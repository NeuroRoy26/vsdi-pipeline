% VSD_Filmstrip_Montage_Batch.m
% Modified: Publication Quality (Interpolated, Smoothed, Clean UI)
% WITH SMART TRIGGER DETECTION (Pre-Rise Peak - 3 Frame Shift)
clearvars -except files path_name bg_rgb_base custom_bg cached_bg_path cached_D_all;
clc; close all;

%% 1. Configuration (UPDATED FOR INDIVIDUAL COMPONENT TWEAKING)
window_pre_ms  = 20;
window_post_ms = 100;
frame_step     = 1;

% --- COMPONENT-SPECIFIC SETTINGS ---
% Array of values [Comp1, Comp2, ...]. 
alpha_thresholds       = [0.45, 0.35]; 
heatmap_transparencies = [0.85, 0.95]; 
% Assign different colormaps to visually separate the ROIs in Figure 5
component_cmaps = {@spring, @hot}; 

% Global visual settings
spatial_smoothing = 4.5;
closing_radius    = 12;     % Morphological closing radius (pixels)
line_thickness    = 1;
bg_path = 'C:\Roy\MSc\Thesis\Scripts\frame_1.png';

%% 2. Load Background
if exist('bg_rgb_base', 'var') && exist('cached_bg_path', 'var') && strcmp(bg_path, cached_bg_path)
    fprintf('Using cached background image.\n');
else
    if exist(bg_path, 'file')
        custom_bg = imread(bg_path);
        bg_rgb_base = im2double(custom_bg);
        if size(bg_rgb_base, 3) == 1
            bg_rgb_base = repmat(bg_rgb_base, [1 1 3]);
        end
        cached_bg_path = bg_path; 
    else
        error('Background image not found at: %s', bg_path);
    end
end

%% 3. Select Files
if ~exist('files', 'var') || ~exist('path_name', 'var') || isequal(files, 0)
    fprintf('Select NNMF components\n');
    [files, path_name] = uigetfile('*.mat', 'Select NMF .mat files', 'MultiSelect', 'on');
    if isequal(files, 0), return; end
    if ischar(files), files = {files}; end
else
    fprintf('Using previously selected files from: %s\n', path_name);
end

se_fat = strel('disk', max(1, floor(line_thickness/2)));

%% 3.5 Pre-pass: Load Data & Calculate Common Timeline
num_files = length(files);
if ~exist('cached_D_all', 'var') || length(cached_D_all) ~= num_files
    fprintf('Pre-loading %d files to calculate common timeline...\n', num_files);
    cached_D_all = cell(1, num_files);
    for k = 1:num_files
        cached_D_all{k} = load(fullfile(path_name, files{k}));
    end
end

% Extract traces and compute common trigger
all_traces = [];
for k = 1:num_files
    mov = cached_D_all{k}.reconstructed_movie;
    trace = squeeze(mean(mean(mov,1),2));
    all_traces = [all_traces, trace];
end

% Sum all traces to find the global event across all components
sum_trace = sum(all_traces, 2);

Fs = cached_D_all{1}.Fs;
[orig_h, orig_w, num_frames] = size(cached_D_all{1}.reconstructed_movie);

%% 3.6 SMART TRIGGER DETECTION (Local Pre-Rise Peak - 3 Frames)
fprintf('Calculating Smart Trigger (Pre-Rise Peak Shifted by -3 frames)...\n');
time_sum = (0:num_frames-1)' / Fs;

% 1. Find the Absolute Peak
[peak_amp, peak_idx] = max(sum_trace);
t_peak = time_sum(peak_idx);

% 2. Find Max Derivative (The steep rising edge)
% Look back 200ms from the peak to find the steepest slope
lookback_window_sec = 0.20;
window_start_idx = max(1, peak_idx - round(lookback_window_sec * Fs));
window_indices = window_start_idx : peak_idx;

global_deriv = [0; diff(sum_trace)];
deriv_segment = global_deriv(window_indices);
[slope_val, rel_idx_slope] = max(deriv_segment);

global_idx_slope = window_indices(rel_idx_slope);
t_slope = time_sum(global_idx_slope);
amp_at_slope = sum_trace(global_idx_slope);

