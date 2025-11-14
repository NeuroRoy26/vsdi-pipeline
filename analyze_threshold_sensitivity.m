clc; clear; close all;
% -----------------------------------------------------------------
%    analyze_threshold_sensitivity_OPTIMIZED.m
% -----------------------------------------------------------------
% Optimized version that processes multipliers sequentially
% and saves directly to HDF5 to avoid memory overflow
% -----------------------------------------------------------------

clear all; close all; clc;

%% 1. Load the Averaged dF/F Movie
fprintf('========================================\n');
fprintf('THRESHOLD SENSITIVITY ANALYSIS (OPTIMIZED)\n');
fprintf('========================================\n\n');

input_h5_file = 'data/preprocessing/averaged_movie_E0B0-B3.h5';
fprintf('Loading averaged dF/F movie from: %s\n', input_h5_file);

try
    average_dff_movie = h5read(input_h5_file, '/functional_dff');
    [H, W, T] = size(average_dff_movie);
    fprintf('  Dimensions: [%d, %d, %d] (Height × Width × Time)\n', H, W, T);
catch ME
    error('Failed to load dF/F movie. Error: %s', ME.message);
end

%% 2. Define Binned Baseline Period
bin_size = 5;
raw_baseline_frames = 100;
binned_baseline_end = floor(raw_baseline_frames / bin_size);

fprintf('\nDefining binned baseline period...\n');
fprintf('  Raw baseline frames: 1-%d\n', raw_baseline_frames);
fprintf('  Bin size: %d\n', bin_size);
fprintf('  Binned baseline frames: 1-%d\n', binned_baseline_end);

baseline_dff = average_dff_movie(:, :, 1:binned_baseline_end);
fprintf('  Baseline movie dimensions: [%d, %d, %d]\n', size(baseline_dff, 1), size(baseline_dff, 2), size(baseline_dff, 3));

%% 3. Calculate Per-Pixel Baseline Statistics (ONCE)
fprintf('\nCalculating per-pixel baseline statistics...\n');

mean_baseline_map = mean(baseline_dff, 3);
std_baseline_map = std(baseline_dff, 0, 3);

fprintf('  Mean baseline - Range: [%.6f, %.6f]\n', min(mean_baseline_map(:)), max(mean_baseline_map(:)));
fprintf('  Std baseline  - Range: [%.6f, %.6f]\n', min(std_baseline_map(:)), max(std_baseline_map(:)));

% Baseline signal-to-noise ratio
snr_map = mean_baseline_map ./ std_baseline_map;
snr_map(isinf(snr_map) | isnan(snr_map)) = 0;
fprintf('  SNR (Mean/Std) - Range: [%.4f, %.4f], Mean: %.4f\n', ...
    min(snr_map(:)), max(snr_map(:)), mean(snr_map(snr_map > 0)));

%% 4. VALIDATE BASELINE PERIOD
fprintf('\nValidating baseline period (frames 1-%d)...\n', binned_baseline_end);

baseline_activity = squeeze(max(max(baseline_dff, [], 1), [], 2));
fprintf('  Max signal in baseline: %.6f\n', max(baseline_activity));
fprintf('  Min signal in baseline: %.6f\n', min(baseline_activity));
fprintf('  Mean signal in baseline: %.6f\n', mean(baseline_activity));

if max(baseline_activity) > mean(baseline_activity) * 2
    fprintf('  ⚠ WARNING: Baseline may contain significant activity!\n');
else
    fprintf('  ✓ Baseline appears quiet.\n');
end

%% 5. SENSITIVITY SWEEP: Process Each Multiplier Sequentially
fprintf('\n========================================\n');
fprintf('SENSITIVITY SWEEP\n');
fprintf('========================================\n\n');

multipliers = [3, 4, 5, 6, 7];
num_multipliers = length(multipliers);

% Initialize storage for summary statistics as a cell array instead
summary_stats = cell(num_multipliers, 1);
all_comparisons = [];

