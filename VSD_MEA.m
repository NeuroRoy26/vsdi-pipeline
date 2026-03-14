%% COMBINED PIPELINE: VSD Filmstrip + MEA ERP/CSD Analysis
% Bugfixes & optimisations applied — see changelog at bottom.
clearvars -except cached_D_all cached_bg_path bg_rgb_base freehand_masks mea_grid_pos;
clc; close all;
%% =========================================================================
% SECTION A — CONFIGURATION
% =========================================================================
window_pre_ms  = 0;
window_post_ms = 120;
frame_step     = 1;
alpha_thresholds       = [0.15, 0.15];
heatmap_transparencies = [0.95, 0.95];
component_cmaps        = {@turbo, @turbo};
num_color_bands = 32;
spatial_smoothing = 4.5;
closing_radius    = 12;
% --- Colorbar / heatmap recalculation toggle ---
recalc_colorbar_from_zero = true;
% --- MEA column flip toggle ---
flip_mea_columns = false;
% --- Freehand ROI settings ---
roi_feather_px = 18;
freehand_frame = 376;
bg_path      = 'frame_1.png';
mea_filePath = 'data/ID0503/0503_MEA72_03_ref_ground_512Hz.mat';
MEA_FS       = 512;
cutSecs      = 0.5;
trigDelaySecs = 0.01;
notchFlag    = 1;
bpFlag       = 1;
bpRange      = [4 150];
trialNum     = 3;
erpPreSecs   = 0.125;
erpPostSecs  = 0.200;
baseRange    = [0.01, 0.05];
roiRange     = [-0.02, 0.16];
% --- Fig 11: optical dipole baseline correction ---
% Pre-trigger window (ms) used to compute the resting-state offset.
% Adjust if your pre-trigger epoch is longer/shorter.
optical_baseline_pre_ms  = -20;   % start of baseline window (ms, relative to trigger)
optical_baseline_post_ms =   0;   % end   of baseline window (ms, relative to trigger)

%% =========================================================================
% SECTION B — VSD: LOAD BACKGROUND
% =========================================================================
if exist('bg_rgb_base','var') && exist('cached_bg_path','var') && strcmp(bg_path, cached_bg_path)
    fprintf('Using cached background image.\n');
else
    if ~exist(bg_path, 'file')
        error('Background image not found at: %s', bg_path);
    end
    custom_bg   = imread(bg_path);
    bg_rgb_base = im2double(custom_bg);
    if size(bg_rgb_base, 3) == 1
        bg_rgb_base = repmat(bg_rgb_base, [1 1 3]);
    end
    cached_bg_path = bg_path;
end

%% =========================================================================
% SECTION C — VSD: LOAD NMF FILES
% =========================================================================
files = {
    'data/batch_output500/reconstructed_NMF_Comp1_led_E0B0_vsd_corrected_dff.mat', ...
    'data/batch_output500/reconstructed_NMF_Comp2_led_E0B0_vsd_corrected_dff.mat'
};
path_name = '';
fprintf('Loading hardcoded local files...\n');
merged_label = 'E0B0_500_Global';
match = regexp(files{1}, '(E\d+B\d+)', 'match');
if ~isempty(match)
    merged_label = sprintf('%s_500_Global', match{1});
end

%% =========================================================================
% SECTION D — VSD: PRE-LOAD DATA & COMMON TIMELINE
% =========================================================================
num_files = length(files);
if ~exist('cached_D_all','var') || length(cached_D_all) ~= num_files
    fprintf('Pre-loading %d NMF files...\n', num_files);
    cached_D_all = cell(1, num_files);
    for k = 1:num_files
        cached_D_all{k} = load(fullfile(path_name, files{k}));
    end
end
[orig_h, orig_w, num_frames] = size(cached_D_all{1}.reconstructed_movie);
Fs = cached_D_all{1}.Fs;
all_traces = zeros(num_frames, num_files);
for k = 1:num_files
    mov = cached_D_all{k}.reconstructed_movie;
    all_traces(:,k) = mean(reshape(mov, orig_h*orig_w, num_frames), 1)';
end
sum_trace = sum(all_traces, 2);

%% =========================================================================
% SECTION E — VSD: SMART TRIGGER DETECTION
% =========================================================================
fprintf('Calculating Trigger (Pre-Rise Peak, -3 frames)...\n');
time_sum = (0:num_frames-1)' / Fs;
[peak_amp, peak_idx] = max(sum_trace);
t_peak = time_sum(peak_idx);
lookback_window_sec = 0.20;
window_start_idx    = max(1, peak_idx - round(lookback_window_sec * Fs));
window_indices      = window_start_idx : peak_idx;
global_deriv    = [0; diff(sum_trace)];
deriv_segment   = global_deriv(window_indices);
[~, rel_idx_slope] = max(deriv_segment);
global_idx_slope   = window_indices(rel_idx_slope);
t_slope            = time_sum(global_idx_slope);
amp_at_slope       = sum_trace(global_idx_slope);
trough_idx = global_idx_slope;
max_walk   = round(0.15 * Fs);
for i = global_idx_slope : -1 : 2
    if sum_trace(i-1) >= sum_trace(i) || (global_idx_slope - i) > max_walk
        trough_idx = i; break;
    end
end
pre_peak_idx = trough_idx;
for i = trough_idx : -1 : 2
    if sum_trace(i-1) <= sum_trace(i) || (trough_idx - i) > max_walk
        pre_peak_idx = i; break;
    end
end
shift_frames      = 3;
smart_trigger_idx = max(1, pre_peak_idx - shift_frames);
t_onset           = time_sum(smart_trigger_idx);
onset_amp         = sum_trace(smart_trigger_idx);
fprintf('  Peak: %.3fs | Slope: %.3fs | Onset (-3 frames): %.3fs (Frame %d)\n', ...
        t_peak, t_slope, t_onset, smart_trigger_idx);

%% =========================================================================
%% FIGURE 1 — VSD: GLOBAL SMART TRIGGER DETECTION
%% =========================================================================
figure('Name','Fig 1 - Global Trigger Detection','Color','w','Position',[100 550 1000 420]);
yyaxis left;
plot(time_sum, sum_trace,   'k-', 'LineWidth',1.5,'DisplayName','Global Signal (Sum)'); hold on;
plot(t_peak,   peak_amp,    'r*', 'MarkerSize',10,'LineWidth',1.5,'DisplayName','Main Peak');
plot(t_slope,  amp_at_slope,'bo', 'MarkerSize', 8,'LineWidth',1.5,'DisplayName','Max Slope');
xline(t_onset, 'g-','LineWidth',1.5,'DisplayName',sprintf('Onset (-%d frames)',shift_frames));
plot(t_onset,  onset_amp,   'gs', 'MarkerSize',10,'LineWidth',2,'MarkerFaceColor','w','DisplayName','Onset Trigger');
ylabel('Sum Amplitude (\DeltaF/F_0)','FontSize',11,'FontWeight','bold');
yyaxis right;
plot(time_sum, global_deriv, '-','Color',[0 0.45 0.74 0.3],'LineWidth',1,'DisplayName','Derivative');
ylabel('Rate of Change','FontSize',11,'FontWeight','bold');
title('Trigger Detection','FontSize',12,'FontWeight','bold');
xlabel('Time (s)','FontSize',11,'FontWeight','bold');
legend('Location','best'); grid on; axis tight;
ax_trig = gca;
ax_trig.YAxis(1).Color = 'k';
ax_trig.YAxis(2).Color = [0 0.45 0.74];

%% =========================================================================
% SECTION F — VSD: SETUP PLOT FRAMES & CANVAS
% =========================================================================
bg_rgb   = imresize(bg_rgb_base, [orig_h, orig_w]);
bg_uint8 = im2uint8(bg_rgb);
frames_post  = round((window_post_ms / 1000) * Fs);
plot_frames  = smart_trigger_idx : frame_step : min(num_frames, smart_trigger_idx + frames_post);
num_subplots = length(plot_frames);
cols = ceil(sqrt(num_subplots * 1.2));
rows = ceil(num_subplots / cols);
canvas_combined = repmat(bg_uint8, [rows, cols, 1]);
canvas_combined = canvas_combined(1:rows*orig_h, 1:cols*orig_w, :);
viewer_pre_ms  = 100;
viewer_post_ms = 250;
frames_pre_v   = round((viewer_pre_ms  / 1000) * Fs);
frames_post_v  = round((viewer_post_ms / 1000) * Fs);
plot_frames_v  = max(1, smart_trigger_idx - frames_pre_v) : frame_step : ...
                 min(num_frames, smart_trigger_idx + frames_post_v);

%% =========================================================================
%% SECTION F2 — VSD: PRE-COMPUTE NORM STACKS
%% =========================================================================
norm_stacks = cell(1, num_files);
cmaps_used  = cell(1, num_files);
alphas_used = zeros(1, num_files);
se_close = [];
if closing_radius > 0
    se_close = strel('disk', closing_radius);
end
for k = 1:num_files
    mov        = cached_D_all{k}.reconstructed_movie;
    curr_alpha = alpha_thresholds(min(k, end));
    cmap       = component_cmaps{min(k, end)}(num_color_bands);
    window_data  = mov(:,:, plot_frames);
    smooth_stack = imgaussfilt3(window_data, [spatial_smoothing, spatial_smoothing, 0.001]);
    mn = min(smooth_stack(:)); mx = max(smooth_stack(:));
    norm_stack = (smooth_stack - mn) / (mx - mn + eps);
    if ~isempty(se_close)
        for i = 1:num_subplots
            norm_stack(:,:,i) = imclose(norm_stack(:,:,i), se_close);
        end
    end
    norm_stacks{k} = norm_stack;
    cmaps_used{k}  = cmap;
    alphas_used(k) = curr_alpha;
end

%% =========================================================================
%% SECTION F3 — VSD: FREEHAND ROIs (draw or reuse)
%% =========================================================================
[~, fh_local_idx] = min(abs(plot_frames - freehand_frame));
fh_local_idx = max(1, min(num_subplots, fh_local_idx));
masks_ready = exist('freehand_masks','var') && iscell(freehand_masks) && ...
              numel(freehand_masks) == num_files && ...
              all(cellfun(@(m) isequal(size(m), [orig_h, orig_w]), freehand_masks));
if ~masks_ready
    mat_files = arrayfun(@(k) sprintf('ROI_%d_mask_frame%d.mat', k, freehand_frame), ...
                         1:num_files, 'UniformOutput', false);
    all_mats_exist = all(cellfun(@(f) exist(f,'file') > 0, mat_files));
    if all_mats_exist
        freehand_masks = cell(1, num_files);
        for k = 1:num_files
            tmp = load(mat_files{k}, 'feathered_mask');
            freehand_masks{k} = tmp.feathered_mask;
            fprintf('ROI_%d mask loaded from %s.\n', k, mat_files{k});
        end
        masks_ready = true;
    end
end
if masks_ready
    fprintf('Using existing freehand_masks (skipping interactive draw).\n');
