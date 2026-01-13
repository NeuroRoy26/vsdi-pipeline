%% batch_PLOT.m
% run this after post_reconstruction_v4.m script
% Loads multiple traces, NORMALIZES them, and plots a Waterfall.
% UPDATES:
% 1. Added 'use_zscore' setting to normalize data (Recommended).
% 2. Fixed the "0.00" display issue by using Scientific Notation.

clear; clc; close all;

%% 1. SETTINGS
% --- Normalization ---
use_zscore       = true;  % Set TRUE to normalize each trial (Mean=0, Std=1)
                          % This makes every row visible, even weak trials.

% --- Filtering ---
filter_on        = true;
high_pass_cutoff = 0.1;  
low_pass_cutoff  = 120; 
filter_order     = 4;

% --- Plotting ---
xline_stimulus   = 0;     % Time point to mark as stimulus (ms)
c_range_percent  = 98;    % Percentile for color contrast

%% 2. SELECT MULTIPLE FILES
if exist('data', 'dir')
    start_path = 'data/';
else
    start_path = pwd;
end

fprintf('Please select MULTIPLE global_trace_*.mat files (Hold Ctrl/Shift)...\n');
[file_names, file_path] = uigetfile(fullfile(start_path, '*.mat'), ...
                                    'Select Individual Trial Files', ...
                                    'MultiSelect', 'on');

if isequal(file_names, 0)
    error('User canceled file selection.');
end
if ischar(file_names), file_names = {file_names}; end % Handle single file

fprintf('Selected %d files.\n', length(file_names));

%% 3. LOAD, PROCESS, AND NORMALIZE
trace_matrix = []; 
time_vec = [];
Fs_main = [];
trial_labels = {}; 

fprintf('\n--- FILE STATISTICS (Scientific Notation) ---\n');
fprintf('%-30s | %-12s | %-12s\n', 'File Name', 'Min', 'Max');
fprintf('%s\n', repmat('-', 1, 60));

for i = 1:length(file_names)
    full_file_path = fullfile(file_path, file_names{i});
    loaded_struct = load(full_file_path);
    
    if ~isfield(loaded_struct, 'trace_data')
        warning('Skipping %s: No trace_data found.', file_names{i});
        continue;
    end
    
    data = loaded_struct.trace_data;
    raw_signal = data.global_trace;
    current_Fs = data.sampling_rate;
    current_time = data.time_axis_ms;
    
    % Check Fs
    if isempty(Fs_main), Fs_main = current_Fs; 
    elseif current_Fs ~= Fs_main
        warning('File %s Fs mismatch. Skipping.', file_names{i}); continue;
    end
    
    % 1. FILTER
    if filter_on
        nyquist_freq = current_Fs / 2;
        Wn = [high_pass_cutoff, low_pass_cutoff] / nyquist_freq;
        [b_band, a_band] = butter(filter_order, Wn, 'bandpass');
        proc_signal = filtfilt(b_band, a_band, raw_signal);
    else
        proc_signal = raw_signal;
    end

    % 2. PRINT RAW STATS (Before Normalization)
    % Using %10.4e shows values like 5.4321e-04 instead of 0.00
    fprintf('%-30s | %10.4e | %10.4e\n', file_names{i}(1:min(30, end)), min(proc_signal), max(proc_signal));

    % 3. NORMALIZE (Z-SCORE)
    if use_zscore
        % Subtract Mean and Divide by Std Dev
        mu = mean(proc_signal);
        sigma = std(proc_signal);
        if sigma == 0, sigma = 1; end % Avoid divide by zero
        proc_signal = (proc_signal - mu) / sigma;
    end
    
    % Clean Name for Plot
    clean_name = strrep(file_names{i}, 'global_trace_', '');
    clean_name = strrep(clean_name, '.mat', '');
    trial_labels{end+1} = clean_name; %#ok<SAGROW>
    
    % Store
    if isempty(trace_matrix)
        trace_matrix = proc_signal'; 
        time_vec = current_time;
    else
        target_len = size(trace_matrix, 2);
        curr_len = length(proc_signal);
        if curr_len > target_len, proc_signal = proc_signal(1:target_len);
        elseif curr_len < target_len, proc_signal(curr_len+1:target_len) = 0; end
        trace_matrix = [trace_matrix; proc_signal']; 
    end
end

%% 4. PLOTTING
if isempty(trace_matrix), error('No valid data loaded.'); end

trace_matrix = trace_matrix * -1;

figure('Name', 'Normalized Waterfall', 'Position', [100 50 1200 900]);
t = tiledlayout(4, 1, 'TileSpacing', 'compact', 'Padding', 'compact'); 

% A. Average Trace
nexttile(1); 
avg_trace = mean(trace_matrix, 1);
plot(time_vec, avg_trace, 'k', 'LineWidth', 1.5);
xline(xline_stimulus, '--r');
if use_zscore
    title('Average Response (Z-Scored Units)');
    ylabel('Std Dev (Z)');
else
    title('Average Response (Raw Units)');
    ylabel('Amplitude');
end
grid on; xlim([min(time_vec), max(time_vec)]);

% B. Waterfall
nexttile(2, [3 1]); 
imagesc(time_vec, 1:size(trace_matrix, 1), trace_matrix);

colormap('jet'); 
c = colorbar;
if use_zscore
    c.Label.String = 'Z-Score (Std Dev from Baseline)';
    caxis([-3 3]); % Standard setting for Z-scores (show +/- 3 sigmas)
else
    c.Label.String = 'Raw Amplitude';
    clim_vals = prctile(trace_matrix(:), [100-c_range_percent, c_range_percent]);
    caxis(clim_vals); 
end

title(sprintf('Waterfall Plot (n=%d)', size(trace_matrix, 1)));
xlabel('Time (ms)');
set(gca, 'YTick', 1:size(trace_matrix, 1), 'YTickLabel', trial_labels, ...
    'TickLabelInterpreter', 'none', 'FontSize', 9, 'YDir', 'normal');
xline(xline_stimulus, '--w', 'LineWidth', 1.5); 

fprintf('\nPlot complete. Normalization: %d\n', use_zscore);