total_pixels = H * W;

fprintf('Testing multipliers: %s\n\n', sprintf('%d× ', multipliers));

for idx = 1:num_multipliers
    mult = multipliers(idx);
    fprintf('Processing multiplier: %d×\n', mult);
    
    % Create threshold map for this multiplier
    threshold_map = mean_baseline_map + (mult * std_baseline_map);
    
    % Generate activation mask for ALL frames
    threshold_map_expanded = repmat(threshold_map, 1, 1, T);
    activation_mask = average_dff_movie > threshold_map_expanded;
    activation_mask_uint8 = uint8(activation_mask);
    
    % Verify dimensions
    fprintf('  ✓ Activation mask dimensions: [%d, %d, %d]\n', ...
        size(activation_mask, 1), size(activation_mask, 2), size(activation_mask, 3));
    
    % Calculate statistics
    activated_pixels_per_frame = squeeze(sum(sum(activation_mask, 1), 2));
    percent_active_per_frame = (activated_pixels_per_frame / total_pixels) * 100;
    
    % Summary statistics - store in cell array
    stats = struct();
    stats.multiplier = mult;
    stats.threshold_range = [min(threshold_map(:)), max(threshold_map(:))];
    stats.min_active_pixels = min(activated_pixels_per_frame);
    stats.max_active_pixels = max(activated_pixels_per_frame);
    stats.mean_active_pixels = mean(activated_pixels_per_frame);
    stats.min_percent = min(percent_active_per_frame);
    stats.max_percent = max(percent_active_per_frame);
    stats.mean_percent = mean(percent_active_per_frame);
    stats.baseline_mean_percent = mean(percent_active_per_frame(1:binned_baseline_end));
    stats.post_baseline_mean_percent = mean(percent_active_per_frame(binned_baseline_end+1:end));
    
    % Store in cell array
    summary_stats{idx} = stats;
    all_comparisons = [all_comparisons; percent_active_per_frame];
    
    % Print statistics
    fprintf('  Threshold range: [%.6f, %.6f]\n', stats.threshold_range(1), stats.threshold_range(2));
    fprintf('  Active pixels - Min: %d, Max: %d, Mean: %.1f\n', ...
        stats.min_active_pixels, stats.max_active_pixels, stats.mean_active_pixels);
    fprintf('  Active percent - Min: %.2f%%, Max: %.2f%%, Mean: %.2f%%\n', ...
        stats.min_percent, stats.max_percent, stats.mean_percent);
    fprintf('  Baseline period percent: %.2f%%\n', stats.baseline_mean_percent);
    fprintf('  Post-baseline period percent: %.2f%%\n\n', stats.post_baseline_mean_percent);
    
    %% 6. Save Individual Mask to HDF5 (immediately, to free memory)
    output_h5_file = sprintf('data/activation_mask_%dx.h5', mult);
    
    if isfile(output_h5_file)
        delete(output_h5_file);
    end
    
    h5create(output_h5_file, '/activation_mask', size(activation_mask_uint8), 'DataType', 'uint8');
    h5write(output_h5_file, '/activation_mask', activation_mask_uint8);
    
    % Also save the per-frame statistics
    h5create(output_h5_file, '/activated_pixels_per_frame', size(activated_pixels_per_frame), 'DataType', 'double');
    h5write(output_h5_file, '/activated_pixels_per_frame', activated_pixels_per_frame);
    
    h5create(output_h5_file, '/percent_active_per_frame', size(percent_active_per_frame), 'DataType', 'double');
    h5write(output_h5_file, '/percent_active_per_frame', percent_active_per_frame);
    
    fprintf('  Saved: %s\n', output_h5_file);
    
    % Clear large variables to free memory
    %clear activation_mask activation_mask_uint8 threshold_map threshold_map_expanded activated_pixels_per_frame percent_active_per_frame;
end
%% 7. Create Comparative Visualization Figures (using saved statistics)
fprintf('\nCreating diagnostic figures...\n');

