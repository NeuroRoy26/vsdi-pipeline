% analyze_ROI.m
% Loads a previously saved ROI file and performs post-processing analysis
% including Global vs. ROI traces, SNR, and Peak detection.

clc; close all;
fprintf('=== ROI ANALYSIS & POST-PROCESSING ===\n');

%% 1. LOAD ROI DATA
% Open a dialog to pick the specific ROI file
[roi_file, roi_path] = uigetfile('data/ROI_Data_*.mat', 'Select ROI File');
if isequal(roi_file,0)
    disp('User canceled file selection');
    return;
end
fprintf('Loading: %s ...\n', roi_file);
load(fullfile(roi_path, roi_file)); % Loads: roi_mask, roi_trace, roi_coords, activation_map

%% 2. CHECK FOR MOVIE DATA (Required for Global Trace)
% We need the full movie (M_smooth) to calculate the Global Trace.
if ~exist('M_smooth', 'var')
    fprintf('\n! "M_smooth" variable not found in workspace.\n');
    fprintf('  We need the full movie data to calculate the Global Trace.\n');
    % Option to load the reconstruction file if not in memory
    files = dir('data/reconstructed_ICs_*.mat');
    if ~isempty(files)
        fprintf('  Loading data from: %s...\n', files(1).name);
        tmp = load(fullfile('data', files(1).name));
        M = double(tmp.reconstructed_movie);
        % Quick recreate of M_smooth (simplified)
        baseline = mean(M(:,:,350:370), 3);
        M_smooth = -1 * (M - baseline); % Assuming -1 sign inversion
        sampling_rate = 250; % Default if not found
        if isfield(tmp, 'Fs'), sampling_rate = tmp.Fs; end
    else
        error('Could not find original movie data. Please load your data first.');
    end
else
    if ~exist('sampling_rate', 'var'), sampling_rate = 250; end
end

[H, W, T] = size(M_smooth);

%% 3. CALCULATE TRACES
fprintf('\nCalculating traces...\n');

% A. ROI Trace (Reloaded from file, or re-calculated to be safe)
% Reshape movie to 2D (pixels x time) for fast masking
M_reshaped = reshape(M_smooth, H*W, T);
roi_trace_calc = mean(M_reshaped(roi_mask(:), :), 1);

% B. Global Trace (Mean of the entire image)
global_trace = mean(M_reshaped, 1);

% C. Background Trace (Everything OUTSIDE the ROI)
bg_mask = ~roi_mask;
bg_trace = mean(M_reshaped(bg_mask(:), :), 1);

%% 4. CALCULATE METRICS
stim_frame = 376; % Based on your previous script
pre_stim_window = 1:(stim_frame-10);
post_stim_window = stim_frame:(stim_frame+100); % Look at 100 frames post stim

% Time Vector
time_axis = ((0:T-1) - stim_frame) * (1000/sampling_rate);

% --- Metrics for ROI ---
% Baseline stats
roi_baseline_mean = mean(roi_trace_calc(pre_stim_window));
roi_baseline_std  = std(roi_trace_calc(pre_stim_window));

% Peak stats (in the post-stimulus window)
[roi_peak_val, roi_peak_idx_local] = max(roi_trace_calc(post_stim_window));
roi_peak_idx_global = roi_peak_idx_local + stim_frame - 1;
roi_latency_ms = time_axis(roi_peak_idx_global);

% SNR Calculation (Peak Amplitude / Baseline Noise)
roi_snr = (roi_peak_val - roi_baseline_mean) / roi_baseline_std;

fprintf('\n--- ANALYSIS RESULTS ---\n');
fprintf('ROI Peak Amplitude: %.4f\n', roi_peak_val);
fprintf('ROI Peak Latency:   %.2f ms\n', roi_latency_ms);
fprintf('ROI SNR:            %.2f\n', roi_snr);

%% 5. PLOTTING
figure('Name', 'Post-Processing Analysis', 'Color', 'w', 'Position', [100 100 1200 800]);

% Subplot 1: Spatial View (Where is the ROI?)
subplot(2, 2, 1);
imagesc(activation_map); 
hold on;
plot(roi_coords(:,1), roi_coords(:,2), 'w', 'LineWidth', 2); % White outline
hold off;
axis image off;
colormap(gca, jet(256));
title('ROI Location (White Outline)');

% Subplot 2: Temporal View (Comparison)
subplot(2, 2, [3, 4]); % Spans bottom row
plot(time_axis, global_trace, 'k', 'LineWidth', 1, 'DisplayName', 'Global (Whole Frame)');
hold on;
plot(time_axis, bg_trace, 'Color', [0.5 0.5 0.5], 'LineStyle', ':', 'DisplayName', 'Background (Outside ROI)');
plot(time_axis, roi_trace_calc, 'r', 'LineWidth', 2, 'DisplayName', 'ROI Signal');

% Mark Stimulus
xline(0, '--k', 'Stimulus');

% Mark Peak
plot(roi_latency_ms, roi_peak_val, 'vb', 'MarkerFaceColor', 'b', 'DisplayName', 'Peak');

legend('Location', 'northeast');
xlabel('Time relative to Stimulus (ms)');
ylabel('Signal Intensity (dF)');
title(sprintf('Signal Comparison (ROI SNR = %.2f)', roi_snr));
grid on;
xlim([-50 150]); % Zoom in on the event (adjust as needed)

% Subplot 3: Heatmap of ROI vs Global
% Sometimes it helps to see the "Average ROI pixel" vs "Average Global pixel" side by side as bars
subplot(2, 2, 2);
bar_data = [max(global_trace), max(roi_trace_calc)];
b = bar(bar_data);
b.FaceColor = 'flat';
b.CData(1,:) = [0 0 0]; % Black for Global
b.CData(2,:) = [1 0 0]; % Red for ROI
xticklabels({'Global Peak', 'ROI Peak'});
ylabel('Max Intensity');
title('Response Magnitude Comparison');
grid on;