% 3. Find the IMMEDIATE Trough (Foot of the slope)
trough_idx = global_idx_slope;
for i = global_idx_slope : -1 : 2
    if sum_trace(i-1) >= sum_trace(i)
        trough_idx = i;
        break;
    end
    if (global_idx_slope - i) > round(0.15 * Fs)
        trough_idx = i;
        break;
    end
end

% 4. Find the LOCAL PEAK immediately before the trough
pre_peak_idx = trough_idx;
for i = trough_idx : -1 : 2
    % Stop moving backwards the moment the signal stops increasing
    if sum_trace(i-1) <= sum_trace(i)
        pre_peak_idx = i;
        break;
    end
    % Safeguard: don't walk back more than 150ms from the trough
    if (trough_idx - i) > round(0.15 * Fs)
        pre_peak_idx = i;
        break;
    end
end

% 5. SHIFT BACK BY 3 FRAMES
shift_frames = 3;
smart_trigger_idx = max(1, pre_peak_idx - shift_frames);

t_onset = time_sum(smart_trigger_idx);
onset_amp = sum_trace(smart_trigger_idx);

fprintf('  -> Main Peak at: %.3fs | Max Slope at: %.3fs | Shifted Onset (-3 frames) at: %.3fs (Frame %d)\n', ...
        t_peak, t_slope, t_onset, smart_trigger_idx);

%% 3.7 VISUALIZE SMART TRIGGER (Standalone Figure)
f_trigger = figure('Name', 'Global Smart Trigger Detection', 'Color', 'w', 'Position', [150, 150, 1000, 500]);
yyaxis left;
plot(time_sum, sum_trace, 'k-', 'LineWidth', 1.5, 'DisplayName', 'Global Signal (Sum)'); hold on;
plot(t_peak, peak_amp, 'r*', 'MarkerSize', 10, 'LineWidth', 1.5, 'DisplayName', 'Main Peak');
plot(t_slope, amp_at_slope, 'bo', 'MarkerSize', 8, 'LineWidth', 1.5, 'DisplayName', 'Max Slope');

% Anchor the green square exactly on the shifted frame
xline(t_onset, 'g-', 'LineWidth', 1.5, 'DisplayName', sprintf('Calculated Onset (-%d frames)', shift_frames));
plot(t_onset, onset_amp, 'gs', 'MarkerSize', 10, 'LineWidth', 2, 'MarkerFaceColor', 'w', 'DisplayName', 'Onset Trigger');
ylabel('Sum Amplitude (\DeltaF/F_0)', 'FontSize', 11, 'FontWeight', 'bold');

yyaxis right;
plot(time_sum, global_deriv, '-', 'Color', [0 0.45 0.74 0.3], 'LineWidth', 1, 'DisplayName', 'Derivative');
ylabel('Rate of Change', 'FontSize', 11, 'FontWeight', 'bold');

title(sprintf('Smart Trigger Detection (Pre-Rise Peak shifted by -%d frames)', shift_frames), 'FontSize', 12, 'FontWeight', 'bold');
xlabel('Time (s)', 'FontSize', 11, 'FontWeight', 'bold');
legend('Location', 'best'); grid on; axis tight;
ax_trig = gca; ax_trig.YAxis(1).Color = 'k'; ax_trig.YAxis(2).Color = [0 0.45 0.74];

%% 3.8 Setup Plot Frames based on SMART TRIGGER
bg_rgb   = imresize(bg_rgb_base, [orig_h, orig_w]);
bg_uint8 = im2uint8(bg_rgb);
frames_pre  = round((window_pre_ms  / 1000) * Fs);
frames_post = round((window_post_ms / 1000) * Fs);
plot_frames = max(1, smart_trigger_idx-frames_pre) : frame_step : min(num_frames, smart_trigger_idx+frames_post);
num_subplots = length(plot_frames);

%% Initialize Global Combined Canvas (For Figure 5)
cols = ceil(sqrt(num_subplots * 1.2));
rows = ceil(num_subplots / cols);
canvas_combined = zeros(rows*orig_h, cols*orig_w, 3, 'uint8');
for i = 1:num_subplots
    r_idx     = ceil(i / cols);
    c_idx     = mod(i-1, cols) + 1;
    row_range = (r_idx-1)*orig_h+1 : r_idx*orig_h;
    col_range = (c_idx-1)*orig_w+1 : c_idx*orig_w;
    canvas_combined(row_range, col_range, :) = bg_uint8;
