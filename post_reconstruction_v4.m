% post_reconstruction_v4.m
% addition of 1D signal extraction code block
clear; clc; close all;
fprintf('=== POST-RECONSTRUCTION PROCESSING ===\n\n');
sign_ass = -1; % chagne to -1 for sign inversion
%% DATA LOADING

data_found = false;
if exist('reconstructed_movie', 'var')
    M = double(reconstructed_movie); data_found = true;
elseif exist('mov_recon', 'var')
    M = double(mov_recon); data_found = true;
elseif exist('mov', 'var')
    M = double(mov); data_found = true;
end

if data_found
    if exist('Fs', 'var'), sampling_rate = Fs; else, sampling_rate = 250; end
end

if ~data_found
    if ~exist('data', 'dir'), error('Data directory not found!'); end
    files = dir('data/reconstructed_ICs_*.mat');
    if isempty(files), error('No reconstruction files found!'); end
    
    fprintf('Available reconstruction files:\n');
    for i = 1:length(files), fprintf('  %d. %s\n', i, files(i).name); end
    
    if length(files) == 1, file_idx = 1; else, file_idx = input('\nSelect file number: '); end
    
    loaded_data = load(fullfile('data', files(file_idx).name));
    M = double(loaded_data.reconstructed_movie);
    if isfield(loaded_data, 'Fs'), sampling_rate = loaded_data.Fs; else, sampling_rate = 250; end
end

[H, W, T] = size(M);
fprintf('Data: %d x %d pixels, %d frames (%.1f Hz)\n', H, W, T, sampling_rate);

% input_file = 'data/averaged_movie_E0B0-B3_unbinned.h5';
% input_file = 'data/motion_compensated_1000/led_E0B0_vsd_corrected.h5';
% 
% dataset_name = '/structural';
% structural_rgb = [];
% 
% if exist(input_file, 'file')
%     try
%         fprintf('Loading structural movie from: %s\n', input_file);
%         mov_struct = h5read(input_file, dataset_name);
%         bg = mean(mov_struct, 3);
%         bg = double(bg);
%         bg_norm = (bg - min(bg(:))) / (max(bg(:)) - min(bg(:)));
%         structural_rgb = cat(3, bg_norm, bg_norm, bg_norm);
%         fprintf('✓ Structural background converted to RGB.\n');
%     catch
%         fprintf('! Warning: Structural load failed. Using black background.\n');
%     end
% else
%     fprintf('! Warning: Structural file not found. Using black background.\n');
% end

if exist('loaded_data', 'var') && isfield(loaded_data, 'input_file')
    input_file = loaded_data.input_file;
elseif ~exist('input_file', 'var')
    input_file = ''; 
end
dataset_name = '/structural';
structural_rgb = [];
if ~isempty(input_file) && exist(input_file, 'file')
    try
        fprintf('Loading structural movie from: %s\n', input_file);
        mov_struct = h5read(input_file, dataset_name);
        bg = mean(mov_struct, 3);
        bg = double(bg);
        bg_min = min(bg(:));
        bg_max = max(bg(:));
        if bg_max > bg_min
            bg_norm = (bg - bg_min) / (bg_max - bg_min);
        else
            bg_norm = bg; % Avoid NaN if image is flat
        end
        structural_rgb = cat(3, bg_norm, bg_norm, bg_norm);
        fprintf('✓ Structural background converted to RGB.\n');
    catch ME
        fprintf('! Warning: Structural load failed.\nError: %s\n', ME.message);
    end
else
    if isempty(input_file)
        fprintf('! Warning: No input filename found in metadata.\n');
    else
        fprintf('! Warning: Original source file not found at: %s\n', input_file);
    end
end
%% =========================================================================
% --- SETTINGS & PROCESSING ---
% =========================================================================
SIGMA = 2.0; 
FLOOR_SENSITIVITY = 0.45;
SATURATION_PCT = 98.5;

