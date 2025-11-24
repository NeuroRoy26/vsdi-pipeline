% -------------------------------------------------------------------------
% Post-threshold processing & analysis for multipliers 3x and 4x
% Updated to use measured pixel calibration:
%   pixel_size_um = 10.7 µm/pixel
%   pixel_area_mm2 = 1.1e-4 mm^2/pixel
%
% - Loads averaged dF/F movie and activation masks (3x, 4x)
% - Performs small morphological clean-up and enforces consecutive-frame
%   activation criterium (optional)
% - Computes per-multiplier metrics:
%     * Initial response latency L
%     * Response amplitude (Amp) using pixels active at L
%     * Peak latency Lp
%     * Activated area A(t) and activation velocity V(t)
%     * Pixel onset map, pixel peak map, pixel amplitude map
%     * Center-of-mass (CoM) trajectory and instantaneous CoM speed
% - Creates diagnostic figures and saves results to .mat and HDF5
%
% NOTE: This version defaults to the pixel calibration provided:
%       pixel_size_um = 10.7  --> pixel_area_mm2 = (10.7e-3)^2 = 1.1449e-4 mm^2
%       For simplicity we round and use pixel_area_mm2 = 1.1e-4 mm^2.
%
% If there is a different calibration saved to data/pixel_calibration.mat
% the script will prefer that file (if it contains pixel_size_um or
% pixel_area_mm2).
% -------------------------------------------------------------------------

clc; clearvars -except; close all;

avg_movie_h5 = 'data/averaged_movie_E0B0-B3_unbinned.h5';      % from run_trial_averaging.m
avg_movie_dataset = '/functional_dff';
mask_h5_template = 'data/activation_mask_%dx.h5';     % files created by analyze_threshold_sensitivity.m
mask_dataset = '/activation_mask';
multipliers = [3, 4];
raw_frame_time_ms = 2;    % original raw frame interval in ms (change if different)
bin_size = 1;             % must match the bin used when creating averaged movie
binned_frame_time_ms = raw_frame_time_ms * bin_size;
stim_onset_frame = 376;    % absolute frame index in binned movie where stimulus/response begins
response_start = stim_onset_frame;

% Use the measured calibration provided (10.7 µm/pixel -> area ≈ 1.1449e-4 mm^2)
pixel_size_um_default = 10.7;          % µm per pixel (user-provided)
pixel_area_mm2_default = (pixel_size_um_default * 1e-3)^2; % mm^2 per pixel

pixel_area_mm2_default = 1.1449e-4;
use_calibration_file = true;
calibration_mat = 'data/pixel_calibration.mat';

min_consecutive_frames = 0;    % require a pixel to be active for at least this many consecutive binned frames
min_cluster_pixels = 5;        % remove spatial clusters smaller than this (in pixels) per frame
apply_morphology = false;       % apply bwareaopen to each frame after consecutive-frame enforcement

out_mat = 'data/activation_analysis_3x_4x.mat';
out_dir_figs = 'data/figs';
out_dir_h5 = 'data/h5';
if ~exist(out_dir_figs, 'dir'), mkdir(out_dir_figs); end
if ~exist(out_dir_h5, 'dir'), mkdir(out_dir_h5); end

verbose = true;

%% 0. Load calibration (if present) or use defaults
pixel_size_um = pixel_size_um_default;
pixel_area_mm2 = pixel_area_mm2_default;

if use_calibration_file && isfile(calibration_mat)
    try
        C = load(calibration_mat);
        if isfield(C, 'pixel_area_mm2')
            pixel_area_mm2 = C.pixel_area_mm2;
        end
        if isfield(C, 'pixel_size_um')
            pixel_size_um = C.pixel_size_um;
        elseif isfield(C, 'pixel_size_um_x') && isfield(C, 'pixel_size_um_y')
            pixel_size_um = mean([C.pixel_size_um_x, C.pixel_size_um_y]);
        end
        if verbose
            fprintf('Loaded calibration from %s\n', calibration_mat);
            fprintf('  Using pixel_size_um = %.3f µm/pixel, pixel_area_mm2 = %.6e mm^2/pixel\n', pixel_size_um, pixel_area_mm2);
        end
    catch
        warning('Could not load calibration file %s - using defaults.', calibration_mat);
    end
else
    if verbose
        fprintf('Using default pixel calibration: %.3f µm/pixel -> %.6e mm^2/pixel\n', pixel_size_um, pixel_area_mm2);
    end
end

% derive pixel_side_mm (used for CoM mm conversion)
pixel_side_mm = pixel_size_um * 1e-3;

%% 1. Load averaged dF/F movie
if ~isfile(avg_movie_h5)
    error('Averaged movie not found: %s', avg_movie_h5);