else
    freehand_masks = cell(1, num_files);
    for k = 1:num_files
        fprintf('\n--- Draw Freehand ROI for Component %d (Frame %d) ---\n', k, freehand_frame);
        frame_disp = vsd_compose_frame(norm_stacks{k}(:,:,fh_local_idx), bg_uint8, ...
            cmaps_used{k}, alphas_used(k), orig_h, orig_w, recalc_colorbar_from_zero);
        frame_disp = burn_text(frame_disp, ...
            sprintf('Frame %d | Draw ROI for Comp %d', freehand_frame, k), orig_h, orig_w, false);
        fig_draw = figure('Name', sprintf('Draw Freehand ROI — Component %d', k), ...
            'Color','k','Position',[200 150 800 700]);
        ax_draw = axes('Parent', fig_draw, 'Position', [0.05 0.05 0.90 0.90]);
        imshow(frame_disp, 'Parent', ax_draw);
        title(ax_draw, sprintf('Comp %d | Frame %d | Draw ROI then double-click to finish', k, freehand_frame), ...
            'Color','w','FontSize',11,'FontWeight','bold');
        h_free   = drawfreehand(ax_draw, 'Color',[1 1 0], 'LineWidth',2, 'FaceAlpha',0.15);
        wait(h_free);
        raw_mask = createMask(h_free, frame_disp);
        close(fig_draw);
        dist_in   = bwdist(~raw_mask);
        dist_out  = bwdist( raw_mask);
        signed_d  = double(raw_mask).*dist_in - double(~raw_mask).*dist_out;
        feathered = (signed_d + roi_feather_px) / (2 * roi_feather_px);
        feathered = min(max(feathered, 0), 1);
        freehand_masks{k} = feathered;
        fprintf('    ROI %d captured.\n', k);
    end
end

%% =========================================================================
%% FIGURES 2-3 — VSD: PER-COMPONENT FREEHAND ROI FILMSTRIPS
%% =========================================================================
canvas_overlays = cell(1, num_files);
for k = 1:num_files
    curr_alpha = alphas_used(k);
    curr_trans = heatmap_transparencies(min(k, end));
    cmap       = cmaps_used{k};
    norm_stack = norm_stacks{k};
    feat_mask  = freehand_masks{k};
    fprintf('Rendering Fig %d ROI_%d filmstrip...\n', k+1, k);
    canvas_overlay = repmat(bg_uint8, [rows, cols, 1]);
    canvas_overlay = canvas_overlay(1:rows*orig_h, 1:cols*orig_w, :);
    for i = 1:num_subplots
        img   = norm_stack(:,:,i);
        r_idx = ceil(i/cols);  c_idx = mod(i-1,cols)+1;
        rr    = (r_idx-1)*orig_h+1 : r_idx*orig_h;
        cc    = (c_idx-1)*orig_w+1 : c_idx*orig_w;
        color_rgb      = make_color_rgb(img, cmap, curr_alpha, orig_h, orig_w, recalc_colorbar_from_zero);
        alpha_activity = imgaussfilt(double(img >= curr_alpha), 1.5);
        opacity        = alpha_activity .* feat_mask * curr_trans;
        op3            = repmat(opacity, [1 1 3]);
        frame_out = uint8(double(bg_uint8).*(1-op3) + double(color_rgb).*op3);
        curr_bg = double(canvas_combined(rr,cc,:));
        canvas_combined(rr,cc,:) = uint8(curr_bg.*(1-op3) + double(color_rgb).*op3);
        is_trig  = (plot_frames(i) == smart_trigger_idx);
        time_ms  = ((plot_frames(i) - smart_trigger_idx) / Fs) * 1000;
        frame_out = burn_text(frame_out, sprintf('%+.0f ms',time_ms), orig_h, orig_w, is_trig);
        canvas_overlay(rr,cc,:) = frame_out;
    end
    canvas_overlays{k} = canvas_overlay;
    fig_ov = figure('Name', sprintf('Fig %d - ROI_%d Freehand Overlay', k+1, k), ...
        'Color','w','Position',[50+k*20, 50+k*20, 1600, 900]);
    ax_ov  = axes(fig_ov,'Position',[0.02 0.10 0.88 0.85]);
    imshow(canvas_overlay,'Parent',ax_ov);
    [cb_lo, cb_hi] = colorbar_range(curr_alpha, recalc_colorbar_from_zero);
    add_colorbar_full(fig_ov, cmap, cb_lo, cb_hi, sprintf('ROI\\_\\%d \\DeltaF/F_0',k), []);
    title(ax_ov, sprintf('ROI_%d — Freehand ROI (feather=%dpx) | colorbar from %s', ...
        k, roi_feather_px, ternary_str(recalc_colorbar_from_zero,'0','alpha')), ...
        'FontSize',11,'FontWeight','bold');
end

%% =========================================================================
%% FIGURE 4 — VSD: DUAL ROI OVERLAY FILMSTRIP
%% =========================================================================
if num_files >= 2
    fprintf('Building Fig 4 — Dual ROI filmstrip (%s)...\n', merged_label);
    cmap_merged  = turbo(256);
    canvas_dual  = repmat(bg_uint8, [rows, cols, 1]);
    canvas_dual  = canvas_dual(1:rows*orig_h, 1:cols*orig_w, :);
    for i = 1:num_subplots
        r_idx = ceil(i/cols); c_idx = mod(i-1,cols)+1;
        rr    = (r_idx-1)*orig_h+1 : r_idx*orig_h;
        cc    = (c_idx-1)*orig_w+1 : c_idx*orig_w;
        frame_out = double(bg_uint8);
        for k = 1:num_files
            img         = norm_stacks{k}(:,:,i);
            cmap_k      = cmaps_used{k};
            alpha_k     = alphas_used(k);
            trans_k     = heatmap_transparencies(min(k, end));
            feat_k      = freehand_masks{k};
            color_rgb_k = double(make_color_rgb(img, cmap_k, alpha_k, orig_h, orig_w, recalc_colorbar_from_zero));
            alpha_act   = imgaussfilt(double(img >= alpha_k), 1.5);
            opacity     = alpha_act .* feat_k * trans_k;
            op3         = repmat(opacity, [1 1 3]);
            frame_out   = frame_out.*(1-op3) + color_rgb_k.*op3;
        end
        frame_out = uint8(frame_out);
        is_trig   = (plot_frames(i) == smart_trigger_idx);
        time_ms   = ((plot_frames(i) - smart_trigger_idx) / Fs) * 1000;
        frame_out = burn_text(frame_out, sprintf('%+.0f ms',time_ms), orig_h, orig_w, is_trig);
        canvas_dual(rr,cc,:) = frame_out;
    end
    f_dual  = figure('Name', sprintf('Fig 4 - Dual ROI Overlay (%s)', merged_label), ...
        'Color','w','Position',[170 170 1600 950]);
    ax_dual = axes(f_dual,'Position',[0.02 0.10 0.84 0.85]);
    imshow(canvas_dual,'Parent',ax_dual);
    title(ax_dual, sprintf('Both ROIs overlaid — %s | colorbar from %s', ...
        merged_label, ternary_str(recalc_colorbar_from_zero,'0','alpha')), ...
        'FontSize',12,'FontWeight','bold');
    [cb_lo1,cb_hi1] = colorbar_range(alphas_used(1), recalc_colorbar_from_zero);
    [cb_lo2,cb_hi2] = colorbar_range(alphas_used(2), recalc_colorbar_from_zero);
    add_colorbar_full(f_dual, cmaps_used{1}, cb_lo1, cb_hi1, 'ROI\_1 \DeltaF/F_0', [0.87 0.30 0.015 0.60]);
    add_colorbar_full(f_dual, cmaps_used{2}, cb_lo2, cb_hi2, 'ROI\_2 \DeltaF/F_0', [0.91 0.30 0.015 0.60]);
    merged_movie  = cached_D_all{1}.reconstructed_movie + cached_D_all{2}.reconstructed_movie;
    merged_window = merged_movie(:,:, plot_frames);
    merged_smooth = imgaussfilt3(merged_window, [spatial_smoothing, spatial_smoothing, 0.001]);
    mn = min(merged_smooth(:)); mx = max(merged_smooth(:));
    merged_norm   = (merged_smooth - mn) / (mx - mn + eps);
    if ~isempty(se_close)
        for i = 1:num_subplots
            merged_norm(:,:,i) = imclose(merged_norm(:,:,i), se_close);
        end
    end
end

%% =========================================================================
%% FIGURE 4B — VSD: ROI 1 CORRECTED (ROI 2 AS VIRTUAL GROUND) FILMSTRIP
%% =========================================================================
if num_files >= 2
    fprintf('Building Fig 4B — ROI 1 Corrected (Virtual Ground) filmstrip...\n');
    corrected_stack = norm_stacks{1} - norm_stacks{2};
    corrected_stack(corrected_stack < 0) = 0;
    canvas_corrected = repmat(bg_uint8, [rows, cols, 1]);
    canvas_corrected = canvas_corrected(1:rows*orig_h, 1:cols*orig_w, :);
    cmap_corr  = cmaps_used{1};
    alpha_corr = alphas_used(1);
    trans_corr = heatmap_transparencies(1);
    feat_mask  = freehand_masks{1};
    for i = 1:num_subplots
        img = corrected_stack(:,:,i);
        r_idx = ceil(i/cols); c_idx = mod(i-1,cols)+1;
        rr    = (r_idx-1)*orig_h+1 : r_idx*orig_h;
        cc    = (c_idx-1)*orig_w+1 : c_idx*orig_w;
        color_rgb = make_color_rgb(img, cmap_corr, alpha_corr, orig_h, orig_w, recalc_colorbar_from_zero);
        alpha_act = imgaussfilt(double(img >= alpha_corr), 1.5);
        opacity = alpha_act .* feat_mask * trans_corr;
        op3     = repmat(opacity, [1 1 3]);
        curr_bg   = double(canvas_corrected(rr,cc,:));
        frame_out = uint8(curr_bg.*(1-op3) + double(color_rgb).*op3);
        is_trig   = (plot_frames(i) == smart_trigger_idx);
        time_ms   = ((plot_frames(i) - smart_trigger_idx) / Fs) * 1000;
        frame_out = burn_text(frame_out, sprintf('%+.0f ms',time_ms), orig_h, orig_w, is_trig);
        canvas_corrected(rr,cc,:) = frame_out;
    end
    fig_corr = figure('Name', 'Fig 4B - ROI 1 Corrected (Virtual Ground)', ...
        'Color','w','Position',[120 120 1600 900]);
    ax_corr  = axes(fig_corr,'Position',[0.02 0.10 0.88 0.85]);
    imshow(canvas_corrected, 'Parent', ax_corr);
    [cb_lo, cb_hi] = colorbar_range(alpha_corr, recalc_colorbar_from_zero);
    add_colorbar_full(fig_corr, cmap_corr, cb_lo, cb_hi, 'Corrected \DeltaF/F_0', []);
    title(ax_corr, sprintf('ROI 1 Corrected (ROI 1 minus ROI 2) | Shared artifact removed'), ...
        'FontSize',12,'FontWeight','bold');
    fprintf('  Fig 4B rendered.\n');
end

