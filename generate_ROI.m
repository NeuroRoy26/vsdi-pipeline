% generate_ROI.m
% This script loads data, replicates the processing from v3.6,
% and allows the user to define an ROI based on the active signal.

clc; close all;
fprintf('=== ROI GENERATION TOOL ===\n');

%% 1. DUPLICATE DATA PROCESSING (To ensure image matches your view)
% We reuse the logic from your provided script to ensure the "Image" 
% looks exactly like what you see in the montage.

% --- Load or find data ---
if exist('M_smooth', 'var') && exist('sampling_rate', 'var')
    fprintf('Using existing M_smooth from workspace.\n');
else
    % If variables aren't there, we need to load them (simplified from your script)
    fprintf('Data not in workspace. Attempting to load...\n');
    files = dir('data/reconstructed_ICs_*.mat');
    if isempty(files), error('Please run this script after your main script, or ensure data is in /data'); end
    loaded_data = load(fullfile('data', files(1).name));
    M = double(loaded_data.reconstructed_movie);
    
    % Re-apply smoothing and baseline
    SIGMA = 2.0; 
    sign_ass = -1;
    [H, W, T] = size(M);
    
    baseline = mean(M(:,:,350:370), 3);
    M_sub = sign_ass * (M - baseline);
    M_smooth = zeros(H, W, T);
    fprintf('Smoothing data (this may take a moment)...\n');
    for t = 1:T
        M_smooth(:,:,t) = imgaussfilt(M_sub(:,:,t), SIGMA);
    end
    if isfield(loaded_data, 'Fs'), sampling_rate = loaded_data.Fs; else, sampling_rate = 250; end
end

%% 2. GENERATE ACTIVATION MAP
% We take the Maximum Intensity Projection (MIP) of the active window.
% This captures the full extent of the "Yellow" signal over time.

start_frame = 376;       % Stimulus start
end_frame = 376 + 40;    % Look at 40 frames post-stimulus to capture the wave
active_window = M_smooth(:,:,start_frame:end_frame);

% Calculate Max Projection (collapses time to show the footprint of signal)
activation_map = max(active_window, [], 3);

% Calculate thresholds exactly like your script
SATURATION_PCT = 98.5;
FLOOR_SENSITIVITY = 0.40;
sat_val = prctile(active_window(:), SATURATION_PCT);
floor_val = sat_val * FLOOR_SENSITIVITY;

%% 3. INTERACTIVE ROI DRAWING
f = figure('Name', 'Draw ROI', 'Color', 'w', 'Position', [100 100 900 700]);

% Show the map
imagesc(activation_map);
colormap(jet(256));
caxis([floor_val, sat_val]); % Apply same limits so "Yellow" looks the same
colorbar;
axis image;
title({'ACTIVATION MAP (Max Projection)', 'Click points to draw ROI around the yellow area.', 'Double-click to finish.'});

fprintf('\n--> Please draw the ROI polygon on the figure window.\n');
fprintf('--> Double-click inside the polygon to finalize it.\n');

% Draw Polygon Tool
h_poly = drawpolygon('Color', 'm', 'LineWidth', 2);
wait(h_poly); % Wait for user to finish drawing

% Create Binary Mask
roi_mask = createMask(h_poly);
roi_coords = h_poly.Position;

%% 4. EXTRACT TRACE & SAVE
% Calculate the average signal trace inside this ROI
[H, W, T] = size(M_smooth);
roi_trace = zeros(1, T);

% Reshape for quick calculation
M_reshaped = reshape(M_smooth, H*W, T);
mask_flat = roi_mask(:);

% Calculate mean only for pixels inside mask
roi_trace = mean(M_reshaped(mask_flat, :), 1);

% Plot the result to confirm
figure('Name', 'ROI Trace', 'Color', 'w');
time_axis = ((0:T-1) - 376) * (1000/sampling_rate); % Align 0 to stimulus
plot(time_axis, roi_trace, 'r', 'LineWidth', 1.5);
xline(0, '--k', 'Stimulus');
xlabel('Time (ms)');
ylabel('dF (ROI Average)');
title('Extracted Signal from Drawn ROI');
grid on;

%% 5. SAVE TO FILE
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
filename = sprintf('data/ROI_Trace_%s.mat', timestamp);

save(filename, 'roi_mask', 'roi_coords', 'roi_trace', 'activation_map');
fprintf('\nSuccess! ROI saved as: %s\n', filename);
fprintf('Contains: roi_mask (logical), roi_coords (xy), roi_trace (vector)\n');