% CHANGE: Back to 'jet' for that classic Red/Blue look
CHOSEN_CMAP = 'jet'; 

fprintf('\nProcessing (Sigma=%.1f, Floor=%.2f, Sat=%.1f, Cmap=%s)...\n', ...
    SIGMA, FLOOR_SENSITIVITY, SATURATION_PCT, CHOSEN_CMAP);

baseline = mean(M(:,:,300:375), 3);
M_sub = M - baseline;
M_sub = sign_ass * M_sub;
M_smooth = zeros(H, W, T);
for t = 1:T
    M_smooth(:,:,t) = imgaussfilt(M_sub(:,:,t), SIGMA);
end
% M_smooth = M_smooth(:,:,300:500);

active_data = M_smooth(:,:,350:400);
sat_val = prctile(active_data(:), SATURATION_PCT);
floor_val = sat_val * FLOOR_SENSITIVITY;

%% =========================================================================
% 3. GENERATE MONTAGE
% =========================================================================
start_f = 376 - 8; 
end_f = 376 + 23; 
num_frames = end_f - start_f + 1;
rows = 4; cols = 8; 

figure('Name', 'Montage', 'Color', 'w', 'Position', [10 10 1600 900]);

try, cmap = feval(CHOSEN_CMAP, 256); catch, cmap = jet(256); end

for k = 1:num_frames
    frame_idx = start_f + k - 1;
    img = M_smooth(:,:,frame_idx);
    if frame_idx < 376
        img = -1 * img; 
    end
    img_display = img;
    img_display(img < floor_val) = floor_val;

    subplot(rows, cols, k);

    if ~isempty(structural_rgb)
        image(structural_rgb); 
        hold on;
        h_ov = imagesc(img_display);

        % Transparency Calculation
        alpha_data = (img_display - floor_val) / (sat_val - floor_val);
        alpha_data(alpha_data < 0) = 0;
        alpha_data(alpha_data > 1) = 1;
        alpha_data = alpha_data.^1.5; % Soften edges

        set(h_ov, 'AlphaData', alpha_data);
        colormap(gca, cmap);
        caxis([floor_val, sat_val]);
        hold off;
    else
        imagesc(img_display);
        colormap(gca, cmap);
        caxis([floor_val, sat_val]);
    end

    axis image off;

    if frame_idx == 376
        title('STIMULUS', 'Color', 'r', 'FontWeight', 'bold');
    else
        latency = (frame_idx - 376) * (1000/sampling_rate);
        title(sprintf('%.0f ms', latency), 'Color', 'k');
    end
end

h = colorbar; h.Position = [0.92 0.1 0.02 0.8]; h.Color = 'k'; 
sgtitle(sprintf('Neural Propagation (Sigma=%.1f, Floor=%.2f)', SIGMA, FLOOR_SENSITIVITY), 'Color', 'k');

