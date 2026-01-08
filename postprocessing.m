%% postprocessing_v1.2.m
% FILTER_AND_ANALYZE_TRACE.m
% Loads the global trace file, computes FFT, applies 50Hz Notch, and plots.
clear; clc; close all;

%% 1. LOAD DATA
if exist('data', 'dir')
    start_path = 'data/';
else
    start_path = pwd;
end

% Search for global_trace_*.mat files
mat_files = dir(fullfile(start_path, 'global_trace_*.mat'));

if isempty(mat_files)
    % No files found - open file browser
    fprintf('No global_trace_*.mat files found in %s\n', start_path);
    fprintf('Please select the global_trace_*.mat file...\n');
    [file_name, file_path] = uigetfile(fullfile(start_path, '*.mat'), 'Select Trace Data');
    if isequal(file_name, 0)
        error('User canceled file selection.');
    end
    full_file_path = fullfile(file_path, file_name);
    
elseif length(mat_files) == 1
    % Exactly one file found - load it automatically
    file_name = mat_files(1).name;
    file_path = start_path;
    full_file_path = fullfile(file_path, file_name);
    fprintf('Found file: %s\n', file_name);
    
else
    % Multiple files found - let user choose
    fprintf('Found %d global_trace_*.mat files:\n', length(mat_files));
    for i = 1:length(mat_files)
        fprintf('  %d: %s\n', i, mat_files(i).name);
    end
    choice = input(sprintf('Select file (1-%d): ', length(mat_files)));
    
    if choice < 1 || choice > length(mat_files) || isempty(choice)
        error('Invalid selection.');
    end
    
    file_name = mat_files(choice).name;
    file_path = start_path;
    full_file_path = fullfile(file_path, file_name);
end

% Load the selected file
fprintf('Loading: %s\n', file_name);
loaded_struct = load(full_file_path);

if isfield(loaded_struct, 'trace_data')
    data = loaded_struct.trace_data;
    raw_signal = data.global_trace;
    
    % Initial Fs from file (will be overwritten below based on filename)
    Fs = data.sampling_rate; 
    time_ms = data.time_axis_ms;
else
    error('Structure "trace_data" not found in file.');
end

% DETERMINE Fs FROM FILENAME
if contains(file_name, '1000Hz', 'IgnoreCase', true)
    Fs = 1000;
    fprintf('Detected "1000Hz" in filename. Setting Fs = 1000 Hz.\n');
elseif contains(file_name, '500Hz', 'IgnoreCase', true)
    Fs = 500;
    fprintf('Detected "500Hz" in filename. Setting Fs = 500 Hz.\n');
else
    fprintf('Frequency not detected in filename. Using Fs from struct: %.1f Hz\n', Fs);
end

fprintf('Signal loaded: %d samples @ %.1f Hz\n', length(raw_signal), Fs);

%% Sign inversion / Setup
% raw_signal = -1 * raw_signal;
xlineat = 1500;

%% 3. FFT
L = length(raw_signal);
Y_raw = fft(raw_signal);
P2_raw = abs(Y_raw / L);
P1_raw = P2_raw(1:floor(L/2)+1);
P1_raw(2:end-1) = 2*P1_raw(2:end-1);
f = Fs * (0:(L/2)) / L;

%% 4. FILTERING
% 50Hz FILTER (Commented out in original)
% notch_freq = 50; % Hz
% bw = 2;
% wo = notch_freq / (Fs/2);  
% bw_norm = bw / (Fs/2);
% fprintf('Applying Notch Filter at %d Hz (Bandwidth: %d Hz)...\n', notch_freq, bw);
% [b, a] = iirnotch(wo, bw_norm);
% notched_signal = filtfilt(b, a, raw_signal);

% HIGH-PASS & LOW-PASS / BANDPASS
% filtered_signal = notched_signal;
filtered_signal = raw_signal;
filter_order     = 4;    
high_pass_cutoff = 0.1;  
low_pass_cutoff  = 35; 

% Bandpass Implementation
nyquist_freq = Fs / 2;
Wn = [high_pass_cutoff, low_pass_cutoff] / nyquist_freq;
fprintf('Applying Bandpass Filter (%.1f Hz to %.1f Hz)...\n', high_pass_cutoff, low_pass_cutoff);
[b_band, a_band] = butter(filter_order, Wn, 'bandpass');
clean_signal = filtfilt(b_band, a_band, raw_signal);

%% 5. FFT after filtering
Y_clean = fft(clean_signal);
P2_clean = abs(Y_clean / L);
P1_clean = P2_clean(1:floor(L/2)+1);
P1_clean(2:end-1) = 2*P1_clean(2:end-1);

%% 6. PLOTTING
figure('Position', [100 100 1200 800]);

% Top subplot: Raw
subplot(2,1,1);
plot(time_ms, raw_signal, 'b', 'LineWidth', 1); hold on;
title('Raw Signal');
xlabel('Time (ms)');
ylabel('Amplitude');
xline(xlineat, '--r');

% Bottom subplot: Filtered
subplot(2,1,2);
plot(time_ms, clean_signal, 'b', 'LineWidth', 1);
title(sprintf('Processed @ Fs=%.0fHz', Fs));
xlabel('Time (ms)');
ylabel('Amplitude');
xline(xlineat, '--r');

