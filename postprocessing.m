%% postprocessing_v11.2.m
% FILTER_AND_ANALYZE_TRACE.m
% Loads the global trace file, computes FFT, applies 50Hz Notch, and plots.
clear; clc; close all;

%% 1. LOAD DATA
if exist('data', 'dir')
    start_path = 'data/recon_500';
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
raw_signal = 1 * raw_signal;
xlineat = 1470;

%% 3. FFT
L = length(raw_signal);
Y_raw = fft(raw_signal);
P2_raw = abs(Y_raw / L);
P1_raw = P2_raw(1:floor(L/2)+1);
P1_raw(2:end-1) = 2*P1_raw(2:end-1);
f = Fs * (0:(L/2)) / L;

%% 4. FILTERING
% 50Hz FILTER 
notch_freq = 50; % Hz
bw = 2;
wo = notch_freq / (Fs/2);  
bw_norm = bw / (Fs/2);
fprintf('Applying Notch Filter at %d Hz (Bandwidth: %d Hz)...\n', notch_freq, bw);
[b, a] = iirnotch(wo, bw_norm);
notched_signal = filtfilt(b, a, raw_signal);

% HIGH-PASS & LOW-PASS / BANDPASS
filtered_signal = notched_signal;
% filtered_signal = raw_signal;
filter_order     = 4;    
high_pass_cutoff = 0.1;  
low_pass_cutoff  = 35; %35, 55, 75, 120

steepness_db_oct = filter_order * 6 * 2;

% Bandpass Implementation
nyquist_freq = Fs / 2;
Wn = [high_pass_cutoff, low_pass_cutoff] / nyquist_freq;
fprintf('Applying Bandpass Filter (%.1f Hz to %.1f Hz)...\n', high_pass_cutoff, low_pass_cutoff);
[b_band, a_band] = butter(filter_order, Wn, 'bandpass');
clean_signal = filtfilt(b_band, a_band, filtered_signal);

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
info_str = sprintf('Bandpass = %.1f to %.1f Hz | Steepness = %d dB/octave | zero-phase filtering', ...
                   high_pass_cutoff, low_pass_cutoff, steepness_db_oct);
title(info_str, 'FontWeight', 'bold');
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
%% 8. DUAL CURVE FITTING (Constrained & Robust) - FIXED v3
% Fits pre/post stimulus with strict bounds to ensure decay.

fprintf('\n--- Starting Robust Curve Fitting ---\n');

% 1. Split Data
split_time = xlineat; 
idx_split = find(time_ms >= split_time, 1);

% ZONE 1 DATA (Pre-Stimulus)
x1 = time_ms(1:idx_split-5);     
y1 = raw_signal(1:idx_split-5);
x1 = x1(:); y1 = y1(:);          % Force column
x1_shift = x1 - x1(1);           % Shift to 0 for math stability

% ZONE 2 DATA (Post-Stimulus)
search_window = 50; 
idx_search_end = find(time_ms >= xlineat + search_window, 1);
[~, rel_peak] = max(raw_signal(idx_split:idx_search_end));
idx_peak = idx_split + rel_peak - 1;

x2 = time_ms(idx_peak:end);
y2 = raw_signal(idx_peak:end);
x2 = x2(:); y2 = y2(:);          % Force column
x2_shift = x2 - x2(1);           % Shift to 0 for math stability

% 2. Define Model: y = a*exp(-b*x) + c
ft = fittype('a*exp(-b*x) + c');

% --- SETUP ZONE 1 FIT (PRE-STIMULUS) ---
opts1 = fitoptions(ft);
opts1.Algorithm = 'Trust-Region';    % FIXED: Correct algorithm name
opts1.Robust    = 'LAR';             % Ignore noise outliers

% ESTIMATES (Smart Guessing)
y1_start = mean(y1(1:10));
y1_end   = mean(y1(end-10:end));
c_guess  = y1_end;                % Offset is roughly the end value
a_guess  = y1_start - y1_end;     % Amplitude is Drop
b_guess  = 1 / (x1_shift(end)/3); % Assume decay happens over 1/3rd of the window

opts1.StartPoint = [a_guess, b_guess, c_guess];
% BOUNDS: [a, b, c] - b > 0 ensures DECAY
opts1.Lower      = [0,       0,      min(y1)]; 
opts1.Upper      = [Inf,     Inf,    max(y1)]; 

fprintf('Fitting Zone 1...\n');
[fit1, gof1] = fit(x1_shift, y1, ft, opts1);


% --- SETUP ZONE 2 FIT (POST-STIMULUS) ---
opts2 = fitoptions(ft);
opts2.Algorithm = 'Trust-Region';    % FIXED: Correct algorithm name
opts2.Robust    = 'LAR'; 

% ESTIMATES
y2_start = mean(y2(1:5));
y2_end   = mean(y2(end-10:end));
c_guess  = y2_end;
a_guess  = y2_start - y2_end;
b_guess  = 1 / (x2_shift(end)/4); 

opts2.StartPoint = [a_guess, b_guess, c_guess];
% BOUNDS
opts2.Lower      = [0,       0,      min(y2)]; 
opts2.Upper      = [Inf,     Inf,    max(y2)];

fprintf('Fitting Zone 2...\n');
[fit2, gof2] = fit(x2_shift, y2, ft, opts2);

% 3. Generate Curves
y1_curve = feval(fit1, x1_shift);
y2_curve = feval(fit2, x2_shift);

% 4. Report
tau1 = 1 / fit1.b;
tau2 = 1 / fit2.b;

fprintf('\n>>> ZONE 1 (Pre-Stimulus):\n');
fprintf('   y = %.2e * exp(-t/%.1f) + %.2e\n', fit1.a, tau1, fit1.c);
fprintf('   Time Constant: %.1f ms | R^2: %.4f\n', tau1, gof1.rsquare);

fprintf('\n>>> ZONE 2 (Post-Stimulus):\n');
fprintf('   y = %.2e * exp(-(t-1500)/%.1f) + %.2e\n', fit2.a, tau2, fit2.c);
fprintf('   Time Constant: %.1f ms | R^2: %.4f\n', tau2, gof2.rsquare);

% 5. Plot
figure('Name', 'Robust Curve Fit', 'Position', [100 100 1000 600]);
plot(time_ms, raw_signal, 'Color', [0.7 0.7 0.7], 'LineWidth', 1); hold on;
plot(x1, y1_curve, 'b--', 'LineWidth', 2);
plot(x2, y2_curve, 'r--', 'LineWidth', 2);

xline(xlineat, 'k:');
title('Robust Piecewise Fit (Constrained Decay)');
legend('Raw Signal', 'Pre-Stimulus Fit', 'Post-Stimulus Fit');
xlabel('Time (ms)');
ylabel('Amplitude');
grid on;
xlim([time_ms(1) time_ms(end)]);

% Text Labels
text(x1(round(end/2)), fit1.c + fit1.a/2, sprintf('\\tau_{pre} = %.0f ms', tau1), ...
    'Color', 'b', 'FontSize', 12, 'FontWeight', 'bold');
text(x2(round(end/4)), fit2.c + fit2.a/2, sprintf('\\tau_{post} = %.0f ms', tau2), ...
    'Color', 'r', 'FontSize', 12, 'FontWeight', 'bold');
fprintf('=== DONE ===\n');