% generate_multi_ROI.m
% This script loads data, replicates processing, and allows MULTIPLE ROI selections.
clc; close all;
fprintf('=== MULTI-ROI GENERATION TOOL ===\n');

%% 1. DUPLICATE DATA PROCESSING
% (Same logic as before to ensure data matches your view)
if exist('M_smooth', 'var') && exist('sampling_rate', 'var')
    fprintf('Using existing M_smooth from workspace.\n');
else
    fprintf('Data not in workspace. Attempting to load...\n');
    files = dir('data/reconstructed_ICs_*.mat');
    if isempty(files), error('Please run this script after your main script, or ensure data is in /data'); end
    loaded_data = load(fullfile('data', files(1).name));
    M = double(loaded_data.reconstructed_movie);
    
    SIGMA = 2.0; 
    sign_ass = -1;
    [H, W, T] = size(M);
    
    baseline = mean(M(:,:,350:370), 3);
    M_sub = sign_ass * (M - baseline);
    M_smooth = zeros(H, W, T);
    fprintf('Smoothing data...\n');
    for t = 1:T
        M_smooth(:,:,t) = imgaussfilt(M_sub(:,:,t), SIGMA);
    end
    if isfield(loaded_data, 'Fs'), sampling_rate = loaded_data.Fs; else, sampling_rate = 250; end
end

%% 2. GENERATE ACTIVATION MAP
start_frame = 376;       
end_frame = 376 + 40;    
active_window = M_smooth(:,:,start_frame:end_frame);
activation_map = max(active_window, [], 3);

SATURATION_PCT = 98.5;
FLOOR_SENSITIVITY = 0.40;
sat_val = prctile(active_window(:), SATURATION_PCT);
floor_val = sat_val * FLOOR_SENSITIVITY;

%% 3. INTERACTIVE MULTI-ROI DRAWING
f = figure('Name', 'Draw Multiple ROIs', 'Color', 'w', 'Position', [100 100 900 700]);
imagesc(activation_map);
colormap(jet(256));
caxis([floor_val, sat_val]);
colorbar;
axis image;
title({'ACTIVATION MAP', 'Draw an ROI, double-click to finish.', 'Check Command Window to add more.'});

% Initialize storage structure
roi_data = struct('mask', {}, 'coords', {}, 'trace', {}, 'color', {}, 'name', {});
roi_colors = lines(10); % Generate distinct colors for up to 10 ROIs
keep_drawing = true;
count = 1;

% Reshape data once for speed
[H, W, T] = size(M_smooth);
M_reshaped = reshape(M_smooth, H*W, T);

while keep_drawing
    fprintf('\n--- ROI #%d ---\n', count);
    fprintf('Please draw ROI #%d on the figure...\n', count);
    
    % Select color for this ROI
    this_color = roi_colors(mod(count-1, 10) + 1, :);
    
    % Draw
    h_poly = drawpolygon('Color', this_color, 'LineWidth', 2, 'Label', sprintf('ROI %d', count));
    wait(h_poly); % Wait for double-click
    
    % Store Data
    mask = createMask(h_poly);
    roi_data(count).mask = mask;
    roi_data(count).coords = h_poly.Position;
    roi_data(count).color = this_color;
    roi_data(count).name = sprintf('ROI %d', count);
    
    % Extract Trace Immediately
    roi_data(count).trace = mean(M_reshaped(mask(:), :), 1);
    
    % Ask user to continue
    user_choice = input('Draw another ROI? (y/n) [y]: ', 's');
    if strcmpi(user_choice, 'n')
        keep_drawing = false;
    else
        count = count + 1;
    end
end

%% 4. PLOT COMPARISON
figure('Name', 'ROI Comparison', 'Color', 'w', 'Position', [150 150 1000 500]);
hold on;

time_axis = ((0:T-1) - 376) * (1000/sampling_rate); % Time in ms
legend_entries = {};

for i = 1:length(roi_data)
    plot(time_axis, roi_data(i).trace, 'Color', roi_data(i).color, 'LineWidth', 1.5);
    legend_entries{end+1} = roi_data(i).name;
end

xline(0, '--k', 'Stimulus');
xlabel('Time (ms)');
ylabel('dF (ROI Average)');
title(sprintf('Comparison of %d ROIs', length(roi_data)));
legend(legend_entries, 'Location', 'best');
grid on;
hold off;

%% 5. SAVE TO FILE
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
filename = sprintf('data/multi_ROI_trace_%s.mat', timestamp);

% Save the struct containing all info
save(filename, 'roi_data', 'activation_map', 'sampling_rate');
fprintf('\nSuccess! Data saved to: %s\n', filename);
fprintf('Variable "roi_data" is a structure array containing traces and masks for all ROIs.\n');