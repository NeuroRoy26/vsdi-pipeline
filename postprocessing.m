%% postprocessing_v1.1.m
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
    Fs = data.sampling_rate;
    time_ms = data.time_axis_ms;
else
    error('Structure "trace_data" not found in file.');
end

fprintf('Signal loaded: %d samples @ %.1f Hz\n', length(raw_signal), Fs);

%% Sign inversion
% raw_signal = -1 * raw_signal;
% Fs = 500.67;
Fs = 1001.67;
xlineat = 1500;

%% 2. FFT
L = length(raw_signal);
Y_raw = fft(raw_signal);
P2_raw = abs(Y_raw / L);
P1_raw = P2_raw(1:floor(L/2)+1);
P1_raw(2:end-1) = 2*P1_raw(2:end-1);
f = Fs * (0:(L/2)) / L;

%% 3. 50Hz FILTER
% notch_freq = 50; % Hz
% bw = 2;
% wo = notch_freq / (Fs/2);  
% bw_norm = bw / (Fs/2);
% fprintf('Applying Notch Filter at %d Hz (Bandwidth: %d Hz)...\n', notch_freq, bw);
% [b, a] = iirnotch(wo, bw_norm);
% notched_signal = filtfilt(b, a, raw_signal);

%% HIGH-PASS & LOW-PASS
% filtered_signal = notched_signal;
filtered_signal = raw_signal;
filter_order     = 4;    
high_pass_cutoff = 0.1;  % 0.1 Hz or 4Hz, run and decide which is better
low_pass_cutoff  = 35; 
% fprintf('Applying High-Pass Filter (> %.1f Hz)...\n', high_pass_cutoff);
% fnorm = high_pass_cutoff / (Fs/2); % Normalize to Nyquist
% [b_high, a_high] = butter(filter_order, fnorm, 'high');
% filtered_signal = filtfilt(b_high, a_high, filtered_signal);
% 
% fprintf('Applying Low-Pass Filter (< %.1f Hz)...\n', low_pass_cutoff);
% fnorm = low_pass_cutoff / (Fs/2); % Normalize to Nyquist
% [b_low, a_low] = butter(filter_order, fnorm, 'low');
% filtered_signal = filtfilt(b_low, a_low, filtered_signal);
% 
% clean_signal_A = filtered_signal;

%% Bandpass
nyquist_freq = Fs / 2;
Wn = [high_pass_cutoff, low_pass_cutoff] / nyquist_freq;
fprintf('Applying Bandpass Filter (%.1f Hz to %.1f Hz)...\n', high_pass_cutoff, low_pass_cutoff);
[b_band, a_band] = butter(filter_order, Wn, 'bandpass');
clean_signal = filtfilt(b_band, a_band, raw_signal);

%% 4. FFT after filtering
Y_clean = fft(clean_signal);
P2_clean = abs(Y_clean / L);
P1_clean = P2_clean(1:floor(L/2)+1);
P1_clean(2:end-1) = 2*P1_clean(2:end-1);

%% 5. 
figure('Position', [100 100 1200 800]);
subplot(2,1,1);
plot(time_ms, raw_signal, 'b', 'LineWidth', 1); hold on;
title('Raw');
xlabel('Time (ms)');
ylabel('Amplitude');
% legend({'Raw'}, 'Location', 'best');
% grid on; axis tight;
% mid_idx = round(L/2);
% range_idx = max(1, mid_idx-100) : min(L, mid_idx+100);
% xlim([time_ms(range_idx(1)), time_ms(range_idx(end))]); 
xline(xlineat, '--r');

subplot(2,1,2);
plot(time_ms, clean_signal, 'b', 'LineWidth', 1);
title('Filtered');
xlabel('Time (ms)');
ylabel('Amplitude');
% grid on; axis tight;
% mid_idx = round(L/2);
% range_idx = max(1, mid_idx-100) : min(L, mid_idx+100);
% xlim([time_ms(range_idx(1)), time_ms(range_idx(end))]); 
% legend({'Clean'}, 'Location', 'best');
% xline(mid_idx * (1000/Fs), '--r');
xline(xlineat, '--r');

% figure('Position', [100 100 1200 800]);
% plot(f, P1_clean, 'b', 'LineWidth', 1);
% xline(50, '--k');
% title('FFT');
% xlabel('Frequency (Hz)');
% ylabel('Magnitude |P1(f)|');
% legend({'Spectrum'});

% figure('Position', [100 100 1200 800]);
% plot(time_ms, clean_signal_A, 'k', 'LineWidth', 1);
% title('Filtered');
% xlabel('Time (ms)');
% ylabel('Amplitude');
% grid on; axis tight;
% mid_idx = round(L/2);
% range_idx = max(1, mid_idx-100) : min(L, mid_idx+100);
% xlim([time_ms(range_idx(1)), time_ms(range_idx(end))]); 
% xl= xline(xlineat, '--r', '1450 ms');
% xl.LabelVerticalAlignment = 'bottom';
% xline(1500, '--c');
% legend({'VSD', 'Assummed Stimulus', 'Stimulus'});

stimulus_ms = 700; 
time_shifted = time_ms - xlineat;
figure('Position', [100 100 1200 800]);
plot(time_shifted, clean_signal, 'k', 'LineWidth', 1);
title('Filtered');
xlabel('Time (ms)');
ylabel('Amplitude');
grid on; 
axis tight;
labelStr = sprintf('0 ms (%d ms)', xlineat);
xl = xline(0, '--r', labelStr);
xl.LabelVerticalAlignment = 'bottom';
% xline(1500 - xlineat, '--c');

fprintf('=== DONE ===\n');