% Figure 1: Activation Dynamics Comparison (All Multipliers)
figure('Name', 'Comparative Activation Dynamics', 'NumberTitle', 'off', 'Position', [100, 100, 1200, 600]);

colors = {'r', 'g', 'b', 'c', 'm'};
hold on;
for idx = 1:num_multipliers
    mult = multipliers(idx);
    % Reload just the percent_active data for plotting
    h5_file = sprintf('data/activation_mask_%dx.h5', mult);
    percent_active = h5read(h5_file, '/percent_active_per_frame');
    plot(1:T, percent_active, 'Color', colors{idx}, 'LineWidth', 2, 'DisplayName', sprintf('%d×', mult));
end

yLimits = ylim;
plot([binned_baseline_end + 0.5, binned_baseline_end + 0.5], yLimits, 'k--', 'LineWidth', 1.5, 'DisplayName', 'Baseline End');

xlabel('Frame', 'FontSize', 12); 
ylabel('Activated Pixels (%)', 'FontSize', 12); 
title('Activation Dynamics: Sensitivity to Threshold Multiplier', 'FontSize', 14, 'FontWeight', 'bold');
legend(sprintf('%d×', multipliers(1)), sprintf('%d×', multipliers(2)), sprintf('%d×', multipliers(3)), ...
       sprintf('%d×', multipliers(4)), sprintf('%d×', multipliers(5)), 'Baseline End', ...
       'Location', 'best', 'FontSize', 11);
grid on;
set(gca, 'FontSize', 11);
hold off;

% Figure 2: Threshold Map Visualization (recreate from baseline stats)
figure('Name', 'Threshold Maps by Multiplier', 'NumberTitle', 'off');

for idx = 1:num_multipliers
    mult = multipliers(idx);
    threshold_map = mean_baseline_map + (mult * std_baseline_map);
    
    subplot(1, num_multipliers, idx);
    imagesc(threshold_map);
    colorbar;
    axis image;
    title(sprintf('Threshold Map\n%d×StdDev', mult), 'FontSize', 10);
    set(gca, 'FontSize', 9);
end

% Figure 3: Baseline vs Post-Baseline Comparison
figure('Name', 'Baseline vs Post-Baseline Activity', 'NumberTitle', 'off', 'Position', [100, 100, 800, 600]);

% Extract values from cell array
baseline_means = [];
post_baseline_means = [];
for idx = 1:num_multipliers
    baseline_means = [baseline_means; summary_stats{idx}.baseline_mean_percent];
    post_baseline_means = [post_baseline_means; summary_stats{idx}.post_baseline_mean_percent];
end

subplot(2, 1, 1);
bar(multipliers, baseline_means, 'FaceColor', 'cyan', 'EdgeColor', 'k', 'LineWidth', 1.5);
ylabel('% Active Pixels', 'FontSize', 11);
title('Baseline Period (Frames 1-20) Activity', 'FontSize', 12, 'FontWeight', 'bold');
set(gca, 'FontSize', 10);
grid on; ylim([0, max(baseline_means) * 1.2]);

subplot(2, 1, 2);
bar(multipliers, post_baseline_means, 'FaceColor', 'magenta', 'EdgeColor', 'k', 'LineWidth', 1.5);
xlabel('Threshold Multiplier', 'FontSize', 11);
ylabel('% Active Pixels', 'FontSize', 11);
title('Post-Baseline Period (Frames 21-150) Activity', 'FontSize', 12, 'FontWeight', 'bold');
set(gca, 'FontSize', 10);
grid on; ylim([0, max(post_baseline_means) * 1.2]);

% Figure 4: Activation Distribution Histograms
figure('Name', 'Activation Distribution', 'NumberTitle', 'off');

