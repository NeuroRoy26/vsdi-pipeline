% calc_internal_trigger_enhanced.m
% run after reconstruct.m files, on reconstructed_ICs_*.mat files 
% use v2.m
% Enhanced version with GUI controls and keyboard navigation
% FEATURES: Slider, Arrow keys, Click-to-view, Better visualization

clear; clc; close all;

%% 1. LOAD DATA
fprintf('=== INTERNAL TRIGGER CALCULATION (Enhanced) ===\n');
if ~exist('data', 'dir'), error('Data directory not found!'); end

files = dir('data/reconstructed_ICs_*.mat');
if isempty(files), error('No reconstruction files found! Run ICA_reconstruct.m first.'); end

fprintf('Select the reconstruction file to analyze:\n');
for i = 1:length(files)
    fprintf('  %d. %s\n', i, files(i).name);
end
file_idx = input('\nSelect file number: ');
load(fullfile('data', files(file_idx).name));

if ~exist('Fs', 'var'), Fs = 500; warning('Fs not found, assuming 250Hz'); end

%% 2. PREPARE SIGNAL
raw_trace = squeeze(mean(mean(reconstructed_movie, 1), 2));

filter_order     = 4;    
high_pass_cutoff = 0.1;  
low_pass_cutoff  = 75; %35, 55, 75, 120
steepness_db_oct = filter_order * 6 * 2;
nyquist_freq = Fs / 2;
Wn = [high_pass_cutoff, low_pass_cutoff] / nyquist_freq;
fprintf('Applying Bandpass Filter (%.1f Hz to %.1f Hz)...\n', high_pass_cutoff, low_pass_cutoff);
[b_band, a_band] = butter(filter_order, Wn, 'bandpass');
clean_signal = filtfilt(b_band, a_band, raw_trace);
raw_trace = clean_signal;

% Polarity check
figure('Position', [400 400 800 300]);
plot(raw_trace, 'k'); 
title('Check Polarity:');
xlabel('Frame'); ylabel('Intensity');
pol_choice = input('Do the sharp spikes go UP? (y/n): ', 's');
if strcmpi(pol_choice, 'n')
    trace_signal = -1 * raw_trace;
else
    trace_signal = raw_trace;
end
close(gcf);

%% 3. DETECT TRIGGERS
d_signal = [0; diff(trace_signal)];
noise_mean = mean(d_signal);
noise_std = std(d_signal);
Z_score_threshold = 3.5;
threshold_val = noise_mean + (Z_score_threshold * noise_std);

candidates = find(d_signal > threshold_val);
min_inter_stim_interval_ms = 800;
min_dist_samples = round((min_inter_stim_interval_ms / 1000) * Fs);

triggers = [];
last_trigger = -min_dist_samples;
for i = 1:length(candidates)
    current_idx = candidates(i);
    if (current_idx - last_trigger) > min_dist_samples
        triggers = [triggers; current_idx];
        last_trigger = current_idx;
    end
end

num_triggers = length(triggers);
time_axis = (1:length(trace_signal)) / Fs;

fprintf('\n================================================\n');
fprintf('DETECTION RESULTS:\n');
fprintf('  Threshold (Z-score): %.1f\n', Z_score_threshold);
fprintf('  Refractory Period: %d ms\n', min_inter_stim_interval_ms);
fprintf('  DETECTED EVENTS: %d\n', num_triggers);
fprintf('================================================\n');

%% 4. CREATE INTERACTIVE GUI
f = figure('Name', 'Internal Trigger Analysis - Interactive Viewer', ...
           'Color', 'w', 'Position', [50 50 1200 900], ...
           'KeyPressFcn', @keyPress);

% Shared data structure
gui_data = struct();
gui_data.current_frame = 1;
gui_data.max_frames = size(reconstructed_movie, 3);
gui_data.movie = reconstructed_movie;
gui_data.trace = trace_signal;
gui_data.deriv = d_signal;
gui_data.triggers = triggers;
gui_data.time_axis = time_axis;
gui_data.Fs = Fs;
gui_data.threshold = threshold_val;
gui_data.click_line = [];