%% =========================================================================
%% FIGURE 5 — VSD: INTERACTIVE SPATIAL VIEWER
%% =========================================================================
if num_files >= 2
    fprintf('Launching Interactive Spatial Viewer...\n');
    vsd_time_ms    = ((plot_frames_v - smart_trigger_idx) / Fs) * 1000;
    num_subplots_v = length(plot_frames_v);
    comp_norms  = cell(1, num_files+1);
    comp_traces = cell(1, num_files+1);
    comp_cmaps  = cell(1, num_files+1);
    comp_alphas = zeros(1, num_files+1);
    comp_labels = cell(1, num_files+1);
    comp_masks  = cell(1, num_files+1);
    for k = 1:num_files
        mov_k = cached_D_all{k}.reconstructed_movie;
        win_k = mov_k(:,:, plot_frames_v);
        sm_k  = imgaussfilt3(win_k, [spatial_smoothing, spatial_smoothing, 0.001]);
        mn = min(sm_k(:)); mx = max(sm_k(:));
        nm_k  = (sm_k - mn) / (mx - mn + eps);
        if ~isempty(se_close)
            for i = 1:num_subplots_v
                nm_k(:,:,i) = imclose(nm_k(:,:,i), se_close);
            end
        end
        comp_norms{k}  = nm_k;
        comp_traces{k} = mean(reshape(mov_k(:,:,plot_frames_v), orig_h*orig_w, num_subplots_v), 1)';
        comp_cmaps{k}  = component_cmaps{min(k,end)}(256);
        comp_alphas(k) = alpha_thresholds(min(k,end));
        comp_labels{k} = sprintf('ROI_%d', k);
        comp_masks{k}  = freehand_masks{k};
    end
    merged_movie_v  = cached_D_all{1}.reconstructed_movie + cached_D_all{2}.reconstructed_movie;
    merged_smooth_v = imgaussfilt3(merged_movie_v(:,:,plot_frames_v), [spatial_smoothing, spatial_smoothing, 0.001]);
    mn = min(merged_smooth_v(:)); mx = max(merged_smooth_v(:));
    merged_norm_v   = (merged_smooth_v - mn) / (mx - mn + eps);
    if ~isempty(se_close)
        for i = 1:num_subplots_v
            merged_norm_v(:,:,i) = imclose(merged_norm_v(:,:,i), se_close);
        end
    end
    nv = num_files + 1;
    comp_norms{nv}  = merged_norm_v;
    comp_traces{nv} = mean(reshape(merged_movie_v(:,:,plot_frames_v), orig_h*orig_w, num_subplots_v), 1)';
    comp_cmaps{nv}  = cmap_merged;
    comp_alphas(nv) = alpha_thresholds(1);
    comp_labels{nv} = merged_label;
    comp_masks{nv}  = ones(orig_h, orig_w);
    num_views    = nv;
    trace_colors = {[1 0.6 0.2],[1 0.3 0.3],[0.3 1 0.6]};
    hVSD = figure('Name','Fig 5 - Interactive Spatial Viewer','Color','k','Position',[200 100 1400 720]);
    axTrace = axes('Parent',hVSD,'Position',[0.05 0.15 0.42 0.72],'Color','k','XColor','w','YColor','w');
    hold(axTrace,'on');
    hTraceLine = gobjects(num_views,1);
    hTraceDots = gobjects(num_views,1);
    hVLines    = gobjects(num_views,1);
    for k = 1:num_views
        tc = trace_colors{min(k,end)};
        hTraceLine(k) = plot(axTrace, vsd_time_ms, comp_traces{k}, '-','Color',tc,'LineWidth',1.5,'DisplayName',comp_labels{k});
        hTraceDots(k) = plot(axTrace, vsd_time_ms(1), comp_traces{k}(1), 'o','Color',tc,'MarkerFaceColor',tc,'MarkerSize',9,'HandleVisibility','off');
        hVLines(k)    = xline(axTrace, vsd_time_ms(1), '-','Color',tc,'LineWidth',1.2,'Alpha',0.5,'HandleVisibility','off');
    end
    xline(axTrace, 0, '--','Color',[0.9 0.85 0.2],'LineWidth',1.2,'Label','Trigger','LabelVerticalAlignment','bottom','FontSize',9,'HandleVisibility','off');
    hold(axTrace,'off');
    xlabel(axTrace,'Time relative to Trigger (ms)','Color','w','FontSize',11);
    ylabel(axTrace,'\DeltaF/F_0 (spatial mean)','Color','w','FontSize',11);
    title(axTrace,'Click trace to view spatial frame','Color','w','FontSize',11);
    legend(axTrace,'Location','best','TextColor','w','Color','k','EdgeColor','w');
    grid(axTrace,'on'); set(axTrace,'GridColor',[0.3 0.3 0.3]);
    xlim(axTrace,[vsd_time_ms(1), vsd_time_ms(end)]);
    panel_w = 0.16; panel_h = 0.80; panel_gap = 0.01; panel_left_start = 0.52;
    hSpatialImgs   = gobjects(num_views,1);
    hSpatialTitles = gobjects(num_views,1);
    for k = 1:num_views
        axSp = axes('Parent',hVSD,'Position',...
            [panel_left_start+(k-1)*(panel_w+panel_gap), 0.10, panel_w, panel_h]);
        init_frame = vsd_compose_frame_masked(comp_norms{k}(:,:,1), bg_uint8, comp_cmaps{k}, ...
            comp_alphas(k), comp_masks{k}, orig_h, orig_w, recalc_colorbar_from_zero);
        init_frame = burn_text(init_frame, sprintf('%+.0f ms',vsd_time_ms(1)), ...
            orig_h, orig_w, (plot_frames_v(1)==smart_trigger_idx));
        hSpatialImgs(k)   = imshow(init_frame,'Parent',axSp);
        hSpatialTitles(k) = title(axSp, comp_labels{k},'Color',trace_colors{min(k,end)},...
            'FontSize',10,'FontWeight','bold');
        set(axSp,'Color','k');
    end
    setappdata(hVSD,'comp_norms',    comp_norms);
    setappdata(hVSD,'comp_traces',   comp_traces);
    setappdata(hVSD,'comp_cmaps',    comp_cmaps);
    setappdata(hVSD,'comp_alphas',   comp_alphas);
    setappdata(hVSD,'comp_masks',    comp_masks);
    setappdata(hVSD,'comp_labels',   comp_labels);
    setappdata(hVSD,'num_views',     num_views);
    setappdata(hVSD,'vsd_time_ms',   vsd_time_ms);
    setappdata(hVSD,'plot_frames',   plot_frames_v);
    setappdata(hVSD,'smart_trigger_idx', smart_trigger_idx);
    setappdata(hVSD,'num_subplots',  num_subplots_v);
    setappdata(hVSD,'orig_h',        orig_h);
    setappdata(hVSD,'orig_w',        orig_w);
    setappdata(hVSD,'bg_uint8',      bg_uint8);
    setappdata(hVSD,'Fs',            Fs);
    setappdata(hVSD,'hVLines',       hVLines);
    setappdata(hVSD,'hTraceDots',    hTraceDots);
    setappdata(hVSD,'hSpatialImgs',  hSpatialImgs);
    setappdata(hVSD,'hSpatialTitles',hSpatialTitles);
    setappdata(hVSD,'trace_colors',  trace_colors);
    setappdata(hVSD,'recalc_flag',   recalc_colorbar_from_zero);
    set(axTrace,'ButtonDownFcn',@vsdTraceClick);
    set(get(axTrace,'Children'),'HitTest','off');
end
fprintf('\nAll VSD figures rendered.\n');

%% =========================================================================
%% FIGURE 5B — VSD: DIFFERENTIAL TIME COURSE (OPTICAL DIPOLE)
%% =========================================================================
if num_files >= 2
    fprintf('Building Fig 5B - Differential Time Course (ROI_1 - ROI_2)...\n');
    fig5b = figure('Name','Fig 5B - Optical Dipole (ROI_1 - ROI_2)','Color','w','Position',[250 150 900 650]);
    ax1 = subplot(2,1,1);
    plot(ax1, vsd_time_ms, comp_traces{1},'Color',[1 0.6 0.2],'LineWidth',1.5,'DisplayName','ROI_1 (Orange)');
    hold(ax1,'on');
    plot(ax1, vsd_time_ms, comp_traces{2},'Color',[1 0.3 0.3],'LineWidth',1.5,'DisplayName','ROI_2 (Red)');
    xline(ax1, 0,'--k','Trigger','LabelVerticalAlignment','bottom');
    ylabel(ax1,'\DeltaF/F_0','FontWeight','bold');
    title(ax1,'Raw Optical Time Courses (Shared Background Decay)','FontWeight','bold');
    legend(ax1,'Location','best'); grid(ax1,'on');
    xlim(ax1,[vsd_time_ms(1), vsd_time_ms(end)]);
    diff_trace = comp_traces{1} - comp_traces{2};
    ax2 = subplot(2,1,2);
    plot(ax2, vsd_time_ms, diff_trace,'Color',[0.2 0.6 0.8],'LineWidth',2,'DisplayName','Difference (ROI_1 - ROI_2)');
    hold(ax2,'on');
    xline(ax2, 0,'--k','Trigger','LabelVerticalAlignment','bottom');
    ylabel(ax2,'\Delta(\DeltaF/F_0)','FontWeight','bold');
    title(ax2,'Differential Signal (Virtual Differential Electrode)','FontWeight','bold');
    xlabel(ax2,'Time relative to Trigger (ms)','FontWeight','bold');
    legend(ax2,'Location','best'); grid(ax2,'on');
    xlim(ax2,[vsd_time_ms(1), vsd_time_ms(end)]);
    sgtitle(fig5b,'Mimicking MEA Recordings via Optical Subtraction','FontSize',14,'FontWeight','bold');
    fprintf('  Fig 5B rendered.\n');
end

%% =========================================================================
%% SECTION G — MEA: LOAD & PREPROCESS
%% =========================================================================
fprintf('\n--- Starting MEA Pipeline ---\n');
if ~exist(mea_filePath,'file')
    error('MEA file not found: %s', mea_filePath);
end
rawFile = load(mea_filePath);
Y = rawFile.Y;
idx_trig = 70;
idx_data = 2:65;
trigger_raw = Y(idx_trig, :);
mea_data    = Y(idx_data, :);
triggerDiff = round(diff(trigger_raw));
unique_steps = unique(triggerDiff);
triggerConditionedDiff = zeros(size(triggerDiff));
for k = unique_steps(:)'
    if mod(k,2) ~= 0 && k ~= 0
        idx = find(triggerDiff == k);
        triggerConditionedDiff(idx) = sign(k);
    end
end
if trialNum == 1
    if 30157 <= length(triggerConditionedDiff)
        triggerConditionedDiff(30157) = 1;
    end
elseif trialNum == 2
    triggerConditionedDiff(32945) =  1;
    triggerConditionedDiff(39389) = -1;
end
onsetIdx_temp  = find(triggerConditionedDiff ==  1) + 1;
offsetIdx_temp = find(triggerConditionedDiff == -1);
min_len = min(length(onsetIdx_temp), length(offsetIdx_temp));
triggerConditioned = zeros(size(trigger_raw));
for i = 1:min_len
    triggerConditioned(onsetIdx_temp(i) : offsetIdx_temp(i)) = 1;
