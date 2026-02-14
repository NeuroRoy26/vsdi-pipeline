% analysis_noPCAICA.m
% Interactive viewer for H5 files WITHOUT PCA/ICA preprocessing
% Purpose is to check whether PCA-ICA is important or not
clear; clc; close all;

%% ======================== CONFIGURATION ========================
CONFIG.bandpass_freq = [0.1, 75];     % Hz - Bandpass filter range
CONFIG.filter_order = 4;              % Butterworth filter order
CONFIG.grid_rows = 5;                 % 5 Rows
CONFIG.grid_cols = 5;                 % 5 Columns
CONFIG.spatial_blur_sigma = 1.5;      % Spatial smoothing sigma
CONFIG.trace_smooth_window = 11;      % Trace smoothing window

%% ======================== FILE SELECTION ========================
fprintf('========================================\n');
fprintf(' Enhanced Direct Signal Viewer - FIXED\n');
fprintf('========================================\n\n');

% File selection
[fName, fPath] = uigetfile('*.h5', 'Select H5 File');
if isequal(fName, 0)
    fprintf('Selection canceled by user.\n');
    return;
end
input_file = fullfile(fPath, fName);
fprintf('Selected: %s\n', input_file);

% Sampling rate selection
fprintf('\nSelect Sampling Rate:\n 1) 500 Hz\n 2) 1000 Hz\n 3) Custom\n');
choice = input('Enter your choice (1, 2, or 3): ');
switch choice
    case 1
        original_sampling_rate = 500;
    case 2
        original_sampling_rate = 1000;
    case 3
        original_sampling_rate = input('Enter custom sampling rate (Hz): ');
    otherwise
        error('Invalid selection. Choose 1, 2, or 3.');
end
Fs = original_sampling_rate / 2;   % interleaved frames -> half rate

%% ======================== LOAD & PROCESS DATA ========================
fprintf('\nLoading data...\n');
dataset_name = '/functional_dff';
try
    mov = h5read(input_file, dataset_name);
catch
    error('Could not read dataset "%s". Check file structure.', dataset_name);
end

[height, width, num_frames] = size(mov);
mov(isnan(mov)) = 0; % Handle NaNs

% Spatial Smoothing
fprintf('Applying spatial smoothing...\n');
mov_smooth = zeros(size(mov));
for t = 1:num_frames
    mov_smooth(:,:,t) = imgaussfilt(mov(:,:,t), CONFIG.spatial_blur_sigma);
end

% Compute Maps
fprintf('Computing auxiliary maps...\n');
std_map = std(mov_smooth, 0, 3);
global_trace_raw = squeeze(mean(mean(mov_smooth, 1), 2));

% Global Trace Processing
[b, a] = butter(CONFIG.filter_order, CONFIG.bandpass_freq / (Fs/2), 'bandpass');
clean_trace = filtfilt(b, a, global_trace_raw);

% Polarity Check
half_idx = floor(num_frames / 2);
sk_2nd_half = skewness(clean_trace(half_idx:end));
if sk_2nd_half < 0
    curr_trace = -clean_trace;
    polarity_action = 'FLIPPED';
    mov_display = -mov_smooth; % Pre-flip for display
else
    curr_trace = clean_trace;
    polarity_action = 'KEPT';
    mov_display = mov_smooth;
end

% Normalize Global Trace
final_trace = zscore(curr_trace);
time_axis = (0:num_frames-1) / Fs;

% Correlation Map
fprintf('Computing correlation map...\n');
corr_map = zeros(height, width);
mov_reshaped = reshape(mov_smooth, height*width, num_frames);
% Quick correlation using vectorization
if strcmp(polarity_action, 'FLIPPED')
    target_trace = -global_trace_raw;
else
    target_trace = global_trace_raw;