for idx = 1:num_multipliers
    mult = multipliers(idx);
    h5_file = sprintf('data/activation_mask_%dx.h5', mult);
    percent_active = h5read(h5_file, '/percent_active_per_frame');
    
    subplot(1, num_multipliers, idx);
    histogram(percent_active, 20, 'EdgeColor', 'k', 'FaceColor', 'cyan', 'FaceAlpha', 0.7);
    xlabel('% Active Pixels', 'FontSize', 9);
    ylabel('Frames', 'FontSize', 9);
    title(sprintf('%d× Multiplier', mult), 'FontSize', 10);
    grid on;
    set(gca, 'FontSize', 8);
end

fprintf('  Generated 4 diagnostic figures\n');

%% 8. Save Summary Statistics to MAT File
fprintf('\nSaving summary statistics to MAT file...\n');

output_mat_file = 'data/threshold_sensitivity_analysis.mat';
save(output_mat_file, 'summary_stats', 'multipliers', 'H', 'W', 'T', ...
    'mean_baseline_map', 'std_baseline_map', 'binned_baseline_end');

fprintf('  Saved: %s\n', output_mat_file);

%% 9. Generate Summary Report
fprintf('\n========================================\n');
fprintf('SENSITIVITY ANALYSIS SUMMARY\n');
fprintf('========================================\n\n');

fprintf('Input Data:\n');
fprintf('  File: %s\n', input_h5_file);
fprintf('  Dimensions: [%d, %d, %d]\n', H, W, T);
fprintf('  Baseline period: Frames 1-%d\n', binned_baseline_end);
fprintf('  Total pixels: %d\n\n', total_pixels);

fprintf('Baseline Statistics:\n');
fprintf('  Mean range: [%.6f, %.6f]\n', min(mean_baseline_map(:)), max(mean_baseline_map(:)));
fprintf('  Std range: [%.6f, %.6f]\n', min(std_baseline_map(:)), max(std_baseline_map(:)));
fprintf('  Mean SNR: %.4f\n\n', mean(snr_map(snr_map > 0)));

fprintf('Sensitivity Analysis Results:\n');
fprintf('%-12s | %-15s | %-15s | %-15s | %-15s\n', 'Multiplier', 'Min Active %', 'Max Active %', 'Mean Active %', 'Post-Baseline %');
fprintf('%s\n', repmat('-', 1, 80));

for idx = 1:num_multipliers
    mult = summary_stats{idx}.multiplier;
    fprintf('%d×          | %14.2f%% | %14.2f%% | %14.2f%% | %14.2f%%\n', ...
        mult, ...
        summary_stats{idx}.min_percent, ...
        summary_stats{idx}.max_percent, ...
        summary_stats{idx}.mean_percent, ...
        summary_stats{idx}.post_baseline_mean_percent);
end

fprintf('\n========================================\n');
fprintf('RECOMMENDATIONS\n');
fprintf('========================================\n\n');

% Find which multiplier gives best separation
post_baseline_activity = [];
baseline_activity = [];
for idx = 1:num_multipliers
    post_baseline_activity = [post_baseline_activity; summary_stats{idx}.post_baseline_mean_percent];
    baseline_activity = [baseline_activity; summary_stats{idx}.baseline_mean_percent];
end
separation = post_baseline_activity - baseline_activity;

[~, best_idx] = max(separation);
best_multiplier = multipliers(best_idx);

fprintf('Best threshold multiplier (maximum post-baseline activation): %d×\n', best_multiplier);
fprintf('  Baseline activity: %.2f%%\n', baseline_activity(best_idx));
fprintf('  Post-baseline activity: %.2f%%\n', post_baseline_activity(best_idx));
fprintf('  Separation: %.2f%%\n\n', separation(best_idx));

fprintf('Files Created:\n');
for idx = 1:num_multipliers
    mult = multipliers(idx);
    fprintf('  - data/activation_mask_%dx.h5\n', mult);
end
fprintf('  - data/threshold_sensitivity_analysis.mat\n');
fprintf('  - 4 diagnostic figures\n');

fprintf('\n========================================\n');
fprintf('ANALYSIS COMPLETE\n');
fprintf('========================================\n\n');