% --- TOP: 1D Trace with Triggers ---
gui_data.ax1 = subplot(3,1,1);
plot(time_axis, trace_signal, 'k', 'LineWidth', 1.2); hold on;
plot(time_axis(triggers), trace_signal(triggers), 'rp', ...
     'MarkerFaceColor', 'r', 'MarkerSize', 12, 'MarkerEdgeColor', 'k');
gui_data.click_line = xline(time_axis(1), 'b-', 'LineWidth', 2);
title('Signal Trace (Click to view frame)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Fluorescence (a.u.)'); 
xlabel('Time (s)');
grid on; axis tight;
set(gca, 'ButtonDownFcn', @clickTrace);

% --- MIDDLE: Derivative ---
gui_data.ax2 = subplot(3,1,2);
plot(time_axis, d_signal, 'Color', [0.2 0.4 0.8], 'LineWidth', 1); hold on;
yline(threshold_val, 'r--', 'LineWidth', 2, 'Label', 'Threshold: Z score=3.5');
gui_data.click_line2 = xline(time_axis(1), 'b-', 'LineWidth', 2);
title('Derivative (Rate of Change)', 'FontSize', 11);
ylabel('dF/dt'); 
xlabel('Time (s)');
grid on; axis tight;

% --- BOTTOM: Spatial Map + Slider ---
gui_data.ax3 = subplot(3,1,3);
gui_data.img_handle = imagesc(reconstructed_movie(:,:,1));
colormap(gui_data.ax3, jet); 
colorbar; 
axis image off;
title(sprintf('Frame 1 / %d  |  Time: 0.000 s', gui_data.max_frames), ...
      'FontSize', 11, 'FontWeight', 'bold');

% Create slider
gui_data.slider = uicontrol('Style', 'slider', ...
    'Min', 1, 'Max', gui_data.max_frames, 'Value', 1, ...
    'Units', 'normalized', 'Position', [0.1 0.02 0.8 0.03], ...
    'SliderStep', [1/(gui_data.max_frames-1), 10/(gui_data.max_frames-1)], ...
    'Callback', @sliderCallback);

% Instructions
uicontrol('Style', 'text', 'String', ...
    '← → Arrow Keys  |  Click on trace  |  Slider', ...
    'Units', 'normalized', 'Position', [0.1 0.06 0.8 0.03], ...
    'BackgroundColor', 'w', 'FontSize', 10, 'FontWeight', 'bold');

% Store data in figure
guidata(f, gui_data);

fprintf('\n INTERACTIVE MODE \n');
fprintf('  Close window to exit\n\n');

%% CALLBACK FUNCTIONS

    function keyPress(src, event)
        % Handle arrow key presses
        data = guidata(src);
        
        switch event.Key
            case 'rightarrow'
                data.current_frame = min(data.current_frame + 1, data.max_frames);
                updateFrame(src, data);
            case 'leftarrow'
                data.current_frame = max(data.current_frame - 1, 1);
                updateFrame(src, data);
        end
    end

    function sliderCallback(src, ~)
        % Handle slider movement
        fig = ancestor(src, 'figure');
        data = guidata(fig);
        data.current_frame = round(get(src, 'Value'));
        updateFrame(fig, data);
    end

    function clickTrace(src, event)
        % Handle clicks on the trace plot
        fig = ancestor(src, 'figure');
        data = guidata(fig);
        
        % Get click position
        click_pos = event.IntersectionPoint(1); % X-coordinate (time)
        
        % Convert time to frame
        frame_idx = round(click_pos * data.Fs);
        frame_idx = max(1, min(frame_idx, data.max_frames));
        
        data.current_frame = frame_idx;
        updateFrame(fig, data);
    end

    function updateFrame(fig, data)
        % Update all displays to show current frame
        
        % Update spatial map
        set(data.img_handle, 'CData', data.movie(:,:,data.current_frame));
        
        % Update title
        current_time = data.time_axis(data.current_frame);
        title(data.ax3, sprintf('Frame %d / %d  |  Time: %.3f s', ...
              data.current_frame, data.max_frames, current_time), ...
              'FontSize', 11, 'FontWeight', 'bold');
        
        % Update vertical line on traces
        set(data.click_line, 'Value', current_time);
        set(data.click_line2, 'Value', current_time);
        
        % Update slider
        set(data.slider, 'Value', data.current_frame);
        
        % Save updated data
        guidata(fig, data);
    end

    