end
for px = 1:height*width
    corr_map(px) = corr(mov_reshaped(px,:)', target_trace);
end
corr_map = reshape(corr_map, height, width);

%% ======================== GRID EXTRACTION ========================
fprintf('Processing Grid Regions...\n');
ROIs = struct();
block_h = floor(height / CONFIG.grid_rows);
block_w = floor(width / CONFIG.grid_cols);
idx_counter = 0;

mov_reshaped_display = reshape(mov_display, [], num_frames);

for r = 1:CONFIG.grid_rows
    for c = 1:CONFIG.grid_cols
        idx_counter = idx_counter + 1;
        
        r_start = (r-1)*block_h + 1;
        r_end = min(r*block_h, height);
        c_start = (c-1)*block_w + 1;
        c_end = min(c*block_w, width);
        
        mask = false(height, width);
        mask(r_start:r_end, c_start:c_end) = true;
        
        ROIs(idx_counter).row = r;
        ROIs(idx_counter).col = c;
        ROIs(idx_counter).pos = [c_start, r_start, (c_end-c_start), (r_end-r_start)];
        
        mask_idx = find(mask);
        roi_raw = mean(mov_reshaped_display(mask_idx, :), 1)';
        
        % Filter & Z-Score
        roi_filt = filtfilt(b, a, roi_raw);
        ROIs(idx_counter).trace = zscore(roi_filt);
        ROIs(idx_counter).mean_activity = mean(abs(ROIs(idx_counter).trace));
    end
end
fprintf('Done.\n');

%% ======================== GUI LAYOUT ========================
h = figure('Name', ['Fixed Viewer - ' fName], ...
           'Position', [50, 50, 1600, 900], ...
           'Color', 'w', 'MenuBar', 'none', ...
           'CloseRequestFcn', @closeGUI); % Custom close function

% --- SHARED DATA STRUCTURE ---
V = struct();
V.mov = mov_display;      % Already polarity corrected
V.std_map = std_map;
V.corr_map = corr_map;
V.num_frames = num_frames;
V.trace = final_trace;
V.time_axis = time_axis;
V.curr_frame = 1;
V.ROIs = ROIs;
V.timer = [];             % Placeholder for timer
V.play_speed = 1;
V.smooth_window = CONFIG.trace_smooth_window;

% --- LAYOUT DEFINITIONS (Normalized 0-1) ---
% Column X positions
col_1_x = 0.03; w_1 = 0.35; % Grid
col_2_x = 0.40; w_2 = 0.35; % Maps
col_3_x = 0.77; w_3 = 0.20; % Controls

% Row Y positions
row_top_y = 0.85; h_top = 0.13; % Main Trace
row_mid_y = 0.05; h_mid = 0.75; % Main Content Area

%% 1. GLOBAL TRACE (Top, spanning Col 1 & 2)
V.ax_main = axes('Parent', h, 'Position', [col_1_x, row_top_y, w_1 + w_2 + 0.02, h_top]);
plot(time_axis, final_trace, 'k-', 'LineWidth', 1); hold on;
V.xline_main = xline(time_axis(1), 'r-', 'LineWidth', 2);
title('Global Signal (Z-Score)', 'FontSize', 10);
axis tight; grid on;
set(V.ax_main, 'ButtonDownFcn', @(s,e) traceClick(s,e,h));

%% 2. GRID TRACES (Left Column)
% Sub-grid calculation
g_gap = 0.002;
sub_w = (w_1 - (CONFIG.grid_cols-1)*g_gap) / CONFIG.grid_cols;
sub_h = (h_mid - (CONFIG.grid_rows-1)*g_gap) / CONFIG.grid_rows;

V.grid_plots = gobjects(25,1);
V.grid_xlines = gobjects(25,1);

% Color range
acts = [ROIs.mean_activity];
c_min = min(acts); c_max = max(acts);

for i = 1:25
    r = ROIs(i).row;
    c = ROIs(i).col;
    
    px = col_1_x + (c-1)*(sub_w + g_gap);
    py = row_mid_y + (CONFIG.grid_rows - r)*(sub_h + g_gap);
    
    ax = axes('Parent', h, 'Position', [px, py, sub_w, sub_h]);
    
    % Color coding
    if c_max > c_min, norm_a = (ROIs(i).mean_activity - c_min)/(c_max - c_min); else, norm_a = 0.5; end
    col = [0, 0.5 + 0.5*norm_a, 1 - norm_a];
    
    % Initial Plot
    V.grid_plots(i) = plot(time_axis, ROIs(i).trace, 'Color', col); hold on;
    V.grid_xlines(i) = xline(time_axis(1), 'k-');
    
    set(ax, 'XTick', [], 'YTick', [], 'Box', 'on', 'XColor', 'none', 'YColor', 'none');
    ylim([-3 3]);
    set(ax, 'ButtonDownFcn', @(s,e) traceClick(s,e,h));
end
uicontrol(h, 'Style','text', 'String', 'Spatial Grid (Click to Jump)', ...
    'Units', 'normalized', 'Position', [col_1_x, row_mid_y+h_mid, w_1, 0.02], ...
    'BackgroundColor', 'w', 'FontWeight', 'bold');

%% 3. MAPS (Center Column)
% Main Movie View
V.ax_movie = axes('Parent', h, 'Position', [col_2_x, 0.45, w_2, 0.35]);
V.img_h = imagesc(V.mov(:,:,1));
colormap(V.ax_movie, jet);
colorbar; axis image off;
hold on;
% Grid Overlay
for i = 1:25
    rectangle('Position', ROIs(i).pos, 'EdgeColor', [1 1 1 0.5]);
end
V.title_h = title('Current Frame', 'FontSize', 10);

% Std Dev Map
axes('Parent', h, 'Position', [col_2_x, 0.05, w_2/2 - 0.01, 0.35]);
imagesc(V.std_map); axis image off; colormap(gca, hot); title('Std Dev');

% Correlation Map
axes('Parent', h, 'Position', [col_2_x + w_2/2 + 0.01, 0.05, w_2/2 - 0.01, 0.35]);
imagesc(V.corr_map, [-1 1]); axis image off; 
% Custom Red-Blue Colormap
m = 64; 
redblue = [linspace(0,1,m/2)' linspace(0,1,m/2)' ones(m/2,1); ones(m/2,1) linspace(1,0,m/2)' linspace(1,0,m/2)'];
colormap(gca, redblue); title('Correlation');

%% 4. CONTROLS (Right Column)

% --- Display Settings ---
p_disp = uipanel('Parent', h, 'Title', 'Display', 'Position', [col_3_x, 0.70, w_3, 0.15], 'BackgroundColor', 'w');
V.chk_smooth = uicontrol(p_disp, 'Style', 'checkbox', 'String', 'Smooth Traces', 'Value', 0, ...
    'Units', 'norm', 'Position', [0.1, 0.7, 0.8, 0.2], 'BackgroundColor', 'w', ...
    'Callback', @(s,e) updateSmoothing(h));
uicontrol(p_disp, 'Style', 'text', 'String', 'Contrast:', 'Units', 'norm', 'Position', [0.1, 0.4, 0.8, 0.2], 'BackgroundColor', 'w', 'HorizontalAlignment', 'left');
V.slider_contrast = uicontrol(p_disp, 'Style', 'slider', 'Min', 0.1, 'Max', 6, 'Value', 2, ...
    'Units', 'norm', 'Position', [0.1, 0.1, 0.8, 0.25], 'Callback', @(s,e) updateFrame(h));

% --- Stats ---
p_stat = uipanel('Parent', h, 'Title', 'Info', 'Position', [col_3_x, 0.45, w_3, 0.20], 'BackgroundColor', 'w');
V.txt_stats = uicontrol(p_stat, 'Style', 'text', 'String', 'Ready', 'Units', 'norm', 'Position', [0.1, 0.1, 0.8, 0.8], 'BackgroundColor', 'w', 'HorizontalAlignment', 'left', 'FontName', 'Courier');

% --- Playback ---
p_play = uipanel('Parent', h, 'Title', 'Playback', 'Position', [col_3_x, 0.15, w_3, 0.25], 'BackgroundColor', 'w');
V.btn_play = uicontrol(p_play, 'Style', 'pushbutton', 'String', '▶ Play', ...
    'Units', 'norm', 'Position', [0.1, 0.65, 0.35, 0.25], 'Callback', @(s,e) toggleTimer(h));
V.btn_stop = uicontrol(p_play, 'Style', 'pushbutton', 'String', '■ Stop', ...
    'Units', 'norm', 'Position', [0.55, 0.65, 0.35, 0.25], 'Callback', @(s,e) stopTimer(h));
V.slider_speed = uicontrol(p_play, 'Style', 'slider', 'Min', 1, 'Max', 10, 'Value', 1, ...
    'Units', 'norm', 'Position', [0.1, 0.35, 0.8, 0.15]); 
uicontrol(p_play, 'Style', 'text', 'String', 'Speed', 'Units', 'norm', 'Position', [0.1, 0.5, 0.8, 0.1], 'BackgroundColor', 'w');

% Master Slider (Bottom)
V.slider_time = uicontrol(h, 'Style', 'slider', 'Min', 1, 'Max', num_frames, 'Value', 1, ...
    'Units', 'norm', 'Position', [col_3_x, 0.05, w_3, 0.05], 'Callback', @(s,e) sliderJump(h));

% --- TIMER SETUP ---
% We create a timer object but don't start it yet. 
% This replaces the 'while' loop.
V.timer = timer('ExecutionMode', 'fixedRate', ...
                'Period', 0.05, ... % 20 fps cap
                'TimerFcn', @(~,~) timerTick(h));

guidata(h, V);
updateFrame(h); % Initial draw

fprintf('✓ Viewer launched successfully.\n');

%% ======================== CALLBACKS ========================

function closeGUI(h, ~)
    % Clean up timer before closing to prevent errors
    V = guidata(h);
    if isfield(V, 'timer') && isvalid(V.timer)
        stop(V.timer);
        delete(V.timer);
    end
    delete(h);
end

function toggleTimer(h)
    V = guidata(h);
    if strcmp(V.timer.Running, 'on')
        stop(V.timer);
        set(V.btn_play, 'String', '▶ Play');
    else
        start(V.timer);
        set(V.btn_play, 'String', '⏸ Pause');
    end
end

function stopTimer(h)
    V = guidata(h);
    stop(V.timer);
    set(V.btn_play, 'String', '▶ Play');
    V.curr_frame = 1;
    guidata(h, V);
    updateFrame(h);
end

function timerTick(h)
    V = guidata(h);
    
    % Calculate next frame based on speed slider
    step = round(get(V.slider_speed, 'Value'));
    next = V.curr_frame + step;
    
    if next > V.num_frames
        next = V.num_frames;
        stopTimer(h); % Auto-stop at end
    end
    
    V.curr_frame = next;
    guidata(h, V);
    updateFrame(h);
end

function sliderJump(h)
    V = guidata(h);
    val = round(get(V.slider_time, 'Value'));
    V.curr_frame = val;
    guidata(h, V);
    updateFrame(h);
end

function traceClick(~, e, h)
    V = guidata(h);
    t_click = e.IntersectionPoint(1);
    [~, idx] = min(abs(V.time_axis - t_click));
    V.curr_frame = idx;
    guidata(h, V);
    updateFrame(h);
end

function updateSmoothing(h)
    V = guidata(h);
    do_smooth = get(V.chk_smooth, 'Value');
    
    for i = 1:25
        if do_smooth
            % Apply moving average
            y_data = movmean(V.ROIs(i).trace, V.smooth_window);
        else
            y_data = V.ROIs(i).trace;
        end
        set(V.grid_plots(i), 'YData', y_data);
    end
end

function updateFrame(h)
    V = guidata(h);
    f = V.curr_frame;
    
    % 1. Update Map
    % Calculate contrast limits
    frame_data = V.mov(:,:,f);
    c_val = get(V.slider_contrast, 'Value');
    mu = mean(frame_data(:));
    sig = std(frame_data(:));
    clim = [mu - c_val*sig, mu + c_val*sig];
    
    set(V.img_h, 'CData', frame_data);
    set(V.ax_movie, 'CLim', clim);
    set(V.title_h, 'String', sprintf('Frame %d / %d (%.2fs)', f, V.num_frames, V.time_axis(f)));
    
    % 2. Update Lines
    set(V.xline_main, 'Value', V.time_axis(f));
    for i=1:25
        set(V.grid_xlines(i), 'Value', V.time_axis(f));
    end
    
    % 3. Update Controls/Stats
    set(V.slider_time, 'Value', f);
    set(V.txt_stats, 'String', sprintf('T: %.3fs\nMin: %.3f\nMax: %.3f', ...
        V.time_axis(f), min(frame_data(:)), max(frame_data(:))));
end