% Stimulus Plot (Zoomed)
stimulus_ms = 700; 
time_shifted = time_ms - xlineat;
figure('Position', [150 150 1200 800]);
plot(time_shifted, clean_signal, 'k', 'LineWidth', 1);
title(sprintf('%.0f Hz', Fs));
xlabel('Time (ms)');
ylabel('Amplitude');
xline(0, '--r');
xlim([-500 700]);
xticks(-500:50:700);
grid on; 
grid minor; 
ax = gca;
ax.XAxis.MinorTickValues = -500:10:1000;
ax.XMinorGrid = 'on';

%% 7. PEAK-TO-PEAK CALCULATION (WITH UNIT CONVERSION)
% --- SETTINGS -----------------------------------------------------------
% window_start = 10;   % ms
% window_end   = 200;  % ms
% scale_factor = 1e8;  % 1e8 for Microvolts (µV)
% unit_label   = 'µV'; % Label to display
% idx_window = find(time_shifted >= window_start & time_shifted <= window_end);
% 
% if isempty(idx_window)
%     warning('No data found in the specified Peak-to-Peak window.');
% else
%     segment_data = clean_signal(idx_window);
%     segment_time = time_shifted(idx_window);
% 
%     [max_val, max_idx] = max(segment_data);
%     [min_val, min_idx] = min(segment_data);
% 
%     Vpp = max_val - min_val;
% 
%     t_max = segment_time(max_idx);
%     t_min = segment_time(min_idx);
% 
%     fprintf('Peak-to-Peak (Window: %.1f to %.1f ms)\n', window_start, window_end);
%     fprintf('  Max: %.2f %s at %.1f ms\n', max_val * scale_factor, unit_label, t_max);
%     fprintf('  Min: %.2f %s at %.1f ms\n', min_val * scale_factor, unit_label, t_min);
%     fprintf('  Vpp: %.2f %s\n', Vpp * scale_factor, unit_label);
% 
%     hold on;
%     plot(t_max, max_val, 'bv', 'MarkerFaceColor', 'b', 'MarkerSize', 6);
%     plot(t_min, min_val, 'b^', 'MarkerFaceColor', 'b', 'MarkerSize', 6);
%     plot([t_max, t_min], [max_val, min_val], 'b--', 'LineWidth', 1);
% 
%     current_title = get(gca, 'title');
%     title(sprintf('%s | Vpp: %.2f %s', current_title.String, Vpp * scale_factor, unit_label));
%     text(t_max, max_val, sprintf(' %.2f %s', max_val * scale_factor, unit_label), ...
%         'VerticalAlignment', 'bottom', 'Color', 'b', 'FontWeight', 'bold');
%     text(t_min, min_val, sprintf(' %.2f %s', min_val * scale_factor, unit_label), ...
%         'VerticalAlignment', 'top', 'Color', 'b', 'FontWeight', 'bold');
% end
%% Figure loader comparison
% mainFig = figure('Name', 'Combined SSEP Analysis');
% t = tiledlayout(2, 1); % 2 row, 1 columns
% h1 = openfig('data/Vp2p_trial_avg_500Hz.fig', 'invisible');
% ax1 = gca(h1); 
% ax1.Parent = t;
% ax1.Layout.Tile = 1; 
% close(h1); 
% 
% h2 = openfig('data/Vp2p_E0B0_1000Hz.fig', 'invisible');
% ax2 = gca(h2); 
% ax2.Parent = t;
% ax2.Layout.Tile = 2; 
% close(h2);
% 
% title(t, 'Comparison of Trials (500Hz vs 1000Hz)');
%% Figure loader overlay
% mainFig = figure('Name', 'Overlay Comparison');
% mainAx = axes(mainFig); 
% hold(mainAx, 'on'); % Critical: allows multiple plots on one graph
% grid(mainAx, 'on');
% 
% % --- Process Figure 1 (500Hz) -> GREEN ---
% h1 = openfig('data/SSEP_trial_avg_500Hz.fig', 'invisible');
% ax1 = gca(h1);
% % Find the line objects (the actual data curves)
% lines1 = findobj(ax1, 'Type', 'line');
% % Set style: Green, slightly thicker for visibility
% set(lines1, 'Color', 'g', 'LineWidth', 1.5, 'DisplayName', '500 Hz');
% % Copy the line data to the new main axis
% copyobj(lines1, mainAx);
% % (Optional) Copy labels from this figure to the new one
% xlabel(mainAx, ax1.XLabel.String);
% ylabel(mainAx, ax1.YLabel.String);
% close(h1);
% 
% % --- Process Figure 2 (1000Hz) -> RED ---
% h2 = openfig('data/SSEP_E0B0_1000Hz.fig', 'invisible');
% ax2 = gca(h2);
% lines2 = findobj(ax2, 'Type', 'line');
% % Set style: Red
% set(lines2, 'Color', 'r', 'LineWidth', 1.5, 'DisplayName', '1000 Hz');
% copyobj(lines2, mainAx);
% close(h2);
% 
% title(mainAx, 'Comparison of SSEP Trials (Overlay)');
% legend(mainAx, 'show'); % Shows the 'DisplayName' set above
% hold(mainAx, 'off');

fprintf('=== DONE ===\n');