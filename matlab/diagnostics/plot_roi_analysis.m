%%
clc; clear; close all;
%% Load Data
%h5_file = 'C:/Roy/MSc/Thesis/Scripts/data/averaged_movie_E0B0-E0B3.h5';
 h5_file = 'C:/Roy/MSc/Thesis/Scripts/data/led_E0B0_dff.h5';

dff_averaged = h5read(h5_file, '/functional_dff');
[H, W, T] = size(dff_averaged); % T should be 150
fprintf('Loaded averaged movie: %d x %d x %d (H x W x T)\n', H, W, T);

%% Pick out ROIs
% frame_76 = dff_averaged(:,:,76);
% frame_75 = dff_averaged(:,:,75);
% frame_77 = dff_averaged(:,:,77);
% 
% figure(1);
% imagesc(frame_76);
% colormap('parula'); % 'parula' or 'hot' work well
% colorbar;
% figure(2);
% imagesc(frame_75);
% colormap('parula'); % 'parula' or 'hot' work well
% colorbar;
% figure(3);
% imagesc(frame_77);
% colormap('parula'); % 'parula' or 'hot' work well

%% activity tracer on ROIs
% --- 2. Define ROIs from Your Coordinates ---
% ROI positions from the data cursor saved as ROI1.mat & ROI2.mat files
% Note: datacursor gives [X, Y], but MATLAB indexes as (Y, X)
pos1 = [285 119]; % [X, Y]
pos2 = [56 326];  % [X, Y]

% We will make a 10x10 pixel box around each point
roi_size = 10;
half_size = round(roi_size / 2);

% --- Create ROI 1 Mask ---
y1_center = pos1(2); % The Y-position
x1_center = pos1(1); % The X-position
% Define box boundaries, clamping to the image edges
y1_min = max(1, y1_center - half_size);
y1_max = min(H, y1_center + half_size);
x1_min = max(1, x1_center - half_size);
x1_max = min(W, x1_center + half_size);

% --- Create ROI 2 Mask ---
y2_center = pos2(2); % The Y-position
x2_center = pos2(1); % The X-position
% Define box boundaries, clamping to the image edges
y2_min = max(1, y2_center - half_size);
y2_max = min(H, y2_center + half_size);
x2_min = max(1, x2_center - half_size);
x2_max = min(W, x2_center + half_size);

[X, Y] = meshgrid(1:W, 1:H);
roi_1_mask = (X >= x1_min & X <= x1_max & Y >= y1_min & Y <= y1_max);
roi_2_mask = (X >= x2_min & X <= x2_max & Y >= y2_min & Y <= y2_max);

fprintf('Created 10x10 ROI 1 at (Y, X) = (%d, %d)\n', y1_center, x1_center);
fprintf('Created 10x10 ROI 2 at (Y, X) = (%d, %d)\n', y2_center, x2_center);

% Reshape data to (total_pixels x time) for easy indexing
dff_flat = reshape(dff_averaged, H*W, T);

trace_1 = mean(dff_flat(roi_1_mask(:), :), 1, 'omitnan');
trace_2 = mean(dff_flat(roi_2_mask(:), :), 1, 'omitnan');

% 2.0 ms/frame (from log_E0.txt) * 5 frame bin
ms_per_binned_frame = 2.0 * 5; % = 10 ms per frame
time_ms = (0:T-1) * ms_per_binned_frame;

% Stimulus onset is binned frame 76
% (76-1) frames * 10 ms/frame = 750 ms
stim_onset_ms = (76-1) * ms_per_binned_frame;

%% --- 5. Plot the Traces (The "Money Plot") --- 🎯
figure(1);
set(gcf, 'Color', 'w'); % Set white background
plot(time_ms, trace_1, 'Color', 'r', 'LineWidth', 2);
hold on;
plot(time_ms, trace_2, 'Color', 'b', 'LineWidth', 2);

xlabel('Time (ms)');
ylabel('\DeltaF/F (Averaged Signal)');
title('Activity Traces from Two Spatial ROIs');
legend('ROI 1 (Position: 285, 119)', 'ROI 2 (Position: 56, 326)');

xline(stim_onset_ms, 'k--', '750 ms', 'LineWidth', 0.5);
grid on;
ax = gca;
ax.FontSize = 12;
ax.Box = 'off';

%% Total energy of each frame
global_signal = squeeze(mean(mean(dff_averaged, 1, 'omitnan'), 2, 'omitnan'));

figure(2);
plot(time_ms, global_signal, 'LineWidth', 1);
xlabel('Time (ms)');
ylabel('Global Mean \DeltaF/F');
title('Global Signal ("Total Energy") Over Time');
hold on;
xline(stim_onset_ms, 'r--', '750 ms');
grid on;

%% Plotting the blob with -50ms and +100ms
stim_onset_frame = 76; % Binned frame

% -50 ms: 50 ms / 10 ms/frame = 5 frames. -> Frame (76 - 5) = 71
start_frame = stim_onset_frame - 5;
% +100 ms: 100 ms / 10 ms/frame = 10 frames. -> Frame (76 + 10) = 86
end_frame = stim_onset_frame + 10;
frames_to_plot = start_frame:end_frame;

dffRange = [-0.01, 0.04]; 

% ---  Montage Plot ---
figure(3);
num_plots = length(frames_to_plot);
% Create a grid (e.g., 4x4)
plot_rows = 4;
plot_cols = 4;

for i = 1:num_plots
    frame_idx = frames_to_plot(i);
    % Calculate time relative to stimulus onset
    time_rel_stim_ms = (frame_idx - stim_onset_frame) * ms_per_binned_frame; 
    
    subplot(plot_rows, plot_cols, i);
    imagesc(dff_averaged(:,:,frame_idx));
    axis image off;
    colormap('parula'); 
    clim(dffRange); % Use a FIXED range!
    title(sprintf('%.0f ms', time_rel_stim_ms));
end
sgtitle('Activity Around Stimulus Onset (-50ms to +100ms)');

%% Subtract prestimulus frames with post stimulus frames
% post_stim_start = 76; % Binned frame 76
% % average the first 200ms of stimulation
% % 200ms / 10 ms/frame = 20 frames
% post_stim_end = post_stim_start + 10; 
% post_stim_frames = post_stim_start : post_stim_end;
% 
% dff_summary_image = mean(dff_averaged(:,:,post_stim_frames), 3, 'omitnan');
% 
% figure(4);
% imagesc(dff_summary_image);
% axis image off;
% colormap('parula');
% colorbar;
% title(sprintf('\\DeltaF/F (Average of %d-%d ms post-stim)', 0, 200));
% 
% max_val = max(abs(dff_summary_image(:)), [], 'omitnan');
% clim([-max_val, max_val]);
% % clim([0.001, 0.01]);

%% kymograph plot
row_center = 250;
slice_thickness = 400; 
half_slice = round(slice_thickness / 2);
row_start = max(1, row_center - half_slice);
row_end   = min(H, row_center + half_slice);
dff_slice = dff_averaged(row_start:row_end, :, :);
kymograph_data = squeeze(mean(dff_slice, 1, 'omitnan'));
fprintf('Created kymograph by averaging rows %d to %d\n', row_start, row_end);

figure(5);
imagesc(time_ms, 1:W, kymograph_data'); % transpose
xlabel('Time (ms)');
ylabel('Spatial Position (X-pixel)');
title(sprintf('Averaged Space-Time Kymograph (Y-pixels %d-%d)', row_start, row_end));
colormap('parula');
colorbar;
clim(dffRange); 
hold on;
xline(stim_onset_ms, 'r--', 'Stimulus Onset');