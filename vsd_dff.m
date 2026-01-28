% diagnostic/accesory script
%run this after run_single_trials.m or run_trial_averaging.m
clc; clear; close all;

%% 1. UI: Select Processed File
fprintf('Select the PROCESSED (*_dff.h5) file...\n');
[file_name, path_name] = uigetfile('*_dff.h5', 'Select Processed DFF File');
if isequal(file_name, 0)
    disp('User canceled.');
    return;
end
full_path = fullfile(path_name, file_name);

%% 2. Load Data
% Check available datasets (in case naming changed)
info = h5info(full_path);
dataset_names = {info.Datasets.Name};

% Prefer 'functional_dff', fallback to first available if not found
if any(strcmp(dataset_names, 'functional_dff'))
    dset_name = '/functional_dff';
else
    dset_name = ['/' dataset_names{1}];
    warning('Dataset /functional_dff not found. Using %s instead.', dset_name);
end

fprintf('Loading %s ...\n', dset_name);
data = h5read(full_path, dset_name);
[H, W, T] = size(data);

%% 3. Pre-processing for Waterfall
% "Waterfall" usually implies Space vs Time.
% We collapse the Width dimension to get a (Rows x Time) matrix.
% This visualizes activity moving Top <-> Bottom.

% Calculate Mean of each Row (Spatial Profile)
% Result is H x T matrix
spatial_profile = squeeze(mean(data, 2)); 

% Optional: Smooth slightly for prettier plotting
spatial_profile = imgaussfilt(spatial_profile, 0.5);

%% 4. Visualization 1: Space-Time Heatmap
% This is the most informative "dense" waterfall view
figure('Name', 'Space-Time Heatmap', 'Color', 'w', 'Position', [100 100 800 600]);

% Create time vector (frames)
t_vec = 1:T;

subplot(1, 10, 1:9); % Use most of the space for the plot
imagesc(t_vec, 1:H, spatial_profile);
colormap(jet); % 'jet' or 'parula' are standard for VSD
colorbar;
xlabel('Time (frames)');
ylabel('Vertical Position (Row Index)');
title(['Spatiotemporal Propagation: ' file_name], 'Interpreter', 'none');
set(gca, 'YDir', 'normal'); % Origin at bottom (or 'reverse' for image coords)

%% 6. Visualization 3: Activity Montage (Smart Subsampled)
fprintf('Generating Montage...\n');

% --- A. Configuration ---
% Max tiles to show (prevents crashing with "a lot of frames")
% A 10x10 grid is usually the limit of readability.
MAX_TILES = 250; 

[H, W, T] = size(data);

% --- B. Smart Subsampling ---
if T > MAX_TILES
    % Calculate equal spacing to fit within MAX_TILES
    frame_indices = round(linspace(1, T, MAX_TILES));
    fprintf('  [INFO] Too many frames (%d). Subsampling to %d frames for montage.\n', T, length(frame_indices));
else
    frame_indices = 1:T;
end

% Extract subset
montage_stack = data(:, :, frame_indices);

% --- C. Reshape for Montage Function ---
% montage() expects 4D input: H x W x ColorChannels(1) x NumberOfFrames
montage_input = reshape(montage_stack, [H, W, 1, length(frame_indices)]);

% --- D. Determine Color Scaling ---
% We need a fixed scale so frame 1 is comparable to frame 100.
% We use the 1st and 99th percentile to avoid hot pixels skewing the view.
all_vals = montage_stack(:);
clim_min = prctile(all_vals, 1); 
clim_max = prctile(all_vals, 99);

% --- E. Plot ---
figure('Name', 'DFF Activity Montage', 'Color', 'w', 'Position', [50 50 1000 800]);

% Plot the montage
hM = montage(montage_input, 'DisplayRange', [clim_min clim_max], 'Size', [NaN 10]); 
% 'Size', [NaN 10] means "Auto calculate rows, but fix columns to 10"

% Aesthetics
colormap(jet); % 'jet' is standard for VSD, 'parula' is softer
c = colorbar;
c.Label.String = '\Delta F / F';

title(sprintf('%d frames linearly spaced across Indices: %d to %d', ...
    length(frame_indices), frame_indices(1), frame_indices(end)));