%% =========================================================================
% 4. FULL MOVIE SLIDER
% =========================================================================
% fprintf('\nGenerating slider figure...\n');
% f_slider = figure('Name', 'Full Movie Slider', 'Color', 'w', 'Position', [100 100 800 600]);
% 
% h_ax = axes('Parent', f_slider, 'Position', [0.05 0.15 0.8 0.75], 'Color', 'w');
% 
% idx = 376;
% img = M_smooth(:,:,idx);
% img_display = img; 
% img_display(img < floor_val) = floor_val;
% 
% if ~isempty(structural_rgb)
%     image(structural_rgb, 'Parent', h_ax);
%     hold(h_ax, 'on');
%     h_img = imagesc(img_display, 'Parent', h_ax);
% 
%     alpha_data = (img_display - floor_val) / (sat_val - floor_val);
%     alpha_data(alpha_data < 0) = 0;
%     alpha_data(alpha_data > 1) = 1;
%     alpha_data = alpha_data.^1.5; 
% 
%     set(h_img, 'AlphaData', alpha_data);
%     colormap(h_ax, cmap);
%     caxis(h_ax, [floor_val, sat_val]);
%     hold(h_ax, 'off');
% else
%     h_img = imagesc(img_display, 'Parent', h_ax);
%     colormap(h_ax, cmap);
%     caxis(h_ax, [floor_val, sat_val]);
% end
% 
% axis(h_ax, 'image', 'off');
% latency = (idx - 376) * (1000/sampling_rate);
% h_title = title(h_ax, sprintf('Frame %d (%.0f ms)', idx, latency), 'Color', 'k', 'FontSize', 14);
% 
% h_cb = colorbar(h_ax);
% h_cb.Position = [0.88 0.15 0.02 0.75];
% h_cb.Color = 'k';
% 
% h_slider = uicontrol('Parent', f_slider, 'Style', 'slider', ...
%     'Units', 'normalized', ...
%     'Position', [0.05 0.05 0.8 0.05], ...
%     'Min', 1, 'Max', T, 'Value', idx, ...
%     'SliderStep', [1/(T-1), 10/(T-1)], ...
%     'BackgroundColor', [0.9 0.9 0.9]); 
% 
% h_text = uicontrol('Parent', f_slider, 'Style', 'text', ...
%     'Units', 'normalized', ...
%     'Position', [0.86 0.05 0.1 0.05], ...
%     'String', sprintf('%d / %d', idx, T), ...
%     'BackgroundColor', 'w', 'ForegroundColor', 'k', 'FontSize', 12);
% 
% set(h_slider, 'Callback', @(s,e) update_frame(s, h_img, h_title, h_text, M_smooth, floor_val, sat_val, sampling_rate, structural_rgb));
% 
% fprintf('\n=== COMPLETE ===\n');
% 
% function update_frame(slider, h_img, h_title, h_text, data, floor_val, sat_val, fs, struc_rgb)
%     idx = round(slider.Value);
%     img = data(:,:,idx);
%     img_disp = img;
%     img_disp(img < floor_val) = floor_val;
% 
%     set(h_img, 'CData', img_disp);
% 
%     if ~isempty(struc_rgb)
%         a_data = (img_disp - floor_val) / (sat_val - floor_val);
%         a_data(a_data < 0) = 0;
%         a_data(a_data > 1) = 1;
%         a_data = a_data.^1.5;
%         set(h_img, 'AlphaData', a_data);
%     end
% 
%     lat = (idx - 376) * (1000/fs);
%     set(h_title, 'String', sprintf('Frame %d (%.0f ms)', idx, lat));
%     set(h_text, 'String', sprintf('%d / %d', idx, size(data,3)));
% end

%% =========================================================================
% fprintf('\nGenerating Raw Diagnostic Montage...\n');
% 
% % Settings for the raw view
% start_f = 376 - 4;  % Start a bit before stimulus
% end_f   = 376 + 11; % Show the immediate response
% num_frames_diag = end_f - start_f + 1;
% 
% % Calculate absolute max to center the colors at 0
% % This ensures 0 is Green, Positive is Red, Negative is Blue
% max_abs_val = max(abs(M_smooth(:))) * 0.8; % *0.8 to make faint signals visible
% 
% figure('Name', 'Raw Data Montage (No Suppression)', 'Color', 'w', 'Position', [50 50 1600 500]);
% 
% rows = 2; cols = 8; % Adjust as needed
% for k = 1:num_frames_diag
%     frame_idx = start_f + k - 1;
% 
%     if frame_idx > size(M_smooth, 3), break; end
% 
%     img_raw = M_smooth(:,:,frame_idx);
% 
%     subplot(rows, cols, k);
% 
%     % 1. Draw Structure (Background)
%     if ~isempty(structural_rgb)
%         image(structural_rgb); hold on;
%     end
% 
%     % 2. Draw Data (Foreground) - NO CLIPPING
%     h_raw = imagesc(img_raw);
% 
%     % 3. Set Constant Visibility (No hiding low values)
%     % We set it to 0.6 so we can see the data AND the background brain
%     set(h_raw, 'AlphaData', 0.6); 
% 
%     % 4. Symmetric Colormap
%     colormap(gca, jet(256));
%     caxis([-max_abs_val, max_abs_val]);
% 
%     axis image off;
% 
%     % Titles
%     if frame_idx == 376
%         title('STIMULUS', 'Color', 'r', 'FontWeight', 'bold');
%     else
%         lat = (frame_idx - 376) * (1000/sampling_rate);
%         title(sprintf('%.1f ms', lat));
%     end
% end
% sgtitle('Raw Data: Blue=Negative, Green=Zero, Red=Positive', 'FontSize', 14);