end

%% 4. Main Batch Loop
for k = 1:num_files
    fName = files{k};
    D = cached_D_all{k};
    
    if ~isfield(D, 'reconstructed_movie'), continue; end
    mov = D.reconstructed_movie;
    
    % --- Apply Component-Specific Settings ---
    curr_alpha = alpha_thresholds(min(k, end));
    curr_trans = heatmap_transparencies(min(k, end));
    cmap_func  = component_cmaps{min(k, end)};
    cmap       = cmap_func(256);
    curr_contour_levels = linspace(curr_alpha, 0.95, 5);
    
    t_total = tic;
    fprintf('Processing %s: %d frames aligned to SMART trigger...\n', fName, num_subplots);
    
    %% 4a. Pre-compute stack
    t_step = tic;
    window_data  = mov(:, :, plot_frames);
    smooth_stack = imgaussfilt3(window_data, [spatial_smoothing, spatial_smoothing, 0.001]);
    
    mn = min(smooth_stack(:));  mx = max(smooth_stack(:));
    norm_stack   = (smooth_stack - mn) / (mx - mn);
    fprintf('  [1-3] Smooth + normalise:  %.2f s\n', toc(t_step));
    
    if closing_radius > 0
        t_step = tic;
        se_close = strel('disk', closing_radius);
        for i = 1:num_subplots
            norm_stack(:,:,i) = imclose(norm_stack(:,:,i), se_close);
        end
        fprintf('  [4]   Morph closing:       %.2f s\n', toc(t_step));
    end
    
    %% 4b. Compositing
    t_step = tic;
    canvas_overlay = zeros(rows*orig_h, cols*orig_w, 3, 'uint8');
    canvas_contour = zeros(rows*orig_h, cols*orig_w, 3, 'uint8');
    
    for i = 1:num_subplots
        img = norm_stack(:,:,i);
        
        r_idx     = ceil(i / cols);
        c_idx     = mod(i-1, cols) + 1;
        row_range = (r_idx-1)*orig_h+1 : r_idx*orig_h;
        col_range = (c_idx-1)*orig_w+1 : c_idx*orig_w;
        
        idx_mat = round(((img - curr_alpha) / (1 - curr_alpha)) * 255) + 1;
        idx_mat = max(1, min(256, idx_mat));
        
        color_r = reshape(cmap(idx_mat, 1), orig_h, orig_w);
        color_g = reshape(cmap(idx_mat, 2), orig_h, orig_w);
        color_b = reshape(cmap(idx_mat, 3), orig_h, orig_w);
        
        alpha_mask = imgaussfilt(double(img >= curr_alpha) * 1.0, 1.5);
        a3 = repmat(alpha_mask, [1 1 3]);
        
        % --- Frame 1: Individual Alpha Overlay ---
        color_rgb     = im2uint8(cat(3, color_r, color_g, color_b));
        frame_overlay = uint8(double(bg_uint8).*(1-a3) + double(color_rgb).*a3);
        
        % --- Accumulate into Global Combined Canvas (Figure 5) ---
        alpha_eff = a3 * curr_trans;
        curr_bg = double(canvas_combined(row_range, col_range, :));
        blended = uint8(curr_bg .* (1 - alpha_eff) + double(color_rgb) .* alpha_eff);
        canvas_combined(row_range, col_range, :) = blended;
        
        % --- Frame 2: Individual Contour Lines ---
        frame_contour = bg_uint8;
        se_halo  = strel('disk', max(2, floor(line_thickness/2) + 2));
        se_color = strel('disk', max(1, floor(line_thickness/2)));
        
        for lv = 1:length(curr_contour_levels)
            lvl = curr_contour_levels(lv);
            mask  = imgaussfilt(img, 0.8) >= lvl;
            perim = bwperim(mask);
            
            perim_halo = imdilate(perim, se_halo);
            r = double(frame_contour(:,:,1))/255; g = double(frame_contour(:,:,2))/255; b = double(frame_contour(:,:,3))/255;
            r(perim_halo) = 0; g(perim_halo) = 0; b(perim_halo) = 0;
            frame_contour = uint8(cat(3, r, g, b) * 255);
            
            perim_color = imdilate(perim, se_color);
            norm_lv  = (lv - 1) / max(length(curr_contour_levels) - 1, 1);
            c_idx_lv = round(norm_lv * 255) + 1; c_idx_lv = max(1, min(256, c_idx_lv));
            line_col = cmap(c_idx_lv, :);   
            
            r(perim_color) = line_col(1); g(perim_color) = line_col(2); b(perim_color) = line_col(3);
            frame_contour = uint8(cat(3, r, g, b) * 255);
        end
        
        % Timestamps and Trigger Annotations for individual frames
        is_trigger_frame = (plot_frames(i) == smart_trigger_idx);
        time_ms = ((plot_frames(i) - smart_trigger_idx) / Fs) * 1000;
        tstr    = sprintf('%+.0f ms', time_ms);
        
        frame_overlay = burn_text(frame_overlay, tstr, orig_h, orig_w, is_trigger_frame);
        frame_contour = burn_text(frame_contour, tstr, orig_h, orig_w, is_trigger_frame);
        
        canvas_overlay(row_range, col_range, :) = frame_overlay;
        canvas_contour(row_range, col_range, :) = frame_contour;
    end
    fprintf('  [5]   Compositing:         %.2f s\n', toc(t_step));
    
    %% 4c. Display Individual Figures
    t_step = tic;
    f1 = figure('Name',[fName ' - Alpha Overlay'],  'Color','w','Position',[50+(k*20)  50+(k*20)  1600 900]);
    ax1 = axes(f1,'Position',[0.02 0.05 0.88 0.92]);
    imshow(canvas_overlay,'Parent',ax1);
    add_colorbar(f1, cmap, curr_alpha, 1, sprintf('Comp %d \\DeltaF/F_0', k));
    
    f3 = figure('Name',[fName ' - Contour Lines'],  'Color','w','Position',[90+(k*20)  90+(k*20)  1600 900]);
    ax3 = axes(f3,'Position',[0.02 0.05 0.88 0.92]);
    imshow(canvas_contour,'Parent',ax3);
    add_colorbar(f3, cmap, curr_alpha, 1, sprintf('Comp %d \\DeltaF/F_0', k));
    
    fprintf('  [6]   Figure display:      %.2f s\n', toc(t_step));
    fprintf('  [TOTAL]:                   %.2f s\n\n', toc(t_total));