end
fprintf('Loading averaged dF/F movie: %s\n', avg_movie_h5);
avg_dff = h5read(avg_movie_h5, avg_movie_dataset);
[H, W, T] = size(avg_dff);
fprintf('  Movie size: [%d x %d x %d]\n', H, W, T);

response_end = T; % default

% Create coordinate grids (pixel centers indexed 1..W & 1..H)
[X_coords, Y_coords] = meshgrid(1:W, 1:H);

%% Container for results
results = struct();
results.params.multipliers = multipliers;
results.params.raw_frame_time_ms = raw_frame_time_ms;
results.params.bin_size = bin_size;
results.params.binned_frame_time_ms = binned_frame_time_ms;
results.params.pixel_area_mm2 = pixel_area_mm2;
results.params.pixel_size_um = pixel_size_um;
results.params.pixel_side_mm = pixel_side_mm;
results.params.stim_onset_frame = stim_onset_frame;
results.params.min_consecutive_frames = min_consecutive_frames;
results.params.min_cluster_pixels = min_cluster_pixels;

%% Processing loop for each multiplier
for m = 1:length(multipliers)
    mult = multipliers(m);
    fprintf('\n--- Processing %dx threshold mask ---\n', mult);
    
    mask_h5 = sprintf(mask_h5_template, mult);
    if ~isfile(mask_h5)
        error('Activation mask HDF5 not found: %s', mask_h5);
    end
    
    % Load activation mask (uint8)
    act_uint8 = h5read(mask_h5, mask_dataset);
    % ensure logical
    activation_mask = logical(act_uint8);
    clear act_uint8;
    
    % Sanity check dims
    if ~isequal(size(activation_mask), [H W T])
        error('Activation mask size [%s] does not match averaged movie size [%d %d %d].', ...
            sprintf('%d ', size(activation_mask)), H, W, T);
    end
    
    % Optionally enforce minimum consecutive-frame activation per pixel
    if min_consecutive_frames > 1
        if verbose, fprintf('  Enforcing >= %d consecutive frames per pixel...\n', min_consecutive_frames); end
        win = ones(1, min_consecutive_frames);
        activation_mask_cons = false(H, W, T);
        for irow = 1:H
            for jcol = 1:W
                ts = squeeze(activation_mask(irow, jcol, :)); % T x 1 logical
                conv_ts = conv(double(ts), win, 'same');
                activation_mask_cons(irow, jcol, :) = conv_ts >= min_consecutive_frames;
            end
        end
        activation_mask = activation_mask_cons;
        clear activation_mask_cons conv_ts ts;
    end
    
    % Optionally apply morphological cleaning on each frame
    if apply_morphology && min_cluster_pixels > 0
        if verbose, fprintf('  Applying spatial cluster cleanup (min pixels = %d)...\n', min_cluster_pixels); end
        for t = 1:T
            frame = activation_mask(:, :, t);
            frame = bwareaopen(frame, min_cluster_pixels);
            activation_mask(:, :, t) = frame;
        end
    end
    
    % Compute per-frame activated pixels and percent
    activated_pixels_per_frame = squeeze(sum(sum(activation_mask, 1), 2)); % T x 1
    percent_active_per_frame = 100 * activated_pixels_per_frame / (H * W);
    
    % Initial response latency L: first frame >= response_start with any active pixel
    resp_frames = response_start:response_end;
    L = NaN;
    idx_L = find(activated_pixels_per_frame(resp_frames) > 0, 1, 'first');
    if ~isempty(idx_L)
        L = resp_frames(idx_L);
        if verbose, fprintf('  Initial latency L = %d (frame)\n', L); end
    else
        if verbose, fprintf('  No activation detected after stimulus for %dx.\n', mult); end
    end
    
    % Mask of pixels active at initial latency
    if ~isnan(L)
        initial_pixels_mask = activation_mask(:, :, L);
    else
        initial_pixels_mask = false(H, W);
    end
    
    % Compute Amp and Lp:
    Amp = NaN; Lp = NaN;
    if any(initial_pixels_mask(:))
        response_movie = avg_dff(:, :, response_start:response_end);
        masked_resp = response_movie;
        masked_resp(repmat(~initial_pixels_mask, 1, 1, size(masked_resp, 3))) = -inf;
        [Amp_val, lin_idx] = max(masked_resp(:));
        if isfinite(Amp_val)
            Amp = Amp_val;
            [iy, ix, iz] = ind2sub(size(masked_resp), lin_idx);
            Lp = iz + response_start - 1; % absolute frame index
            if verbose
                fprintf('  Amp (in initially active pixels) = %.6f at frame Lp = %d\n', Amp, Lp);
            end
        end
    else
        if verbose, fprintf('  No initially active pixels to compute Amp.\n'); end
    end
    
    % Activated area A(t) in mm^2 and activation velocity V(t) in mm^2 / s
    A_t_mm2 = activated_pixels_per_frame * pixel_area_mm2; % T x 1
    dt_s = binned_frame_time_ms / 1000;
    V_t_mm2_per_s = [0; diff(A_t_mm2) / dt_s]; % prepend 0 to match length T
    
    % Peak area frame
    [~, peak_area_rel] = max(A_t_mm2(resp_frames));
    peak_area_frame = resp_frames(peak_area_rel);
    
    % Center-of-mass (CoM) trajectory from L to peak_area_frame
    CoM = struct('frame', [], 'x_pix', [], 'y_pix', [], 'x_mm', [], 'y_mm', [], 'total_signal', []);
    if ~isnan(L) && (peak_area_frame >= L)
        frames_com = L:peak_area_frame;
        ncom = length(frames_com);
        CoM.frame = frames_com';
        CoM.x_pix = nan(ncom, 1);
        CoM.y_pix = nan(ncom, 1);
        CoM.x_mm = nan(ncom, 1);
        CoM.y_mm = nan(ncom, 1);
        CoM.total_signal = nan(ncom, 1);
        for ii = 1:ncom
            t = frames_com(ii);
            S = avg_dff(:, :, t);
            S(~activation_mask(:, :, t)) = 0; % zero outside active pixels at that frame
            total_signal = sum(S(:));
            CoM.total_signal(ii) = total_signal;
            if total_signal > 0
                cx = sum(S(:) .* X_coords(:)) / total_signal; % pixel units
                cy = sum(S(:) .* Y_coords(:)) / total_signal;
                CoM.x_pix(ii) = cx;
                CoM.y_pix(ii) = cy;
                CoM.x_mm(ii) = cx * pixel_side_mm;
                CoM.y_mm(ii) = cy * pixel_side_mm;
            end
        end
        % instantaneous CoM speed (mm/s) between consecutive CoM points
        com_speeds_mm_per_s = nan(ncom,1);
        for kcom = 2:ncom
            dx = CoM.x_mm(kcom) - CoM.x_mm(kcom-1);
            dy = CoM.y_mm(kcom) - CoM.y_mm(kcom-1);
            dist = sqrt(dx^2 + dy^2);
            com_speeds_mm_per_s(kcom) = dist / dt_s;
        end
    else
        CoM = [];
        com_speeds_mm_per_s = [];
    end
    
    % Pixel-wise onset, peak-time and amplitude maps (over response window)
    onset_map = zeros(H, W);        % 0 when never active
    peak_time_map = zeros(H, W);    % frame index of max dF/F during response (if any)
    peak_amp_map = zeros(H, W);     % max dF/F during response
    for irow = 1:H
        for jcol = 1:W
            ts = squeeze(activation_mask(irow, jcol, response_start:response_end));
            if any(ts)
                rel_idx = find(ts, 1, 'first');
                onset_map(irow, jcol) = response_start + rel_idx - 1;
            else
                onset_map(irow, jcol) = 0;
            end
            pix_ts = squeeze(avg_dff(irow, jcol, response_start:response_end));
            [pv, pidx] = max(pix_ts);
            peak_amp_map(irow, jcol) = pv;
            peak_time_map(irow, jcol) = response_start + pidx - 1;
        end
    end
    
    % Save per-multiplier results struct
    res = struct();
    res.multiplier = mult;
    res.activation_mask = activation_mask; % logical HxWxT
    res.activated_pixels_per_frame = activated_pixels_per_frame;
    res.percent_active_per_frame = percent_active_per_frame;
    res.L = L;
    res.Amp = Amp;
    res.Lp = Lp;
    res.A_t_mm2 = A_t_mm2;
    res.V_t_mm2_per_s = V_t_mm2_per_s;
    res.peak_area_frame = peak_area_frame;
    res.CoM = CoM;
    res.com_speeds_mm_per_s = com_speeds_mm_per_s;
    res.onset_map = onset_map;
    res.peak_time_map = peak_time_map;
    res.peak_amp_map = peak_amp_map;
    
    results.(['m' num2str(mult)]) = res;
    
    % Save reduced HDF5 for this multiplier (mask and per-frame stats)
    out_h5 = fullfile(out_dir_h5, sprintf('processed_activation_%dx.h5', mult));
    if isfile(out_h5), delete(out_h5); end
    h5create(out_h5, '/activation_mask', size(activation_mask), 'DataType', 'uint8');
    h5write(out_h5, '/activation_mask', uint8(activation_mask));
    h5create(out_h5, '/activated_pixels_per_frame', size(activated_pixels_per_frame), 'DataType', 'double');
    h5write(out_h5, '/activated_pixels_per_frame', activated_pixels_per_frame);
    h5create(out_h5, '/percent_active_per_frame', size(percent_active_per_frame), 'DataType', 'double');
    h5write(out_h5, '/percent_active_per_frame', percent_active_per_frame);
    h5create(out_h5, '/A_t_mm2', size(A_t_mm2), 'DataType', 'double');
    h5write(out_h5, '/A_t_mm2', A_t_mm2);
    h5create(out_h5, '/V_t_mm2_per_s', size(V_t_mm2_per_s), 'DataType', 'double');
    h5write(out_h5, '/V_t_mm2_per_s', V_t_mm2_per_s);
    h5create(out_h5, '/L', 1, 'DataType', 'double');
    h5write(out_h5, '/L', L);
    h5create(out_h5, '/Amp', 1, 'DataType', 'double');
    h5write(out_h5, '/Amp', Amp);
    h5create(out_h5, '/Lp', 1, 'DataType', 'double');
    h5write(out_h5, '/Lp', Lp);
    h5create(out_h5, '/onset_map', size(onset_map), 'DataType', 'double');
    h5write(out_h5, '/onset_map', onset_map);
    h5create(out_h5, '/peak_amp_map', size(peak_amp_map), 'DataType', 'double');
    h5write(out_h5, '/peak_amp_map', peak_amp_map);
    h5create(out_h5, '/peak_time_map', size(peak_time_map), 'DataType', 'double');
    h5write(out_h5, '/peak_time_map', peak_time_map);
    fprintf('  Saved processed results to %s\n', out_h5);
    
    %% Diagnostic Figures for this multiplier
    fig1 = figure('Visible','off','Name',sprintf('A(t) & V(t) %dx',mult),'NumberTitle','off','Position',[100 100 1000 400]);
    subplot(1,2,1);
    plot(1:T, A_t_mm2, 'LineWidth', 2); hold on;
    if ~isnan(L), plot(L, A_t_mm2(L), 'ro', 'MarkerFaceColor','r'); end
    plot(peak_area_frame, A_t_mm2(peak_area_frame), 'ks', 'MarkerFaceColor','k');
    xline(response_start, '--k', 'Baseline End','LabelVerticalAlignment','bottom');
    xlabel('Frame'); ylabel('Activated area (mm^2)'); title(sprintf('Activated area A(t) - %dx',mult));
    grid on; set(gca,'FontSize',11);
    
    subplot(1,2,2);
    plot(1:T, V_t_mm2_per_s, 'LineWidth', 2);
    xlabel('Frame'); ylabel('Activation velocity (mm^2 / s)'); title('Activation velocity V(t)');
    grid on; set(gca,'FontSize',11);
    
    saveas(fig1, fullfile(out_dir_figs, sprintf('A_and_V_%dx.png', mult)));
    close(fig1);
    
    % CoM trajectory figure
    if ~isempty(CoM)
        fig2 = figure('Visible','off','Name',sprintf('CoM %dx',mult),'NumberTitle','off','Position',[100 100 600 600]);
        imagesc(peak_amp_map); axis image; colormap('hot'); colorbar;
        hold on;
        plot(CoM.x_pix, CoM.y_pix, '-o', 'LineWidth', 2, 'MarkerSize', 6, 'Color','cyan', 'MarkerFaceColor','b');
        xlabel('X (pixels)'); ylabel('Y (pixels)');
        title(sprintf('Center of Mass Trajectory %dx (frames %d -> %d)', mult, L, peak_area_frame));
        set(gca,'YDir','normal','FontSize',11);
        saveas(fig2, fullfile(out_dir_figs, sprintf('CoM_%dx.png', mult)));
        close(fig2);
    end
    
    % Onset map figure
    fig3 = figure('Visible','off','Name',sprintf('Onset map %dx',mult),'NumberTitle','off','Position',[100 100 800 600]);
    onset_plot = onset_map;
    onset_plot(onset_plot==0) = NaN; % don't plot non-onset pixels
    imagesc(onset_plot);
    colorbar; axis image; title(sprintf('Pixel Onset Times (%dx) - NaN = no onset', mult));
    saveas(fig3, fullfile(out_dir_figs, sprintf('Onset_map_%dx.png', mult)));
    close(fig3);
    
end

%% Save results to MAT
fprintf('\nSaving full analysis struct to: %s\n', out_mat);
save(out_mat, 'results', '-v7.3');

fprintf('Done. Figures saved to: %s\n', out_dir_figs);
fprintf('HDF5 per-multiplier saved to: %s\n', out_dir_h5);
fprintf('MAT results saved to: %s\n', out_mat);

% --------------------------- END OF SCRIPT --------------------------------