fprintf('Montage generation complete.\n');

%% Optional: Video Player
% If you really want to see ALL frames, use the Video Player instead of a plot
% implay(data);
% %% 7. Visualization 4: Manual Point Selection on Structural Map
% fprintf('Opening selection window on STRUCTURAL image...\n');
% 
% % --- A. Load Structural Data ---
% % Attempt to load the structural image saved in the file
% try
%     % Try loading the structural dataset we saved earlier
%     ref_map = h5read(full_path, '/structural');
% 
%     % If structural data is a stack (3D), take the mean to get one image
%     if ndims(ref_map) == 3
%         ref_map = mean(ref_map, 3);
%     end
%     fprintf('  [INFO] Structural data loaded for background.\n');
% 
% catch
%     % Fallback if structural data is missing
%     warning('  [WARN] /structural dataset not found. Using std. dev. instead.');
%     ref_map = std(data, 0, 3);
% end
% 
% [H, W, T] = size(data);
% t_vec = 1:T;
% 
% % --- B. Selection Window ---
% hFigSelect = figure('Name', 'Select Points (Structural)', 'Color', 'w');
% imagesc(ref_map); 
% axis image; 
% colormap(gca, 'gray'); 
% title('CLICK to select points (Anatomy). Press ENTER when done.');
% hold on;
% 
% % --- C. User Interaction ---
% [x_clicks, y_clicks] = ginput(30); 
% 
% n_selected = length(x_clicks);
% if n_selected == 0
%     warning('No points selected. Skipping visualization.');
%     return;
% end
% fprintf('You selected %d points.\n', n_selected);
% close(hFigSelect); 
% 
% % --- D. Process Coordinates ---
% sel_x = round(x_clicks);
% sel_y = round(y_clicks);
% 
% % Clamp to boundaries
% sel_x = max(1, min(W, sel_x));
% sel_y = max(1, min(H, sel_y));
% 
% % --- E. Extract Traces ---
% raw_traces = zeros(n_selected, T);
% for i = 1:n_selected
%     raw_traces(i, :) = squeeze(data(sel_y(i), sel_x(i), :));
% end
% 
% % --- F. Figure 1: The Structural Map ---
% figure('Name', 'Selected Points on Structure', 'Color', 'w', 'Position', [50 100 600 600]);
% imagesc(ref_map);
% axis image; 
% colormap(gca, 'gray'); 
% hold on;
% title(sprintf('Selected Locations (%d points)', n_selected));
% xlabel('X Pixel'); ylabel('Y Pixel');
% 
% for i = 1:n_selected
%     plot(sel_x(i), sel_y(i), 'o', ...
%         'MarkerSize', 8, ...
%         'MarkerFaceColor', 'r', ...
%         'MarkerEdgeColor', 'w', ...
%         'LineWidth', 1.5);
% 
%     text(sel_x(i)+4, sel_y(i), num2str(i), ...
%         'Color', 'y', 'FontSize', 10, 'FontWeight', 'bold');
% end
% hold off;
% 
% % --- G. Figure 2: The Waterfall (Black Traces) ---
% figure('Name', 'Waterfall Traces', 'Color', 'w', 'Position', [700 100 800 600]);
% hold on;
% title('Activity Traces (Manual Selection)');
% xlabel('Time (frames)');
% ylabel('Selection Order');
% 
% if n_selected > 1
%     trace_range = max(raw_traces(:)) - min(raw_traces(:));
%     offset_step = trace_range * 0.5; 
% else
%     offset_step = 0;
% end
% 
% for i = 1:n_selected
%     trace = raw_traces(i, :);
%     vertical_pos = (i-1) * offset_step;
% 
%     plot(t_vec, trace + vertical_pos, 'k', 'LineWidth', 1.2);
% 
%     text(1, vertical_pos, sprintf('#%d ', i), ...
%         'Color', 'k', ...
%         'FontSize', 9, ...
%         'FontWeight', 'bold', ...
%         'HorizontalAlignment', 'right');
% end
% 
% axis tight; 
% xlim([1-T*0.05, T]); 
% set(gca, 'YTick', []); 
% grid on;
% box off;

                                                                                                                                                                                                                                                               
fprintf('Done.\n');