end

%% 5. Display Final Combined Synchronization Figure (Visual Overlap)
fprintf('Rendering Final Combined Figure (Aligned to Smart Trigger)....\n');
for i = 1:num_subplots
    r_idx = ceil(i / cols); c_idx = mod(i-1, cols) + 1;
    row_range = (r_idx-1)*orig_h+1 : r_idx*orig_h; col_range = (c_idx-1)*orig_w+1 : c_idx*orig_w;
    
    is_trigger_frame = (plot_frames(i) == smart_trigger_idx);
    time_ms = ((plot_frames(i) - smart_trigger_idx) / Fs) * 1000;
    tstr = sprintf('%+.0f ms', time_ms);
    
    frame_comb = canvas_combined(row_range, col_range, :);
    canvas_combined(row_range, col_range, :) = burn_text(frame_comb, tstr, orig_h, orig_w, is_trigger_frame);
end

f_combined = figure('Name','All Components Combined - Alpha Overlays & Timeline', 'Color','w','Position',[130 130 1600 1000]);
% --- Top Subplot: Combined Image Montage ---
ax_img = axes(f_combined, 'Position', [0.02 0.30 0.88 0.65]);
imshow(canvas_combined, 'Parent', ax_img);
% Add distinct colorbars for each component to the right side
for k = 1:num_files
    cmap_func = component_cmaps{min(k, end)};
    add_colorbar_multi(f_combined, cmap_func(256), alpha_thresholds(min(k, end)), 1, sprintf('Comp %d', k), k, num_files);
end

