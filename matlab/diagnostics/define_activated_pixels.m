clc; clear; close all;
% -----------------------------------------------------------------
%              define_activated_pixels.m
% -----------------------------------------------------------------
% Purpose: Define "activated" pixels by thresholding the averaged dF/F 
%          movie using adaptive per-pixel baseline statistics.
% 
% Input:   averaged_dff_E0B0-B3.h5 (from run_trial_averaging_v2.m)
% Output:  activation_results.mat, activation_results.h5
%          + 3 diagnostic figures
% -----------------------------------------------------------------

%% 1. Load the Averaged dF/F Movie
fprintf('========================================\n');
fprintf('DEFINE ACTIVATED PIXELS - THRESHOLDING\n');
fprintf('========================================\n\n');

input_h5_file = 'data/averaged_movie_E0B0-E0B3.h5';
fprintf('Loading averaged dF/F movie from: %s\n', input_h5_file);

try
    average_dff_movie = h5read(input_h5_file, '/functional_dff');
    [H, W, T] = size(average_dff_movie);
    fprintf('  Dimensions: [%d, %d, %d] (Height × Width × Time)\n', H, W, T);
catch ME
    error('Failed to load dF/F movie. Error: %s', ME.message);
end

%% 2. Define Binned Baseline Period
% Raw baseline was frames 1-100. With bin size 5, binned baseline is frames 1-20.
bin_size = 5;
raw_baseline_frames = 100;
binned_baseline_end = floor(raw_baseline_frames / bin_size);  % = 20

fprintf('\nDefining binned baseline period...\n');
fprintf('  Raw baseline frames: 1-%d\n', raw_baseline_frames);
fprintf('  Bin size: %d\n', bin_size);
fprintf('  Binned baseline frames: 1-%d\n', binned_baseline_end);

baseline_dff = average_dff_movie(:, :, 1:binned_baseline_end);
fprintf('  Baseline movie dimensions: [%d, %d, %d]\n', size(baseline_dff, 1), size(baseline_dff, 2), size(baseline_dff, 3));

%% 3. Calculate Per-Pixel Baseline Statistics
fprintf('\nCalculating per-pixel baseline statistics...\n');

mean_baseline_map = mean(baseline_dff, 3);   % [H, W]
std_baseline_map = std(baseline_dff, 0, 3);  % [H, W]

fprintf('  Mean baseline - Range: [%.4f, %.4f]\n', min(mean_baseline_map(:)), max(mean_baseline_map(:)));
fprintf('  Std baseline  - Range: [%.4f, %.4f]\n', min(std_baseline_map(:)), max(std_baseline_map(:)));

%% 4. Create Threshold Map
% Threshold = Mean(Baseline) + 5 * StdDev(Baseline)
fprintf('\nCreating adaptive threshold map...\n');

threshold_multiplier = 5;
threshold_map = mean_baseline_map + (threshold_multiplier * std_baseline_map);

fprintf('  Threshold multiplier: %.1f × StdDev\n', threshold_multiplier);
fprintf('  Threshold map - Range: [%.4f, %.4f]\n', min(threshold_map(:)), max(threshold_map(:)));

%% 5. Generate Binary Activation Mask
fprintf('\nGenerating binary activation mask...\n');

% Compare each timepoint against the threshold map
activation_mask = average_dff_movie > threshold_map;  % [H, W, T] logical

% Convert to uint8 for memory efficiency
activation_mask_uint8 = uint8(activation_mask);

fprintf('  Activation mask dimensions: [%d, %d, %d]\n', size(activation_mask, 1), size(activation_mask, 2), size(activation_mask, 3));
fprintf('  Data type: uint8 (0=inactive, 1=active)\n');

%% 6. Calculate Activation Statistics
fprintf('\nCalculating activation statistics...\n');

% Activated pixels per frame
activated_pixels_per_frame = squeeze(sum(sum(activation_mask, 1), 2));  % [T, 1]
total_pixels = H * W;
percent_active_per_frame = (activated_pixels_per_frame / total_pixels) * 100;

fprintf('  Total pixels: %d\n', total_pixels);
fprintf('  Active pixels per frame - Min: %d, Max: %d, Mean: %.1f\n', ...
    min(activated_pixels_per_frame), max(activated_pixels_per_frame), mean(activated_pixels_per_frame));
fprintf('  Percent active - Min: %.2f%%, Max: %.2f%%, Mean: %.2f%%\n', ...
    min(percent_active_per_frame), max(percent_active_per_frame), mean(percent_active_per_frame));

%% 7. Save Results to MAT File
fprintf('\nSaving results to MAT file...\n');

output_mat_file = 'data/activation_results.mat';