end
cutSamples = ceil(cutSecs * MEA_FS);
mea_data(:, 1:cutSamples)           = [];
triggerConditioned(:, 1:cutSamples) = [];
if notchFlag
    fNotch  = (50 : 50 : min(MEA_FS/2, 550))';
    fAdd    = [-12 0 12 24];
    fCenter = sort(fNotch + repmat(fAdd, length(fNotch), 1), 'ascend');
    fCenter = fCenter(:);
    fCenter(fCenter >= MEA_FS/2) = [];
    for i = 1:length(fCenter)
        wo  = fCenter(i) / (MEA_FS/2);
        bw  = wo / 35;
        [b,a] = iirnotch(wo, bw);
        mea_data = filtfilt(b, a, mea_data.').';
    end
end
if bpFlag
    [b,a]    = butter(3, 2*bpRange/MEA_FS, 'bandpass');
    mea_data = filtfilt(b, a, mea_data.').';
end
trigDiffFinal = diff(triggerConditioned, 1, 2);
onsetIdx = find(trigDiffFinal == 1) + 1;
onsetIdx = onsetIdx + round(trigDelaySecs * MEA_FS);
onsetIdx(onsetIdx > size(mea_data,2)) = [];
fprintf('MEA Valid Triggers: %d\n', length(onsetIdx));
tERP_raw   = -erpPreSecs : 1/MEA_FS : erpPostSecs;
nTimes_erp = length(tERP_raw);
nCh        = size(mea_data, 1);
nTrials    = length(onsetIdx);
erp_stack = NaN(nCh, nTimes_erp, nTrials);
for i = 1:nTrials
    idx_rel = round(onsetIdx(i) + tERP_raw * MEA_FS);
    if idx_rel(1) >= 1 && idx_rel(end) <= size(mea_data,2)
        erp_stack(:,:,i) = mea_data(:, idx_rel);
    end
end
baseIdx       = tERP_raw >= baseRange(1) & tERP_raw < baseRange(2);
baseline_vals = mean(erp_stack(:, baseIdx, :), 2);
erp_stack     = bsxfun(@minus, erp_stack, baseline_vals);
erpAvg  = mean(erp_stack, 3, 'omitnan');
roiIdx  = tERP_raw >= roiRange(1) & tERP_raw <= roiRange(2);
tFinal  = tERP_raw(roiIdx) * 1000;

%% =========================================================================
%% SECTION G1 — MEA: ELECTRODE LAYOUT
%% =========================================================================
row_map  = [1 1 1 1 1 1 2 2 2 2 2 2 3 3 3 3 3 3 3 3 4 4 4 4 4 4 4 4 5 5 5 5 5 5 5 5 6 6 6 6 6 6 6 6 7 7 7 7 7 7 7 7 8 8 8 8 8 8 9 9 9 9 9 9];
col_map  = [1 2 3 6 7 8 1 2 3 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 2 3 4 5 6 7 2 3 4 5 6 7];
row_chars = 'ABCDEFGHJ';
if flip_mea_columns
    col_map_flipped = (max(col_map)+1) - col_map;
    fprintf('MEA columns: FLIPPED (left-right mirror)\n');
else
    col_map_flipped = col_map;
    fprintf('MEA columns: original orientation\n');
end

%% =========================================================================
%% FIGURE 6 — MEA: RECONSTRUCTED DASHBOARD
%% =========================================================================
figure('Name','Fig 6 - Reconstructed Dashboard (MEA ERPs)','Color','w','Position',[100 50 1400 900]);
clip_uV  = 500;
dyn_ylim = [-clip_uV, clip_uV];
dyn_ytick = [-clip_uV, 0, clip_uV];
for i = 1:64
    r = row_map(i); c = col_map_flipped(i);
    subplot(9, 8, (r-1)*8 + c); hold on;
    xline(0,'Color',[0.4 0.4 0.4],'LineWidth',1.5);
    plot(tFinal, erpAvg(i, roiIdx),'b','LineWidth',1);
    title([row_chars(r) num2str(c)],'FontSize',8,'FontWeight','bold');
    xlim([-20 160]);
    ylim(dyn_ylim);
    set(gca,'YTick',dyn_ytick,'FontSize',7);
    grid off; box on;
    if r < 9, set(gca,'XTickLabel',[]); end
    hold off;
end
sgtitle('Subject 0503 - Averaged ERPs (Reconstructed Dashboard)','FontSize',12,'FontWeight','bold');

%% =========================================================================
%% FIGURE 7 — MEA: INTERACTIVE CSD GUI
%% =========================================================================
fprintf('Building CSD grid and launching Interactive GUI...\n');
nTime  = sum(roiIdx);
V_grid = NaN(9, 8, nTime);
for i = 1:64
    V_grid(row_map(i), col_map_flipped(i), :) = erpAvg(i, roiIdx);
end
dx = 0.625; dy = 0.750;
wx = 1/(dx^2); wy = 1/(dy^2);
CSD_kernel = [0,-wy,0; -wx, 2*(wx+wy), -wx; 0,-wy,0];
[X_g, Y_g] = meshgrid(1:8, 1:9);
CSD_grid   = NaN(size(V_grid));
for t = 1:nTime
    frame      = squeeze(V_grid(:,:,t));
    valid_mask = ~isnan(frame);
    if any(~valid_mask(:))
        frame_filled = griddata(X_g(valid_mask), Y_g(valid_mask), frame(valid_mask), X_g, Y_g, 'cubic');
        nan_still    = isnan(frame_filled);
        if any(nan_still(:))
            fb = griddata(X_g(valid_mask), Y_g(valid_mask), frame(valid_mask), X_g, Y_g, 'nearest');
            frame_filled(nan_still) = fb(nan_still);
        end
    else
        frame_filled = frame;
    end
    pad      = 1;
    fp       = padarray(frame_filled, [pad pad], 'replicate');
    csd_full = conv2(fp, CSD_kernel, 'same');
    csd_frame = csd_full(pad+1:end-pad, pad+1:end-pad);
    csd_frame(~valid_mask) = NaN;
    CSD_grid(:,:,t) = csd_frame;
end
CSD_display = CSD_grid;
CSD_display([1 end], :, :) = NaN;
CSD_display(:, [1 end], :) = NaN;
nFrames_gui = length(tFinal);
max_c    = max(abs(CSD_display(:)), [], 'omitnan');
c_limits = [-max_c*0.8, max_c*0.8];
electrode_map_gui = NaN(9,8);
for i = 1:64
    electrode_map_gui(row_map(i), col_map_flipped(i)) = i;
end
hFig   = figure('Name','Fig 7 - Interactive CSD Viewer','Color','k','Position',[50 50 1300 700],'CloseRequestFcn',@guiCloseReq);
axCSD  = axes('Parent',hFig,'Position',[0.03 0.12 0.50 0.80],'Color','k','XColor','w','YColor','w');
axWave = axes('Parent',hFig,'Position',[0.58 0.15 0.38 0.70],'Color','k','XColor','w','YColor','w');
title(axWave,'Click an electrode on the map to view its waveform','Color','w','FontSize',10);
xlabel(axWave,'Time (ms)','Color','w');
ylabel(axWave,'Amplitude (\muV) / CSD (a.u.)','Color','w');
grid(axWave,'on'); set(axWave,'GridColor',[0.3 0.3 0.3]);
xlim(axWave,[tFinal(1) tFinal(end)]);
frameData = squeeze(CSD_display(:,:,1));
hImg      = imagesc(axCSD, frameData, c_limits);
set(hImg,'AlphaData', double(~isnan(frameData)));
colormap(axCSD, jet(256)); colorbar(axCSD,'Color','w');
axis(axCSD,'square');
set(axCSD,'YDir','reverse','XTick',1:8,'YTick',1:9,...
    'XTickLabel',num2cell(1:8),'YTickLabel',cellstr(row_chars(:)));
xlabel(axCSD,'Column','Color','w'); ylabel(axCSD,'Row','Color','w');
hTitle = title(axCSD, sprintf('CSD  |  %.1f ms  |  [SPACE] Play/Pause  |  [R] Replay  |  ← → Scrub',tFinal(1)),...
    'Color','w','FontSize',9);
hold(axCSD,'on');
hMarker = plot(axCSD, NaN, NaN, 'w+','MarkerSize',14,'LineWidth',2);
hold(axCSD,'off');
btnPlay  = uicontrol('Style','pushbutton','String','▶  Play','Position',[60 20 110 35],...
    'BackgroundColor',[0.2 0.6 0.2],'ForegroundColor','w','FontSize',11,'FontWeight','bold','Callback',@onPlay);
uicontrol('Style','pushbutton','String','↺  Replay','Position',[185 20 110 35],...
    'BackgroundColor',[0.2 0.4 0.7],'ForegroundColor','w','FontSize',11,'FontWeight','bold','Callback',@onReplay);
sldFrame = uicontrol('Style','slider','Min',1,'Max',nFrames_gui,'Value',1,...
    'SliderStep',[1/(nFrames_gui-1), 10/(nFrames_gui-1)],'Position',[315 22 300 22],'Callback',@onSlider);
lblTime  = uicontrol('Style','text','String',sprintf('%.1f ms',tFinal(1)),...
    'Position',[625 20 80 25],'BackgroundColor','k','ForegroundColor','w','FontSize',10);
setappdata(hFig,'CSD_display',       CSD_display);
setappdata(hFig,'erpAvg',            erpAvg);
setappdata(hFig,'erp_stack',         erp_stack);
setappdata(hFig,'tFinal',            tFinal);
setappdata(hFig,'roiIdx',            roiIdx);
setappdata(hFig,'row_map',           row_map);
setappdata(hFig,'col_map_flipped',   col_map_flipped);
setappdata(hFig,'row_chars',         row_chars);
setappdata(hFig,'electrode_map',     electrode_map_gui);
setappdata(hFig,'nFrames',           nFrames_gui);
setappdata(hFig,'c_limits',          c_limits);
setappdata(hFig,'frame',             1);
setappdata(hFig,'playing',           false);
setappdata(hFig,'timerObj',          []);
setappdata(hFig,'hImg',              hImg);
setappdata(hFig,'hTitle',            hTitle);
setappdata(hFig,'hMarker',           hMarker);
setappdata(hFig,'btnPlay',           btnPlay);
setappdata(hFig,'sldFrame',          sldFrame);
setappdata(hFig,'lblTime',           lblTime);
setappdata(hFig,'axWave',            axWave);
setappdata(hFig,'axCSD',             axCSD);
set(hImg,'ButtonDownFcn',@onImageClick);
set(hFig,'KeyPressFcn',@onKeyPress);

%% =========================================================================
%% SECTION G2 — MEA GRID PLACEMENT
%% =========================================================================
mea_grid_mat   = 'mea_grid_pos.mat';
vsd_time_ms_f8 = ((plot_frames - smart_trigger_idx) / Fs) * 1000;
n_vsd_frames   = length(plot_frames);
% INCREASING GRID SIZE DEFAULT BY 2x (was 0.60/0.70)
mea_grid_w_default = round(orig_w * 1.20);
mea_grid_h_default = round(orig_h * 1.40);
grid_ready = exist('mea_grid_pos','var') && isnumeric(mea_grid_pos) && numel(mea_grid_pos)==4;
if ~grid_ready && exist(mea_grid_mat,'file')
    tmp = load(mea_grid_mat,'mea_grid_pos');
    mea_grid_pos = tmp.mea_grid_pos;
    grid_ready   = true;
    fprintf('MEA grid position loaded from %s.\n', mea_grid_mat);
end
if ~grid_ready
    fprintf('\n--- Place MEA electrode grid ---\n');
    fprintf('    Click anywhere (even outside the image) to reposition.\n');
    fprintf('    Press Enter to confirm.\n');
    ref_fi    = max(1, round(n_vsd_frames/2));
    ref_frame = double(bg_uint8);
    for k = 1:num_files
        img   = norm_stacks{k}(:,:,ref_fi);
        crk   = double(make_color_rgb(img, cmaps_used{k}, alphas_used(k), orig_h, orig_w, recalc_colorbar_from_zero));
        aact  = imgaussfilt(double(img >= alphas_used(k)), 1.5);
        op3   = repmat(aact .* freehand_masks{k} * heatmap_transparencies(min(k,end)), [1 1 3]);
        ref_frame = ref_frame.*(1-op3) + crk.*op3;
    end
    ref_frame = uint8(ref_frame);
    elec_norm_x = (col_map_flipped - 1) / (8-1);
    elec_norm_y = (row_map         - 1) / (9-1);
    init_cx     = orig_w / 2;
    init_cy     = orig_h / 2;
    mea_grid_w  = mea_grid_w_default;
    mea_grid_h  = mea_grid_h_default;
    
    fig_grid = figure('Name','Place MEA Grid — click to move, Enter to confirm',...
        'Color','k','Position',[200 150 900 750],'Pointer','crosshair');
    ax_grid  = axes('Parent',fig_grid,'Position',[0.05 0.05 0.90 0.90]);
    hRefImg  = imshow(ref_frame,'Parent',ax_grid);
    hold(ax_grid,'on');
    
    % --- NEW: Expand axes limits so you can click in the void outside the image ---
    xlim(ax_grid, [-orig_w*0.8, orig_w*1.8]);
    ylim(ax_grid, [-orig_h*0.8, orig_h*1.8]);
    
    title(ax_grid,'Click anywhere to position grid  |  Press Enter to confirm',...
        'Color','y','FontSize',12,'FontWeight','bold');
    [init_ex,init_ey,init_bx,init_by] = grid_from_centre(init_cx,init_cy,mea_grid_w,mea_grid_h,elec_norm_x,elec_norm_y);
    h_dots   = scatter(ax_grid,init_ex,init_ey,30,'w','filled','MarkerEdgeColor','k','LineWidth',0.5);
    h_border = plot(ax_grid,init_bx,init_by,'y--','LineWidth',1.2);
    drawnow;
    
    setappdata(fig_grid,'ax_grid',     ax_grid);
    setappdata(fig_grid,'h_dots',      h_dots);
    setappdata(fig_grid,'h_border',    h_border);
    setappdata(fig_grid,'mea_grid_w',  mea_grid_w);
    setappdata(fig_grid,'mea_grid_h',  mea_grid_h);
    setappdata(fig_grid,'elec_norm_x', elec_norm_x);
    setappdata(fig_grid,'elec_norm_y', elec_norm_y);
    setappdata(fig_grid,'cx',          init_cx);
    setappdata(fig_grid,'cy',          init_cy);
    
    % --- NEW: Detect clicks on the whole window, not just the image ---
    set(fig_grid, 'WindowButtonDownFcn', @mea_grid_click);
    set(fig_grid, 'KeyPressFcn',    @mea_grid_keypress);
    set(fig_grid, 'CloseRequestFcn',@(src,~) mea_grid_confirm_close(src));
    waitfor(fig_grid,'UserData','confirmed');
    
    if isvalid(fig_grid)
        cx_final = getappdata(fig_grid,'cx');
        cy_final = getappdata(fig_grid,'cy');
        delete(fig_grid);
    else
        cx_final = orig_w / 2;
        cy_final = orig_h / 2;
    end
    
    % --- NEW: Clamping constraints removed entirely! Grid goes where you click. ---
    
    mea_grid_pos = [cx_final - mea_grid_w/2, cy_final - mea_grid_h/2, ...
                    cx_final + mea_grid_w/2, cy_final + mea_grid_h/2];
    save(mea_grid_mat,'mea_grid_pos');
    fprintf('MEA grid position saved (centre: %.0f, %.0f)\n', cx_final, cy_final);
end
mea_tl_x = mea_grid_pos(1); mea_tl_y = mea_grid_pos(2);
mea_br_x = mea_grid_pos(3); mea_br_y = mea_grid_pos(4);
mea_grid_w = mea_br_x - mea_tl_x;
mea_grid_h = mea_br_y - mea_tl_y;
elec_px = zeros(64,2);
for ei = 1:64
    r = row_map(ei); c = col_map_flipped(ei);
    elec_px(ei,1) = mea_tl_x + (c-1)/(8-1) * mea_grid_w;
    elec_px(ei,2) = mea_tl_y + (r-1)/(9-1) * mea_grid_h;
end

%% =========================================================================
%% FIGURE 8 — VSD+CSD OVERLAY VIDEO
%% =========================================================================
fprintf('\nBuilding Fig 8 - VSD+CSD Overlay Video...\n');
csd_per_elec = zeros(64, length(tFinal));
for ei = 1:64
    csd_per_elec(ei,:) = squeeze(CSD_grid(row_map(ei), col_map_flipped(ei), :))';
end
csd_resampled = zeros(64, n_vsd_frames);
for ei = 1:64
    csd_resampled(ei,:) = interp1(tFinal, csd_per_elec(ei,:), vsd_time_ms_f8, 'linear', NaN);
end
cmap_csd = jet(256);
csd_clim = max(abs(csd_per_elec(:)), [], 'omitnan') * 0.8;
if csd_clim == 0, csd_clim = 1; end
dot_size = max(80, round(orig_h * orig_w / 4000));
vid8 = VideoWriter(sprintf('Fig8_VSD_CSD_%s.mp4', merged_label),'MPEG-4');
vid8.FrameRate = 15; vid8.Quality = 95; open(vid8);
hF8 = figure('Name','Fig 8 - VSD+CSD (rendering...)','Color','k',...
    'Position',[100 100 orig_w+120 orig_h+100],'Visible','on');
ax8   = axes('Parent',hF8,'Position',[0.02 0.10 0.85 0.85],'Color','k','XColor','none','YColor','none');
ax8cb = axes('Parent',hF8,'Position',[0.89 0.15 0.025 0.70]);
image(ax8cb, flipud(permute(reshape(cmap_csd,[256,1,3]),[1 2 3])));
tick_p = round(linspace(1,256,5)); tick_v = linspace(-csd_clim,csd_clim,5);
set(ax8cb,'XTick',[],'YTick',tick_p,...
    'YTickLabel',arrayfun(@(v)sprintf('%.0f',v),fliplr(tick_v),'UniformOutput',false),...
    'TickDir','out','FontSize',8,'YColor','w');
ylabel(ax8cb,'CSD (a.u.)','Color','w','FontSize',10,'FontWeight','bold');
has_insertText = exist('insertText','file') > 0;
fnt_sz = max(14, round(orig_h*0.06));
fprintf('  Pre-computing merged VSD frames...\n');
merged_frames_cell = cell(1, n_vsd_frames);
for fi = 1:n_vsd_frames
    merged_frames_cell{fi} = vsd_compose_frame_masked(merged_norm(:,:,fi), bg_uint8, ...
        cmap_merged, alpha_thresholds(1), ones(orig_h,orig_w), orig_h, orig_w, recalc_colorbar_from_zero);
end
for fi = 1:n_vsd_frames
    vsd_frame = merged_frames_cell{fi};
    t_ms_now  = vsd_time_ms_f8(fi);
    is_trig   = (plot_frames(fi) == smart_trigger_idx);
    if has_insertText
        vsd_frame = insertText(vsd_frame,[5,orig_h-fnt_sz-8],sprintf('%+.1f ms',t_ms_now),...
            'FontSize',fnt_sz,'TextColor','white','BoxColor','black','BoxOpacity',0.75);
        if is_trig
            vsd_frame = insertText(vsd_frame,[5,5],'TRIGGER','FontSize',fnt_sz,...
                'TextColor','white','BoxColor','green','BoxOpacity',0.8);
        end
    else
        vsd_frame = burn_text(vsd_frame, sprintf('%+.1f ms',t_ms_now), orig_h, orig_w, is_trig);
    end
    cla(ax8); imshow(vsd_frame,'Parent',ax8); hold(ax8,'on');
    csd_vals = csd_resampled(:,fi); valid = ~isnan(csd_vals);
    if any(valid)
        idx_c = max(1,min(256, round(((csd_vals(valid)+csd_clim)/(2*csd_clim))*255)+1));
        scatter(ax8, elec_px(valid,1), elec_px(valid,2), dot_size, cmap_csd(idx_c,:), ...
            'filled','MarkerEdgeColor','w','LineWidth',0.6);
    end
    title(ax8, sprintf('VSD+CSD  |  t = %+.1f ms  |  %s', t_ms_now, merged_label),...
        'Color','w','FontSize',11,'FontWeight','bold');
    hold(ax8,'off'); drawnow;
    writeVideo(vid8, getframe(hF8));
    if mod(fi,10)==0, fprintf('  Fig8 frame %d / %d\n',fi,n_vsd_frames); end
end
close(vid8);
set(hF8,'Name','Fig 8 - VSD+CSD [saved]');
fprintf('  Fig 8 video saved.\n');

%% =========================================================================
%% FIGURE 9 — DUAL ROI OVERLAY VIDEO
%% =========================================================================
fprintf('\nBuilding Fig 9 - Dual ROI Overlay Video...\n');
vid9_name = sprintf('Fig9_DualROI_%s.mp4', merged_label);
vid9 = VideoWriter(vid9_name,'MPEG-4'); vid9.FrameRate = 15; vid9.Quality = 95; open(vid9);
hF9  = figure('Name','Fig 9 - Dual ROI Overlay (rendering...)','Color','k',...
    'Position',[150 150 orig_w+200 orig_h+100],'Visible','on');
ax9  = axes('Parent',hF9,'Position',[0.02 0.08 0.82 0.88],'Color','k','XColor','none','YColor','none');
[cb_lo1,cb_hi1] = colorbar_range(alphas_used(1), recalc_colorbar_from_zero);
[cb_lo2,cb_hi2] = colorbar_range(alphas_used(2), recalc_colorbar_from_zero);
add_colorbar_full(hF9, cmaps_used{1}, cb_lo1, cb_hi1, 'ROI_1 \DeltaF/F_0', [0.85 0.35 0.015 0.55]);
add_colorbar_full(hF9, cmaps_used{2}, cb_lo2, cb_hi2, 'ROI_2 \DeltaF/F_0', [0.90 0.35 0.015 0.55]);
fnt_sz9 = max(14, round(orig_h*0.06));
for fi = 1:n_vsd_frames
    frame_out = double(bg_uint8);
    for k = 1:num_files
        img         = norm_stacks{k}(:,:,fi);
        cmap_k      = cmaps_used{k};
        alpha_k     = alphas_used(k);
        trans_k     = heatmap_transparencies(min(k,end));
        feat_k      = freehand_masks{k};
        color_rgb_k = double(make_color_rgb(img, cmap_k, alpha_k, orig_h, orig_w, recalc_colorbar_from_zero));
        alpha_act   = imgaussfilt(double(img >= alpha_k), 1.5);
        opacity     = alpha_act .* feat_k * trans_k;
        op3         = repmat(opacity,[1 1 3]);
        frame_out   = frame_out.*(1-op3) + color_rgb_k.*op3;
    end
    frame_out = uint8(frame_out);
    t_ms_now  = vsd_time_ms_f8(fi);
    is_trig   = (plot_frames(fi) == smart_trigger_idx);
    if has_insertText
        frame_out = insertText(frame_out,[5,orig_h-fnt_sz9-8],sprintf('%+.1f ms',t_ms_now),...
            'FontSize',fnt_sz9,'TextColor','white','BoxColor','black','BoxOpacity',0.75);
        if is_trig
            frame_out = insertText(frame_out,[5,5],'TRIGGER','FontSize',fnt_sz9,...
                'TextColor','white','BoxColor','green','BoxOpacity',0.8);
        end
    else
        frame_out = burn_text(frame_out, sprintf('%+.1f ms',t_ms_now), orig_h, orig_w, is_trig);
    end
    imshow(frame_out,'Parent',ax9); hold(ax9,'on');
    csd_vals = csd_resampled(:,fi); valid = ~isnan(csd_vals);
    if any(valid)
        idx_c = max(1,min(256, round(((csd_vals(valid)+csd_clim)/(2*csd_clim))*255)+1));
        scatter(ax9, elec_px(valid,1), elec_px(valid,2), dot_size, cmap_csd(idx_c,:),...
            'filled','MarkerEdgeColor','w','LineWidth',0.6);
    end
    hold(ax9,'off');
    title(ax9, sprintf('Dual ROI Overlay  |  t = %+.1f ms  |  %s', t_ms_now, merged_label),...
        'Color','w','FontSize',11,'FontWeight','bold');
    drawnow;
    writeVideo(vid9, getframe(hF9));
    if mod(fi,10)==0, fprintf('  Fig9 frame %d / %d\n',fi,n_vsd_frames); end
end
close(vid9);
set(hF9,'Name',sprintf('Fig 9 - Dual ROI Overlay [saved: %s]',vid9_name));
fprintf('  Fig 9 video saved: %s\n', vid9_name);

%% =========================================================================
%% FIGURE 10 — VSD OPTICAL DIPOLE vs. MEA ELECTRODE OVERLAY
%% =========================================================================
if num_files >= 2
    fprintf('\nBuilding Fig 10 - VSD Optical Dipole vs MEA Overlay...\n');
    raw_diff_trace    = comp_traces{1} - comp_traces{2};
    smooth_diff_trace = smoothdata(raw_diff_trace, 'movmean', 5);
    target_row = 3;
    target_col = 2;
    ch_idx = find(row_map == target_row & col_map_flipped == target_col, 1);
    if ~isempty(ch_idx)
        mea_trace_target = erpAvg(ch_idx, roiIdx);
        fig10 = figure('Name','Fig 10 - Optical vs Electrical Dipole Overlay','Color','w','Position',[300 200 1000 500]);
        yyaxis left;
        plot(vsd_time_ms, smooth_diff_trace,'-','Color',[0.2 0.6 0.8],'LineWidth',2.5,...
            'DisplayName','Smoothed Optical Dipole (ROI_1 - ROI_2)');
        ylabel('\Delta(\DeltaF/F_0) [Optical]','Color',[0.2 0.6 0.8],'FontWeight','bold');
        set(gca,'YColor',[0.2 0.6 0.8]);
        yyaxis right;
        plot(tFinal, mea_trace_target,'-','Color',[0.8 0.2 0.2],'LineWidth',2,...
            'DisplayName','MEA Electrode D2 (Amplitude)');
        ylabel('Amplitude (\muV) [Electrical]','Color',[0.8 0.2 0.2],'FontWeight','bold');
        set(gca,'YColor',[0.8 0.2 0.2]);
        xline(0,'--k','Trigger','LabelVerticalAlignment','bottom');
        title('Direct Comparison: Filtered Optical Dipole vs. Local Electrical Activity (C2)',...
            'FontSize',14,'FontWeight','bold');
        xlabel('Time relative to Trigger (ms)','FontWeight','bold');
        xlim([-20 160]); grid on;
        all_lines = findobj(gca,'Type','Line');
        named     = all_lines(~cellfun(@isempty,{all_lines.DisplayName}));
        legend(named,'Location','best');
        fprintf('  Fig 10 rendered.\n');
    else
        fprintf('  Could not find electrode at row %d, col %d for Fig 10 overlay.\n', target_row, target_col);
    end
end

%% =========================================================================
%% FIGURE 11 — DUAL ROI OVERLAY VIDEO (BASELINE-CORRECTED OPTICAL DIPOLE)
%% =========================================================================
if num_files >= 2
    fprintf('\nBuilding Fig 11 - Dual ROI Overlay Video (Baseline-Corrected Optical Dipole)...\n');
    raw_diff_full    = comp_traces{1} - comp_traces{2};
    smooth_diff_full = smoothdata(raw_diff_full, 'movmean', 5);
    bl_mask  = vsd_time_ms >= optical_baseline_pre_ms & ...
               vsd_time_ms <= optical_baseline_post_ms;
    if sum(bl_mask) < 2
        warning('Fig 11: baseline window contains fewer than 2 samples — using first frame only.');
        bl_mask(1) = true;
    end
    dipole_offset        = mean(smooth_diff_full(bl_mask));
    smooth_diff_centered = smooth_diff_full - dipole_offset;
    fprintf('  Optical dipole baseline offset removed: %.4e (window %.0f–%.0f ms)\n', ...
            dipole_offset, optical_baseline_pre_ms, optical_baseline_post_ms);
    [~, pf_in_v] = ismember(plot_frames, plot_frames_v);
    missing = pf_in_v == 0;
    if any(missing)
        for mi = find(missing)
            [~, nn] = min(abs(plot_frames_v - plot_frames(mi)));
            pf_in_v(mi) = nn;
        end
    end
    dipole_filmstrip = smooth_diff_centered(pf_in_v);
    dip_max  = max(abs(dipole_filmstrip));
    if dip_max == 0, dip_max = 1; end
    vid11_name = sprintf('Fig11_DualROI_BaselineCorrected_%s.mp4', merged_label);
    vid11 = VideoWriter(vid11_name,'MPEG-4');
    vid11.FrameRate = 15; vid11.Quality = 95; open(vid11);
    hF11  = figure('Name','Fig 11 - Dual ROI + Baseline-Corrected Dipole (rendering...)',...
        'Color','k','Position',[200 200 orig_w+280 orig_h+120],'Visible','on');
    ax11  = axes('Parent',hF11,'Position',[0.02 0.08 0.72 0.88],...
        'Color','k','XColor','none','YColor','none');
    add_colorbar_full(hF11, cmaps_used{1}, cb_lo1, cb_hi1, 'ROI\_1 \DeltaF/F_0', [0.76 0.35 0.015 0.55]);
    add_colorbar_full(hF11, cmaps_used{2}, cb_lo2, cb_hi2, 'ROI\_2 \DeltaF/F_0', [0.81 0.35 0.015 0.55]);
    ax11t = axes('Parent',hF11,'Position',[0.87 0.12 0.11 0.75],...
        'Color',[0.08 0.08 0.08],'XColor','w','YColor','w','FontSize',8);
    hold(ax11t,'on');
    plot(ax11t, dipole_filmstrip, 1:n_vsd_frames, '-',...
        'Color',[0.3 0.6 0.9 0.35],'LineWidth',0.8);
    hDipDot = plot(ax11t, dipole_filmstrip(1), 1, 'o',...
        'Color',[0.3 0.6 0.9],'MarkerFaceColor',[0.3 0.6 0.9],'MarkerSize',7);
    xline(ax11t, 0, '--','Color',[0.9 0.85 0.2 0.7],'LineWidth',1.0,...
        'Label','0','LabelHorizontalAlignment','right','FontSize',7);
    xlim(ax11t, [-dip_max*1.15, dip_max*1.15]);
    ylim(ax11t, [0.5, n_vsd_frames+0.5]);
    set(ax11t,'YDir','reverse','YTick',[]);
    xlabel(ax11t,'\Delta(\DeltaF/F_0)','Color','w','FontSize',7);
    title(ax11t, sprintf('Optical\nDipole\n(zero-centred)'),...
        'Color',[0.6 0.85 1.0],'FontSize',7,'FontWeight','bold');
    hold(ax11t,'off');
    fnt_sz11 = max(14, round(orig_h*0.06));
    for fi = 1:n_vsd_frames
        frame_out = double(bg_uint8);
        for k = 1:num_files
            img         = norm_stacks{k}(:,:,fi);
            cmap_k      = cmaps_used{k};
            alpha_k     = alphas_used(k);
            trans_k     = heatmap_transparencies(min(k,end));
            feat_k      = freehand_masks{k};
            color_rgb_k = double(make_color_rgb(img, cmap_k, alpha_k, orig_h, orig_w, recalc_colorbar_from_zero));
            alpha_act   = imgaussfilt(double(img >= alpha_k), 1.5);
            opacity     = alpha_act .* feat_k * trans_k;
            op3         = repmat(opacity,[1 1 3]);
            frame_out   = frame_out.*(1-op3) + color_rgb_k.*op3;
        end
        frame_out = uint8(frame_out);
        t_ms_now  = vsd_time_ms_f8(fi);
        is_trig   = (plot_frames(fi) == smart_trigger_idx);
        if has_insertText
            frame_out = insertText(frame_out,[5,orig_h-fnt_sz11-8],sprintf('%+.1f ms',t_ms_now),...
                'FontSize',fnt_sz11,'TextColor','white','BoxColor','black','BoxOpacity',0.75);
            if is_trig
                frame_out = insertText(frame_out,[5,5],'TRIGGER','FontSize',fnt_sz11,...
                    'TextColor','white','BoxColor','green','BoxOpacity',0.8);
            end
        else
            frame_out = burn_text(frame_out, sprintf('%+.1f ms',t_ms_now), orig_h, orig_w, is_trig);
        end
        imshow(frame_out,'Parent',ax11); hold(ax11,'on');
        csd_vals = csd_resampled(:,fi); valid = ~isnan(csd_vals);
        if any(valid)
            idx_c = max(1,min(256, round(((csd_vals(valid)+csd_clim)/(2*csd_clim))*255)+1));
            scatter(ax11, elec_px(valid,1), elec_px(valid,2), dot_size, cmap_csd(idx_c,:),...
                'filled','MarkerEdgeColor','w','LineWidth',0.6);
        end
        hold(ax11,'off');
        title(ax11, sprintf('Dual ROI + CSD  |  t = %+.1f ms  |  %s  |  Dipole DC-removed', ...
            t_ms_now, merged_label),'Color','w','FontSize',10,'FontWeight','bold');
        set(hDipDot,'XData', dipole_filmstrip(fi), 'YData', fi);
        drawnow;
        writeVideo(vid11, getframe(hF11));
        if mod(fi,10)==0
            fprintf('  Fig11 frame %d / %d  |  dipole = %.3e\n', fi, n_vsd_frames, dipole_filmstrip(fi));
        end
    end
    close(vid11);
    set(hF11,'Name',sprintf('Fig 11 - Dual ROI + Baseline-Corrected Dipole [saved: %s]',vid11_name));
    fprintf('  Fig 11 video saved: %s\n', vid11_name);
    dipole_time_ms       = vsd_time_ms(:);
    dipole_raw           = raw_diff_full(:);
    dipole_smooth        = smooth_diff_full(:);
    dipole_smooth_zeroed = smooth_diff_centered(:);
    save(sprintf('Fig11_OpticalDipole_BaselineCorrected_%s.mat', merged_label), ...
        'dipole_time_ms','dipole_raw','dipole_smooth','dipole_smooth_zeroed','dipole_offset');
    fprintf('  Baseline-corrected dipole trace saved to .mat file.\n');
end

%% =========================================================================
%% FIGURE 12 — CSD TIME-LAPSE MONTAGE
%% =========================================================================
fprintf('\nBuilding Fig 12 - CSD Time-Lapse Montage...\n');
montage_times = [0, 8, 12, 14, 18, 20, 22, 24]; % Selected times in ms
num_montage = length(montage_times);
fig12 = figure('Name','Fig 12 - CSD Montage','Color','w','Position',[100 100 1600 300]);
for mi = 1:num_montage
    [~, t_idx] = min(abs(tFinal - montage_times(mi)));
    ax_m = subplot(1, num_montage, mi, 'Parent', fig12);
    frameData = squeeze(CSD_display(:,:,t_idx));
    imagesc(ax_m, frameData, c_limits);
    set(get(ax_m,'Children'),'AlphaData', double(~isnan(frameData)));
    colormap(ax_m, jet(256));
    axis(ax_m,'square');
    set(ax_m,'YDir','reverse','XTick',[],'YTick',[]);
    title(ax_m, sprintf('%+.1f ms', tFinal(t_idx)), 'FontSize', 11, 'FontWeight', 'bold');
end
sgtitle(fig12, 'CSD Spatiotemporal Evolution', 'FontSize', 14, 'FontWeight', 'bold');

%% =========================================================================
%% FIGURE 13 — DUAL ROI + CSD TIME-LAPSE MONTAGE
%% =========================================================================
if num_files >= 2
    fprintf('\nBuilding Fig 13 - Dual ROI + CSD Montage...\n');
    fig13 = figure('Name','Fig 13 - VSD+CSD Montage','Color','k','Position',[100 450 1600 350]);
    for mi = 1:num_montage
        [~, v_idx] = min(abs(vsd_time_ms_f8 - montage_times(mi)));
        ax_m = subplot(1, num_montage, mi, 'Parent', fig13);
        frame_out = double(bg_uint8);
        for k = 1:num_files
            img         = norm_stacks{k}(:,:,v_idx);
            cmap_k      = cmaps_used{k};
            alpha_k     = alphas_used(k);
            trans_k     = heatmap_transparencies(min(k,end));
            feat_k      = freehand_masks{k};
            color_rgb_k = double(make_color_rgb(img, cmap_k, alpha_k, orig_h, orig_w, recalc_colorbar_from_zero));
            alpha_act   = imgaussfilt(double(img >= alpha_k), 1.5);
            opacity     = alpha_act .* feat_k * trans_k;
            op3         = repmat(opacity,[1 1 3]);
            frame_out   = frame_out.*(1-op3) + color_rgb_k.*op3;
        end
        frame_out = uint8(frame_out);
        imshow(frame_out, 'Parent', ax_m); hold(ax_m, 'on');
        csd_vals = csd_resampled(:,v_idx); valid = ~isnan(csd_vals);
        if any(valid)
            idx_c = max(1,min(256, round(((csd_vals(valid)+csd_clim)/(2*csd_clim))*255)+1));
            scatter(ax_m, elec_px(valid,1), elec_px(valid,2), dot_size*0.6, cmap_csd(idx_c,:),...
                'filled','MarkerEdgeColor','w','LineWidth',0.5);
        end
        hold(ax_m, 'off');
        title(ax_m, sprintf('%+.1f ms', vsd_time_ms_f8(v_idx)), 'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold');
    end
    sgtitle(fig13, sprintf('Dual ROI + CSD Evolution (%s)', merged_label), 'Color', 'w', 'FontSize', 14, 'FontWeight', 'bold');
end

%% =========================================================================
%% EXPORT FREEHAND ROIs
%% =========================================================================
for k = 1:num_files
    binary_mask    = freehand_masks{k} >= 0.5;
    feathered_mask = freehand_masks{k};
    fname_mat      = sprintf('ROI_%d_mask_frame%d.mat', k, freehand_frame);
    save(fname_mat, 'binary_mask','feathered_mask');
    imwrite(uint8(binary_mask*255),    sprintf('ROI_%d_binary_frame%d.png',   k, freehand_frame));
    imwrite(uint8(feathered_mask*255), sprintf('ROI_%d_feathered_frame%d.png',k, freehand_frame));
    fprintf('ROI_%d exported: .mat + binary .png + feathered .png\n', k);
end

fprintf('\n=== Pipeline Complete ===\n');
fprintf('Figs 1-4 : VSD (Trigger, ROI_1, ROI_2, Dual Overlay)\n');
fprintf('Fig  5   : VSD Interactive Spatial Viewer\n');
fprintf('Fig  5B  : VSD Differential Time Course (ROI_1 - ROI_2)\n');
fprintf('Fig  6   : MEA Reconstructed Dashboard\n');
fprintf('Fig  7   : MEA Interactive CSD GUI\n');
fprintf('Fig  8   : VSD+CSD Overlay Video\n');
fprintf('Fig  9   : Dual ROI Overlay Video — %s\n', vid9_name);
fprintf('Fig  10  : VSD Optical Dipole vs MEA Overlay\n');
fprintf('Fig  11  : Dual ROI + CSD Overlay (Baseline-Corrected Optical Dipole) — %s\n', vid11_name);
fprintf('Fig  12  : CSD Time-Lapse Montage\n');
fprintf('Fig  13  : Dual ROI + CSD Time-Lapse Montage\n');
fprintf('Toggle   : recalc_colorbar_from_zero = %d\n', recalc_colorbar_from_zero);
fprintf('Toggle   : flip_mea_columns = %d\n', flip_mea_columns);
fprintf('ROI frame: %d  |  feather: %d px\n', freehand_frame, roi_feather_px);

%% =========================================================================
%% LOCAL HELPER FUNCTIONS
%% =========================================================================
function color_rgb = make_color_rgb(img, cmap, alpha_thresh, orig_h, orig_w, recalc)
    num_colors = size(cmap, 1);
    if recalc
        idx_mat = round(img * (num_colors - 1)) + 1;
    else
        idx_mat = round(((img - alpha_thresh) / (1 - alpha_thresh + eps)) * (num_colors - 1)) + 1;
    end
    idx_mat = max(1, min(num_colors, idx_mat));
    color_r = reshape(cmap(idx_mat,1), orig_h, orig_w);
    color_g = reshape(cmap(idx_mat,2), orig_h, orig_w);
    color_b = reshape(cmap(idx_mat,3), orig_h, orig_w);
    color_rgb = im2uint8(cat(3, color_r, color_g, color_b));
end
function [lo, hi] = colorbar_range(alpha_thresh, recalc)
    if recalc, lo = 0; hi = 1;
    else,      lo = alpha_thresh; hi = 1;
    end
end
function s = ternary_str(cond, s_true, s_false)
    if cond, s = s_true; else, s = s_false; end
end
function img = burn_text(img, tstr, orig_h, orig_w, is_trigger)
    if nargin < 5, is_trigger = false; end
    if exist('insertText','file')
        fnt_size = max(18, round(orig_h * 0.08));
        y_pos    = orig_h - fnt_size - 10;
        img = insertText(img,[5,y_pos],tstr,'FontSize',fnt_size,...
            'TextColor','white','BoxColor','black','BoxOpacity',0.8);
        if is_trigger
            img = insertText(img,[5,5],'TRIGGER','FontSize',fnt_size,...
                'TextColor','white','BoxColor','green','BoxOpacity',0.8);
        end
    else
        warning('off','MATLAB:print:ContentTypeImageSuggested');
        tmp_fig = figure('Visible','off','Position',[0 0 orig_w orig_h],'Color','k');
        imshow(img,'Parent',axes('Parent',tmp_fig,'Position',[0 0 1 1]));
        text(5, orig_h-20, tstr,'Color','w','FontSize',10,'Units','pixels','VerticalAlignment','bottom');
        if is_trigger
            text(5,5,'TRIGGER','Color','w','BackgroundColor','g','FontSize',10,'Units','pixels');
        end
        frame_cap = getframe(tmp_fig);
        img       = imresize(frame_cap.cdata, [orig_h orig_w]);
        close(tmp_fig);
        warning('on','MATLAB:print:ContentTypeImageSuggested');
    end
end
function add_colorbar_full(fig, cmap, lo, hi, label_str, pos)
    n = size(cmap, 1);
    if isempty(pos), pos = [0.92 0.30 0.02 0.65]; end
    tick_vals = linspace(lo, hi, 5);
    tick_pos  = round(linspace(1, n, 5));
    ax_cb     = axes(fig,'Position',pos);
    image(ax_cb, flipud(permute(reshape(cmap,[n,1,3]),[1 2 3])));
    set(ax_cb,'XTick',[],'YTick',tick_pos,...
        'YTickLabel',arrayfun(@(v)sprintf('%.2f',v),fliplr(tick_vals),'UniformOutput',false),...
        'TickDir','out','FontSize',9);
    ylabel(ax_cb, label_str,'FontSize',11,'FontWeight','bold');
end
function frame_rgb = vsd_compose_frame(img, bg_uint8, cmap, alpha_thresh, orig_h, orig_w, recalc)
    color_rgb  = make_color_rgb(img, cmap, alpha_thresh, orig_h, orig_w, recalc);
    alpha_mask = imgaussfilt(double(img >= alpha_thresh), 1.5);
    a3         = repmat(alpha_mask,[1 1 3]);
    frame_rgb  = uint8(double(bg_uint8).*(1-a3) + double(color_rgb).*a3);
end
function frame_rgb = vsd_compose_frame_masked(img, bg_uint8, cmap, alpha_thresh, feat_mask, orig_h, orig_w, recalc)
    color_rgb  = make_color_rgb(img, cmap, alpha_thresh, orig_h, orig_w, recalc);
    alpha_act  = imgaussfilt(double(img >= alpha_thresh), 1.5);
    opacity    = alpha_act .* feat_mask;
    a3         = repmat(opacity,[1 1 3]);
    frame_rgb  = uint8(double(bg_uint8).*(1-a3) + double(color_rgb).*a3);
end
function [ex, ey, bx, by] = grid_from_centre(cx, cy, gw, gh, enx, eny)
    tl_x = cx - gw/2;  tl_y = cy - gh/2;
    ex   = tl_x + enx * gw;
    ey   = tl_y + eny * gh;
    bx   = [tl_x, tl_x+gw, tl_x+gw, tl_x,    tl_x];
    by   = [tl_y, tl_y,    tl_y+gh,  tl_y+gh, tl_y];
end
function mea_grid_click(src, ~)
    % Find the figure regardless of where the user clicked
    if strcmp(src.Type, 'figure')
        fig = src;
    else
        fig = ancestor(src,'figure');
    end
    
    ax     = getappdata(fig,'ax_grid');
    cp     = get(ax,'CurrentPoint');
    cx     = cp(1,1);  cy = cp(1,2);
    gw     = getappdata(fig,'mea_grid_w');
    gh     = getappdata(fig,'mea_grid_h');
    enx    = getappdata(fig,'elec_norm_x');
    eny    = getappdata(fig,'elec_norm_y');
    h_dots = getappdata(fig,'h_dots');
    h_bord = getappdata(fig,'h_border');
    
    [ex,ey,bx,by] = grid_from_centre(cx,cy,gw,gh,enx,eny);
    set(h_dots,'XData',ex,'YData',ey);
    set(h_bord,'XData',bx,'YData',by);
    title(ax,sprintf('Grid centre: (%.0f, %.0f)  |  Click to reposition  |  Enter to confirm',cx,cy),...
        'Color','y','FontSize',11,'FontWeight','bold');
    setappdata(fig,'cx',cx); setappdata(fig,'cy',cy);
    drawnow;
end
function mea_grid_keypress(src, evt)
    switch evt.Key
        case {'return','enter'}, src.UserData = 'confirmed';
        case 'escape',           src.UserData = 'confirmed';
    end
end
function mea_grid_confirm_close(fig)
    fig.UserData = 'confirmed';
end
function vsdTraceClick(src, evt)
    hVSD         = ancestor(src,'figure');
    click_ms     = evt.IntersectionPoint(1);
    vsd_time_ms  = getappdata(hVSD,'vsd_time_ms');
    num_subplots = getappdata(hVSD,'num_subplots');
    num_views    = getappdata(hVSD,'num_views');
    orig_h       = getappdata(hVSD,'orig_h');
    orig_w       = getappdata(hVSD,'orig_w');
    plot_frames  = getappdata(hVSD,'plot_frames');
    smart_trig   = getappdata(hVSD,'smart_trigger_idx');
    hVLines      = getappdata(hVSD,'hVLines');
    hTraceDots   = getappdata(hVSD,'hTraceDots');
    hSpatialImgs = getappdata(hVSD,'hSpatialImgs');
    hSpatialTitles = getappdata(hVSD,'hSpatialTitles');
    comp_traces  = getappdata(hVSD,'comp_traces');
    comp_norms   = getappdata(hVSD,'comp_norms');
    comp_cmaps   = getappdata(hVSD,'comp_cmaps');
    comp_alphas  = getappdata(hVSD,'comp_alphas');
    comp_labels  = getappdata(hVSD,'comp_labels');
    comp_masks   = getappdata(hVSD,'comp_masks');
    bg_uint8     = getappdata(hVSD,'bg_uint8');
    trace_colors = getappdata(hVSD,'trace_colors');
    recalc_flag  = getappdata(hVSD,'recalc_flag');
    [~,frame_i] = min(abs(vsd_time_ms - click_ms));
    frame_i = max(1, min(num_subplots, frame_i));
    t_ms    = vsd_time_ms(frame_i);
    is_trig = (plot_frames(frame_i) == smart_trig);
    for k = 1:num_views
        tc = trace_colors{min(k,end)};
        set(hVLines(k),    'Value',t_ms);
        set(hTraceDots(k), 'XData',t_ms,'YData',comp_traces{k}(frame_i));
        fr = vsd_compose_frame_masked(comp_norms{k}(:,:,frame_i), bg_uint8, ...
            comp_cmaps{k}, comp_alphas(k), comp_masks{k}, orig_h, orig_w, recalc_flag);
        fr = burn_text(fr, sprintf('%+.0f ms',t_ms), orig_h, orig_w, is_trig);
        set(hSpatialImgs(k),   'CData',fr);
        set(hSpatialTitles(k), 'String',sprintf('%s  |  t = %+.0f ms',comp_labels{k},t_ms));
    end
    drawnow;
end
function updateFrame(hFig, f)
    nF = getappdata(hFig,'nFrames'); f = max(1,min(nF,round(f)));
    setappdata(hFig,'frame',f);
    CSD_d    = getappdata(hFig,'CSD_display'); tF = getappdata(hFig,'tFinal');
    c_lim    = getappdata(hFig,'c_limits');    hImg = getappdata(hFig,'hImg');
    hTitle   = getappdata(hFig,'hTitle');      sldFrame = getappdata(hFig,'sldFrame');
    lblTime  = getappdata(hFig,'lblTime');      axCSD = getappdata(hFig,'axCSD');
    fd = squeeze(CSD_d(:,:,f));
    set(hImg,'CData',fd,'AlphaData',double(~isnan(fd)));
    clim(axCSD, c_lim);
    set(hTitle,'String',sprintf('CSD  |  %.1f ms  |  [SPACE] Play/Pause  |  [R] Replay  |  ← → Scrub',tF(f)));
    set(sldFrame,'Value',f); set(lblTime,'String',sprintf('%.1f ms',tF(f)));
    drawnow limitrate;
end
function onPlay(src,~)
    hFig    = ancestor(src,'figure');
    playing = getappdata(hFig,'playing');
    btnPlay = getappdata(hFig,'btnPlay');
    tF      = getappdata(hFig,'tFinal');
    nF      = getappdata(hFig,'nFrames');
    if playing
        t = getappdata(hFig,'timerObj');
        if ~isempty(t) && isvalid(t), stop(t); delete(t); end
        setappdata(hFig,'playing',false); setappdata(hFig,'timerObj',[]);
        set(btnPlay,'String','▶  Play','BackgroundColor',[0.2 0.6 0.2]);
    else
        f = getappdata(hFig,'frame');
        if f >= nF, setappdata(hFig,'frame',1); end
        setappdata(hFig,'playing',true);
        set(btnPlay,'String','⏸  Pause','BackgroundColor',[0.7 0.4 0.1]);
        dt_ms  = tF(2) - tF(1);
        period = max(dt_ms / 1000, 0.04);
        t = timer('ExecutionMode','fixedRate','Period',period,...
            'TimerFcn',{@timerStep,hFig},'StopFcn',{@timerStopped,hFig});
        setappdata(hFig,'timerObj',t); start(t);
    end
end
function timerStep(~,~,hFig)
    if ~isvalid(hFig), return; end
    nF = getappdata(hFig,'nFrames'); f = getappdata(hFig,'frame');
    if f >= nF
        t = getappdata(hFig,'timerObj');
        if ~isempty(t) && isvalid(t), stop(t); end
        return;
    end
    setappdata(hFig,'frame',f+1); updateFrame(hFig,f+1);
end
function timerStopped(~,~,hFig)
    if ~isvalid(hFig), return; end
    t = getappdata(hFig,'timerObj');
    if ~isempty(t) && isvalid(t), delete(t); end
    setappdata(hFig,'playing',false); setappdata(hFig,'timerObj',[]);
    btnPlay = getappdata(hFig,'btnPlay');
    if isvalid(btnPlay), set(btnPlay,'String','▶  Play','BackgroundColor',[0.2 0.6 0.2]); end
end
function onReplay(src,~)
    hFig    = ancestor(src,'figure');
    playing = getappdata(hFig,'playing');
    if playing
        t = getappdata(hFig,'timerObj');
        if ~isempty(t) && isvalid(t), stop(t); delete(t); end
        setappdata(hFig,'playing',false); setappdata(hFig,'timerObj',[]);
        set(getappdata(hFig,'btnPlay'),'String','▶  Play','BackgroundColor',[0.2 0.6 0.2]);
    end
    setappdata(hFig,'frame',1); updateFrame(hFig,1);
    onPlay(getappdata(hFig,'btnPlay'),[]);
end
function onSlider(src,~)
    hFig    = ancestor(src,'figure');
    playing = getappdata(hFig,'playing');
    if playing
        t = getappdata(hFig,'timerObj');
        if ~isempty(t) && isvalid(t), stop(t); delete(t); end
        setappdata(hFig,'playing',false); setappdata(hFig,'timerObj',[]);
        set(getappdata(hFig,'btnPlay'),'String','▶  Play','BackgroundColor',[0.2 0.6 0.2]);
    end
    updateFrame(hFig, round(src.Value));
end
function onKeyPress(src,evt)
    hFig = src; f = getappdata(hFig,'frame');
    switch evt.Key
        case 'space',      onPlay(getappdata(hFig,'btnPlay'),[]);
        case 'r',          onReplay(getappdata(hFig,'btnPlay'),[]);
        case 'rightarrow', updateFrame(hFig,f+1);
        case 'leftarrow',  updateFrame(hFig,f-1);
    end
end
function onImageClick(src, evt)
    hFig          = ancestor(src,'figure');
    pt            = evt.IntersectionPoint;
    col = round(pt(1)); row = round(pt(2));
    electrode_map = getappdata(hFig,'electrode_map');
    axWave        = getappdata(hFig,'axWave');
    hMarker       = getappdata(hFig,'hMarker');
    erpAvg_g      = getappdata(hFig,'erpAvg');
    erp_stack_g   = getappdata(hFig,'erp_stack');
    tFinal_g      = getappdata(hFig,'tFinal');
    roiIdx_g      = getappdata(hFig,'roiIdx');
    row_map_g     = getappdata(hFig,'row_map');
    col_map_f     = getappdata(hFig,'col_map_flipped');
    row_chars_g   = getappdata(hFig,'row_chars');
    CSD_d         = getappdata(hFig,'CSD_display');
    if row<1||row>9||col<1||col>8, return; end
    ch = electrode_map(row,col);
    if isnan(ch)
        title(axWave,'No electrode here','Color','w','FontSize',11);
        return;
    end
    set(hMarker,'XData',col,'YData',row);
    label = [row_chars_g(row_map_g(ch)) num2str(col_map_f(ch))];
    cla(axWave,'reset');
    set(axWave,'Color','k','XColor','w','YColor','w');
    yyaxis(axWave,'left'); hold(axWave,'on');
    sweeps = squeeze(erp_stack_g(ch, roiIdx_g, :));
    plot(axWave, tFinal_g, sweeps,    'Color',[0.4 0.4 0.4 0.45]);
    plot(axWave, tFinal_g, erpAvg_g(ch,roiIdx_g), 'w','LineWidth',2);
    ylabel(axWave,'Amplitude (\muV)','Color','w');
    set(axWave,'YColor','w');
    csd_tr = squeeze(CSD_d(row_map_g(ch), col_map_f(ch), :))';
    yyaxis(axWave,'right');
    plot(axWave, tFinal_g, csd_tr,'r-','LineWidth',1.5);
    ylabel(axWave,'CSD (a.u.)','Color','r');
    set(axWave,'YColor','r');
    yyaxis(axWave,'left');
    xline(axWave,0,'--','Color',[0.9 0.85 0.2],'LineWidth',1.2,'Label','Stim');
    hold(axWave,'off');
    title(axWave,['Electrode ' label '  |  Grey: sweeps  |  White: avg  |  Red: CSD'],...
        'Color','w','FontSize',9);
    xlabel(axWave,'Time (ms)','Color','w');
    xlim(axWave,[tFinal_g(1) tFinal_g(end)]);
    grid(axWave,'on');
    set(axWave,'GridColor',[0.3 0.3 0.3],'FontSize',8,'XColor','w');
end
function guiCloseReq(src,~)
    t = getappdata(src,'timerObj');
    if ~isempty(t) && isvalid(t), stop(t); delete(t); end
    delete(src);
end