% --- Bottom Subplot: Global Signals mapped to Time (ms) ---
ax_time = axes(f_combined, 'Position', [0.05 0.08 0.82 0.18]);
time_axis_ms  = ((1:num_frames) - smart_trigger_idx) / Fs * 1000;
plot_times_ms = ((plot_frames - smart_trigger_idx) / Fs) * 1000;
colors = lines(num_files);

hold(ax_time, 'on');
for k = 1:num_files
    plot(ax_time, time_axis_ms, all_traces(:, k), '-', 'Color', colors(k,:), 'LineWidth', 1.5, 'DisplayName', sprintf('Comp %d', k));
    plot(ax_time, plot_times_ms, all_traces(plot_frames, k), 'o', 'MarkerFaceColor', colors(k,:), 'MarkerEdgeColor', 'none', 'MarkerSize', 5, 'HandleVisibility','off');
end

% Mark the new smart trigger & peak for context
xline(ax_time, 0, 'g-', sprintf('Calculated Onset (-%d frames)', shift_frames), 'LabelVerticalAlignment', 'bottom', 'LineWidth', 1.5, 'FontSize', 10, 'HandleVisibility','off');
plot(ax_time, (peak_idx - smart_trigger_idx)/Fs * 1000, peak_amp, 'r*', 'MarkerSize', 8, 'HandleVisibility','off'); 