%% =========================================================================
fprintf('\nGenerating Global Trace Graph...\n');
original_sampling_rate = 250;

global_trace = squeeze(mean(mean(M_smooth, 1), 2));
global_trace = -1 * global_trace;

% global_trace_raw = squeeze(mean(mean(M_smooth, 1), 2));

% This smoothing window size should be much longer than your fast signal (~50 ms)
window_frames = 50; % 50=200ms window at 250 Hz

% 'movmean' or 'sgolay' are good for 1D traces. movmean is simplest.
% The smoothed trace is the low-frequency component (the curve).
% estimated_baseline = smoothdata(global_trace_raw, 'sgolay', window_frames);

% The corrected trace now contains only the fast signals relative to a zero baseline.
% global_trace_corrected = global_trace_raw - estimated_baseline;
% global_trace_corrected = -1 * global_trace_corrected; 

% Frame 1 = 0 ms
time_axis_ms = (0:T-1) * (1000 / original_sampling_rate);
% time_axis_ms = (0:size(M_smooth,3)-1) * (1000 / original_sampling_rate);

% figure;
% plot(time_axis_ms, global_trace_corrected, 'k', 'LineWidth', 1.2); hold on;
% title('Global Trace (Absolute Time)');
% subtitle('Smoothened & Polarity Inverted');
% xlabel('Time (ms)');
% ylabel('Mean Intensity');
% grid on;
% axis tight;
% % xline(1499, '--r', 'Stimulus', 'LabelVerticalAlignment', 'bottom', 'LineWidth', 1);
%%
figure;
plot(time_axis_ms, global_trace, 'k', 'LineWidth', 1.2); hold on;
title('Global Trace (Absolute Time)');
subtitle('Polarity Inverted');
xlabel('Time (ms)');
ylabel('Mean Intensity');
grid on;
axis tight;
% xline(1499, '--r', 'Stimulus', 'LabelVerticalAlignment', 'bottom', 'LineWidth', 1);