save(output_mat_file, ...
    'activation_mask', ...
    'activation_mask_uint8', ...
    'mean_baseline_map', ...
    'std_baseline_map', ...
    'threshold_map', ...
    'activated_pixels_per_frame', ...
    'percent_active_per_frame', ...
    'H', 'W', 'T', ...
    'bin_size', 'threshold_multiplier');

fprintf('  Saved to: %s\n', output_mat_file);

%% 8. Save Results to HDF5 File
fprintf('\nSaving results to HDF5 file...\n');

output_h5_file = 'data/activation_results.h5';

% Delete if exists
if isfile(output_h5_file)
    delete(output_h5_file);
end

% Create and write datasets
h5create(output_h5_file, '/activation_mask', size(activation_mask_uint8), 'DataType', 'uint8');
h5write(output_h5_file, '/activation_mask', activation_mask_uint8);

h5create(output_h5_file, '/mean_baseline_map', size(mean_baseline_map), 'DataType', 'double');
h5write(output_h5_file, '/mean_baseline_map', mean_baseline_map);

h5create(output_h5_file, '/std_baseline_map', size(std_baseline_map), 'DataType', 'double');
h5write(output_h5_file, '/std_baseline_map', std_baseline_map);

h5create(output_h5_file, '/threshold_map', size(threshold_map), 'DataType', 'double');
h5write(output_h5_file, '/threshold_map', threshold_map);

h5create(output_h5_file, '/activated_pixels_per_frame', size(activated_pixels_per_frame), 'DataType', 'double');
h5write(output_h5_file, '/activated_pixels_per_frame', activated_pixels_per_frame);

fprintf('  Saved to: %s\n', output_h5_file);

%% 9. Create Diagnostic Figures
fprintf('\nCreating diagnostic figures...\n');

% Figure 1: Activation Dynamics
figure('Name', 'Activation Dynamics', 'NumberTitle', 'off');
plot(1:T, activated_pixels_per_frame, 'b-', 'LineWidth', 2);
hold on;
plot(1:binned_baseline_end, activated_pixels_per_frame(1:binned_baseline_end), 'r-', 'LineWidth', 2);
xlabel('Frame'); ylabel('Number of Activated Pixels'); 
title('Active Pixel Count Over Time');
legend('All frames', 'Baseline period (1-20)', 'Location', 'best');
grid on;
set(gca, 'FontSize', 11);

% Figure 2: Baseline Statistics Maps
figure('Name', 'Baseline Statistics', 'NumberTitle', 'off');

subplot(1, 3, 1);
imagesc(mean_baseline_map);
colorbar; axis image;
title('Mean Baseline (dF/F)');
set(gca, 'FontSize', 10);

subplot(1, 3, 2);
imagesc(std_baseline_map);
colorbar; axis image;
title('Std Dev Baseline (dF/F)');
set(gca, 'FontSize', 10);

subplot(1, 3, 3);
imagesc(threshold_map);
colorbar; axis image;
title(sprintf('Threshold Map (Mean + 5×Std)'));
set(gca, 'FontSize', 10);

% Figure 3: Sample Frame Comparisons
figure('Name', 'Sample Frame Comparisons', 'NumberTitle', 'o');

% Select a few sample frames from different periods
sample_frames = [10, 40, 75, 120];  % Early baseline, mid, late, recent

for i = 1:length(sample_frames)
    frame_idx = sample_frames(i);
    
    % dF/F frame
    subplot(2, 4, i);
    imagesc(average_dff_movie(:, :, frame_idx));
    colorbar; axis image;
    title(sprintf('dF/F Frame %d', frame_idx));
    set(gca, 'FontSize', 9);
    
    % Activation mask frame
    subplot(2, 4, 4 + i);
    imagesc(activation_mask(:, :, frame_idx));
    colorbar; axis image; clim([0 1]);
    title(sprintf('Mask Frame %d', frame_idx));
    set(gca, 'FontSize', 9);
end

fprintf('  Generated 3 figures\n');

%% 10. Print Summary Report
fprintf('\n');
fprintf('========================================\n');
fprintf('PROCESSING COMPLETE\n');
fprintf('========================================\n');
fprintf('Input file:  %s\n', input_h5_file);
fprintf('Output files:\n');
fprintf('  - %s\n', output_mat_file);
fprintf('  - %s\n', output_h5_file);
fprintf('  - 3 diagnostic figures\n');
fprintf('\nKey Results:\n');
fprintf('  Movie dimensions: [%d, %d, %d]\n', H, W, T);
fprintf('  Baseline period (binned): frames 1-%d\n', binned_baseline_end);
fprintf('  Threshold method: Mean + 5×StdDev\n');
fprintf('  Activation mask type: uint8 (0=inactive, 1=active)\n');
fprintf('  Total pixels: %d\n', total_pixels);
fprintf('  Average active pixels per frame: %.1f (%.2f%%)\n', ...
    mean(activated_pixels_per_frame), mean(percent_active_per_frame));
fprintf('========================================\n\n');