xlabel(ax_time, 'Time relative to Smart Trigger (ms)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel(ax_time, 'Global Signal', 'FontSize', 12, 'FontWeight', 'bold');
xlim(ax_time, [time_axis_ms(1), time_axis_ms(end)]); 
grid(ax_time, 'on');
legend(ax_time, 'Location', 'best');
set(ax_time, 'FontSize', 10, 'TickDir', 'out');

%% 6. Merge First Two Components Mathematically and Plot Alpha Overlay
if num_files >= 2
    fprintf('Mathematically Merging Component 1 and Component 2...\n');
    t_merge_total = tic;
    
    % We use the turbo colormap here to differentiate it from the individual ROI maps
    cmap_merged = turbo(256);
    % Use the threshold of the first component as the baseline for the merged data
    merged_alpha = alpha_thresholds(1); 
    
    % 1. Merge the reconstructed movies
    merged_movie = cached_D_all{1}.reconstructed_movie + cached_D_all{2}.reconstructed_movie;
    
    % 2. Extract the relevant frames synchronized to the common trigger
    merged_window_data = merged_movie(:, :, plot_frames);
    
    % 3. Apply the same spatial smoothing
    merged_smooth = imgaussfilt3(merged_window_data, [spatial_smoothing, spatial_smoothing, 0.001]);
    
    % 4. Normalize the merged stack
    mn = min(merged_smooth(:)); mx = max(merged_smooth(:));
    merged_norm = (merged_smooth - mn) / (mx - mn);
    
    % 5. Apply the same morphological closing
    if closing_radius > 0
        se_close = strel('disk', closing_radius);
        for i = 1:num_subplots
            merged_norm(:,:,i) = imclose(merged_norm(:,:,i), se_close);
        end
    end
    
    % 6. Compositing the Alpha Overlay
    canvas_merged_overlay = zeros(rows*orig_h, cols*orig_w, 3, 'uint8');
    
    for i = 1:num_subplots
        img = merged_norm(:,:,i);
        
        r_idx     = ceil(i / cols);
        c_idx     = mod(i-1, cols) + 1;
        row_range = (r_idx-1)*orig_h+1 : r_idx*orig_h;
        col_range = (c_idx-1)*orig_w+1 : c_idx*orig_w;
        
        % Map to colormap
        idx_mat = round(((img - merged_alpha) / (1 - merged_alpha)) * 255) + 1;
        idx_mat = max(1, min(256, idx_mat));
        
        color_r = reshape(cmap_merged(idx_mat, 1), orig_h, orig_w);
        color_g = reshape(cmap_merged(idx_mat, 2), orig_h, orig_w);
        color_b = reshape(cmap_merged(idx_mat, 3), orig_h, orig_w);
        
        % Calculate alpha mask exactly as before
        alpha_mask = imgaussfilt(double(img >= merged_alpha) * 1.0, 1.5);
        a3 = repmat(alpha_mask, [1 1 3]);
        
        color_rgb = im2uint8(cat(3, color_r, color_g, color_b));
        
        % Composite over the base background image
        frame_overlay = uint8(double(bg_uint8).*(1-a3) + double(color_rgb).*a3);
        
        % Burn timestamps and annotations
        is_trigger_frame = (plot_frames(i) == smart_trigger_idx);
        time_ms = ((plot_frames(i) - smart_trigger_idx) / Fs) * 1000;
        tstr    = sprintf('%+.0f ms', time_ms);
        
        frame_overlay = burn_text(frame_overlay, tstr, orig_h, orig_w, is_trigger_frame);
        
        canvas_merged_overlay(row_range, col_range, :) = frame_overlay;
    end
    
    % 7. Display the Merged Figure
    f_merged = figure('Name','Merged Components 1 & 2 - Mathematical Alpha Overlay',  'Color','w','Position',[170 170 1600 900]);
    ax_merged = axes(f_merged,'Position',[0.02 0.05 0.88 0.92]);
    imshow(canvas_merged_overlay, 'Parent', ax_merged);
    add_colorbar(f_merged, cmap_merged, merged_alpha, 1, 'Merged \DeltaF/F_0 (Norm)');
    
    fprintf('  [Merged] Total processing time: %.2f s\n\n', toc(t_merge_total));
else
    fprintf('Less than 2 components loaded. Skipping the mathematical merge step.\n');
end

%% ── Local helpers ────────────────────────────────────────────────────────────
function img = burn_text(img, tstr, orig_h, orig_w, is_trigger)
    % Default to false if not provided
    if nargin < 5
        is_trigger = false; 
    end
    
    if exist('insertText','file')
        % Calculate a dynamic font size based on image height (min size 18)
        fnt_size = max(18, round(orig_h * 0.12)); 
        
        % Burn the timestamp at the bottom left with higher opacity box
        y_pos = orig_h - fnt_size - 10;
        img = insertText(img, [5, y_pos], tstr, ...
            'FontSize', fnt_size, 'TextColor', 'white', ...
            'BoxColor', 'black', 'BoxOpacity', 0.8);
            
        % If this is the exact trigger frame, burn a green label at the top left
        if is_trigger
            img = insertText(img, [5, 5], 'TRIGGER', ...
                'FontSize', fnt_size, 'TextColor', 'white', ...
                'BoxColor', 'green', 'BoxOpacity', 0.8);
        end
    end
end

function add_colorbar(fig, cmap, lo, hi, label_str)
    n = 256;
    tick_vals = linspace(lo, hi, 5);
    tick_pos  = round(linspace(1, n, 5));
    ax_cb = axes(fig, 'Position', [0.92 0.30 0.02 0.65]);
    
    cb_img = flipud(permute(reshape(cmap, [n, 1, 3]), [1 2 3]));
    image(ax_cb, cb_img);
    set(ax_cb, 'XTick', [], 'YTick', tick_pos, ...
               'YTickLabel', arrayfun(@(v) sprintf('%.2f',v), fliplr(tick_vals), 'UniformOutput', false), ...
               'TickDir', 'out', 'FontSize', 9);
    ylabel(ax_cb, label_str, 'FontSize', 12, 'FontWeight', 'bold');
end

function add_colorbar_multi(fig, cmap, lo, hi, label_str, k, total_k)
    % Stack multiple colorbars vertically on the right
    n = 256;
    tick_vals = linspace(lo, hi, 3);
    tick_pos  = round(linspace(1, n, 3));
    
    % Calculate position so they stack nicely
    height_per_cb = 0.60 / total_k;
    bottom_pos = 0.30 + (total_k - k) * (height_per_cb + 0.05);
    
    ax_cb = axes(fig, 'Position', [0.92 bottom_pos 0.015 height_per_cb]);
    
    cb_img = flipud(permute(reshape(cmap, [n, 1, 3]), [1 2 3]));
    image(ax_cb, cb_img);
    set(ax_cb, 'XTick', [], 'YTick', tick_pos, ...
               'YTickLabel', arrayfun(@(v) sprintf('%.2f',v), fliplr(tick_vals), 'UniformOutput', false), ...
               'TickDir', 'out', 'FontSize', 8);
    title(ax_cb, label_str, 'FontSize', 10, 'FontWeight', 'bold');
end