fprintf('✓ Global trace plotted (Absolute ms).\n');
%%
% estimated_baseline_Msmooth = smoothdata(M_smooth, 3, 'movmean', window_frames); % change window size
% % The corrected trace now contains only the fast signals relative to a zero baseline.
% M_smooth_corrected = M_smooth - estimated_baseline_Msmooth;
% 
% figure('Name', 'Montage 1', 'Color', 'w', 'Position', [10 10 1600 900]);
% 
% try, cmap = feval(CHOSEN_CMAP, 256); catch, cmap = jet(256); end
% 
% start_f = 376 - 8; 
% end_f = 376 + 23; 
% num_frames = end_f - start_f + 1;
% rows = 4; cols = 8; 
% 
% for k = 1:num_frames
%     frame_idx = start_f + k - 1;
% 
%     % 1. Extract the frame
%     img = M_smooth_corrected(:,:,frame_idx);
% 
%     % --- SIGNAL VALUE INVERSION ---
%     % Invert the sign of the data values before the stimulus
%     if frame_idx < 376
%         img = -1 * img; 
%     end
%     % ------------------------------
% 
%     img_display = img;
% 
%     % Apply the floor (this will hide the boundaries if they became negative)
%     img_display(img < floor_val) = floor_val;
% 
%     subplot(rows, cols, k);
% 
%     if ~isempty(structural_rgb)
%         image(structural_rgb); 
%         hold on;
%         h_ov = imagesc(img_display);
% 
%         % Transparency Calculation
%         alpha_data = (img_display - floor_val) / (sat_val - floor_val);
%         alpha_data(alpha_data < 0) = 0;
%         alpha_data(alpha_data > 1) = 1;
%         alpha_data = alpha_data.^1.5; 
% 
%         set(h_ov, 'AlphaData', alpha_data);
%         colormap(gca, cmap);
%         caxis([floor_val, sat_val]);
%         hold off;
%     else
%         imagesc(img_display);
%         colormap(gca, cmap);
%         caxis([floor_val, sat_val]);
%     end
% 
%     axis image off;
% 
%     if frame_idx == 376
%         title('STIMULUS', 'Color', 'r', 'FontWeight', 'bold');
%     else
%         latency = (frame_idx - 376) * (1000/sampling_rate);
%         title(sprintf('%.0f ms', latency), 'Color', 'k');
%     end
% end
% 
% h = colorbar; h.Position = [0.92 0.1 0.02 0.8]; h.Color = 'k'; 
% sgtitle(sprintf('Neural Propagation (Sigma=%.1f, Floor=%.2f)', SIGMA, FLOOR_SENSITIVITY), 'Color', 'k');


%%
fprintf('\nGenerating Peri-Stimulus Graph (-50ms to +100ms)...\n');
ms_per_frame = 1000 / original_sampling_rate; % Should be 4 ms/frame
pre_stim_ms = 500;
post_stim_ms = 900;
stimulus_frame = round(T / 2); % The "Halfway Point"
frames_pre = round(pre_stim_ms / ms_per_frame);
frames_post = round(post_stim_ms / ms_per_frame);
idx_start = stimulus_frame - frames_pre;
idx_end = stimulus_frame + frames_post;
if idx_start < 1 || idx_end > T
    warning('The requested window (-50ms to +100ms) extends beyond the recording limits.');
else
    peri_stim_trace = global_trace(idx_start:idx_end);
    peri_stim_time = (-frames_pre : frames_post) * ms_per_frame;
    figure;
    plot(peri_stim_time, peri_stim_trace, 'b', 'LineWidth', 1.5); hold on;
    xline(0, '--r', 'Stimulus', 'LabelVerticalAlignment', 'top', 'LineWidth', 1);
    title('Stimulus Plot');
    subtitle(sprintf('Window: -%d ms to +%d ms', pre_stim_ms, post_stim_ms));
    xlabel('Time relative to stimulus (ms)');
    ylabel('dF/F change');
    grid on;
    axis tight;

    fprintf('✓ Peri-stimulus trace plotted.\n');
end

%% ===== DEBUG: PRINT RAW VALUES ACROSS FRAMES =====

% test_frames = 370:385;   % spans your stimulus window
% num_test = length(test_frames);
% 
% % Pick a few meaningful pixels manually
% pix_list = [
%     round(H/2), round(W/2);        % center
%     round(H/2)+10, round(W/2);     % below center
%     round(H/2), round(W/2)+10      % right of center
% ];
% 
% fprintf('\n=== RAW VALUE DEBUG (M_smooth) ===\n');
% fprintf('Sampling Rate: %.1f Hz  |  Frame step: %.2f ms\n\n', ...
%         sampling_rate, 1000/sampling_rate);
% 
% for p = 1:size(pix_list,1)
%     r = pix_list(p,1);
%     c = pix_list(p,2);
% 
%     fprintf('Pixel (%d, %d):\n', r, c);
%     fprintf('Frame\tTime(ms)\tValue\n');
% 
%     base_f = 376;
% 
%     for k = 1:num_test
%         f = test_frames(k);
%         t_ms = (f - base_f) * (1000/sampling_rate);
%         val = M_smooth(r, c, f);
%         fprintf('%d\t%+.1f\t\t%.6f\n', f, t_ms, val);
%     end
% 
%     fprintf('\n');
% end

%% ===== DEBUG: PRINT A SMALL PATCH ACROSS FRAMES =====

% r0 = round(H/2);
% c0 = round(W/2);
% patch_radius = 2;
% 
% test_frames = 374:380;
% 
% for f = test_frames
%     fprintf('\nFrame %d (%.1f ms):\n', ...
%         f, (f-376)*(1000/sampling_rate));
% 
%     patch = M_smooth(r0-patch_radius:r0+patch_radius, ...
%                      c0-patch_radius:c0+patch_radius, f);
% 
%     disp(patch);
% end

%% =========================================================================
% SAVE 1D TRACE DATA
% =========================================================================
% save_choice = input('\nDo you want to save the 1D trace data? (y/n): ', 's');
% if strcmpi(save_choice, 'y') || strcmpi(save_choice, 'yes')
%     fprintf('\nSaving 1D trace data...\n');
% 
%     output_dir = 'data/';
%     if ~exist(output_dir, 'dir')
%         mkdir(output_dir);
%     end
% 
%     timestamp = datestr(now, 'yyyymmdd_HHMMSS');
% 
%     trace_data = struct();
%     trace_data.global_trace = global_trace;
%     trace_data.time_axis_ms = time_axis_ms;
%     trace_data.sampling_rate = original_sampling_rate;
%     trace_data.stimulus_frame = 376;
%     trace_data.processing_params = struct(...
%         'sigma', SIGMA, ...
%         'floor_sensitivity', FLOOR_SENSITIVITY, ...
%         'saturation_pct', SATURATION_PCT, ...
%         'sign_assignment', sign_ass);
% 
%     % Save as .mat file
%     output_filename = fullfile(output_dir, sprintf('global_trace_%s.mat', timestamp));
%     save(output_filename, 'trace_data');
%     fprintf('✓ Saved to: %s\n', output_filename);
% 
%     % % Also save as CSV for easy import into other software
%     % csv_filename = fullfile(output_dir, sprintf('global_trace_%s.csv', timestamp));
%     % csv_table = table(time_axis_ms', global_trace', ...
%     %     'VariableNames', {'Time_ms', 'Mean_Intensity'});
%     % writetable(csv_table, csv_filename);
%     % fprintf('✓ CSV saved to: %s\n', csv_filename);
% 
%     fprintf('\n=== TRACE DATA SAVED SUCCESSFULLY ===\n');
% else
%     fprintf('\nTrace data not saved.\n');
% end

save_choice = input('\nDo you want to save the 1D trace data? (y/n): ', 's');
if strcmpi(save_choice, 'y') || strcmpi(save_choice, 'yes')
    fprintf('\nSaving 1D trace data...\n');
    
    output_dir = 'data/';
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    default_suffix = datestr(now, 'yyyymmdd_HHMMSS');
    user_suffix = input(sprintf('Enter filename suffix (default: "%s"): ', default_suffix), 's');
    if isempty(user_suffix)
        final_suffix = default_suffix;
    else
        final_suffix = user_suffix;
    end
    
    trace_data = struct();
    trace_data.global_trace = global_trace;
    trace_data.time_axis_ms = time_axis_ms;
    trace_data.sampling_rate = original_sampling_rate;
    trace_data.stimulus_frame = 376;
    trace_data.processing_params = struct(...
        'sigma', SIGMA, ...
        'floor_sensitivity', FLOOR_SENSITIVITY, ...
        'saturation_pct', SATURATION_PCT, ...
        'sign_assignment', sign_ass);

    output_filename = fullfile(output_dir, sprintf('global_trace_%s.mat', final_suffix));
    save(output_filename, 'trace_data');
    fprintf('✓ Saved to: %s\n', output_filename);
end