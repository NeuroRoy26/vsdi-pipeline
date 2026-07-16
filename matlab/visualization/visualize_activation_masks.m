clc; clear; close all;
% -----------------------------------------------------------------
%         visualize_activation_masks.m
% -----------------------------------------------------------------
% Purpose:
%   1. Load activation masks from HDF5 files
%   2. Create better diagnostic figures with frame-by-frame dynamics
%   3. Provide interactive visualization for mask inspection
%   4. Compare 3x and 4x multipliers
%
% Input:   activation_mask_3x.h5, activation_mask_4x.h5, 
%          averaged_movie_E0B0-E0B3.h5
% Output:  Enhanced diagnostic figures + mask inspection tools
% -----------------------------------------------------------------

clear all; close all; clc;

%% 0. Setup
fprintf('========================================\n');
fprintf('ACTIVATION MASK VISUALIZATION & INSPECTION\n');
fprintf('========================================\n\n');

% Load activation masks and data
multipliers_to_analyze = [3, 4];
data_dir = 'data/';
binned_baseline_end = 20;  % From previous analysis

% Storage for data
masks = struct();
dff_movie = [];
frame_stats = struct();

%% 1. Load averaged dF/F movie (for reference)
fprintf('Loading averaged dF/F movie...\n');
try
    dff_movie = h5read([data_dir 'preprocessing/averaged_movie_E0B0-B3.h5'], '/functional_dff');
    [H, W, T] = size(dff_movie);
    fprintf('  ✓ Dimensions: [%d, %d, %d]\n\n', H, W, T);
catch ME
    error('Failed to load dF/F movie: %s', ME.message);
end

%% 2. Load activation masks for both multipliers
fprintf('Loading activation masks...\n');
for idx = 1:length(multipliers_to_analyze)
    mult = multipliers_to_analyze(idx);
    h5_file = sprintf('%sactivation_mask_%dx.h5', data_dir, mult);
    
    fprintf('  Loading %dx multiplier from %s\n', mult, h5_file);
    
    try
        % Load mask
        mask = h5read(h5_file, '/activation_mask');
        mask = logical(mask);  % Convert to logical
        
        % Load per-frame statistics and force to column vectors
        active_pixels_per_frame = h5read(h5_file, '/activated_pixels_per_frame');
        active_pixels_per_frame = active_pixels_per_frame(:);  % Force to column vector
        
        percent_active_per_frame = h5read(h5_file, '/percent_active_per_frame');
        percent_active_per_frame = percent_active_per_frame(:);  % Force to column vector
        
        % Store in struct
        masks(idx).multiplier = mult;
        masks(idx).mask = mask;
        masks(idx).active_pixels = active_pixels_per_frame;
        masks(idx).percent_active = percent_active_per_frame;
        
        % Calculate frame statistics
        baseline_mean = mean(percent_active_per_frame(1:binned_baseline_end));
        post_baseline_mean = mean(percent_active_per_frame(binned_baseline_end+1:end));
        
        masks(idx).baseline_mean = baseline_mean;
        masks(idx).post_baseline_mean = post_baseline_mean;
        masks(idx).separation = post_baseline_mean - baseline_mean;
        
        fprintf('    ✓ Baseline: %.2f%% | Post-baseline: %.2f%% | Separation: %.2f%%\n\n', ...
            baseline_mean, post_baseline_mean, masks(idx).separation);
        
    catch ME
        error('Failed to load multiplier %d: %s', mult, ME.message);
    end
end

%% 3. FIGURE 1: Frame-by-Frame Activation Dynamics (SEPARATE PLOTS)
fprintf('Creating Figure 1: Frame-by-Frame Dynamics (Separate Plots)...\n');
figure('Name', 'Frame-by-Frame Activation Dynamics', 'NumberTitle', 'off', 'Position', [100, 100, 1400, 800]);

for idx = 1:length(multipliers_to_analyze)
    mult = masks(idx).multiplier;
    percent_active = masks(idx).percent_active;
    
    subplot(2, 2, idx);
    
    % Plot time series
    plot(1:T, percent_active, 'LineWidth', 2.5, 'Color', [0.2 0.4 0.8]);
    hold on;
    
    % Highlight baseline period
    y_max = max(percent_active(:)) * 1.1;  % Force scalar with (:)
    fill([1, binned_baseline_end, binned_baseline_end, 1], ...
         [0, 0, y_max, y_max], ...
         [0.8 0.9 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.3);
    
    % Add vertical line at baseline end
    plot([binned_baseline_end+0.5, binned_baseline_end+0.5], ...
         [0, y_max], 'k--', 'LineWidth', 2, 'DisplayName', 'Baseline End');
    
    % Formatting
    xlabel('Frame', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('% Active Pixels', 'FontSize', 12, 'FontWeight', 'bold');
    title(sprintf('%d× Multiplier: Frame-by-Frame Activation', mult), 'FontSize', 13, 'FontWeight', 'bold');
    grid on;
    set(gca, 'FontSize', 11);
    xlim([1, T]);
    ylim([0, max(percent_active(:))*1.15]);
    hold off;
    
    % Add statistics box
    stats_text = sprintf('Baseline: %.2f%%\nPost-baseline: %.2f%%\nSeparation: %.2f%%', ...
        masks(idx).baseline_mean, masks(idx).post_baseline_mean, masks(idx).separation);
    annotation('textbox', [0.15 + (idx-1)*0.4, 0.55, 0.15, 0.12], ...
        'String', stats_text, 'BackgroundColor', 'white', 'EdgeColor', 'black', ...
        'FontSize', 10, 'FontWeight', 'bold');
end

% Figure 1, Right side: Comparison
subplot(2, 2, 3:4);
colors = {'r', 'b'};
for idx = 1:length(multipliers_to_analyze)
    mult = masks(idx).multiplier;
    percent_active = masks(idx).percent_active;
    plot(1:T, percent_active, 'LineWidth', 2.5, 'Color', colors{idx}, 'DisplayName', sprintf('%d×', mult));
    hold on;
end

% Calculate y_max from all masks
all_percent_active = vertcat(masks(:).percent_active);
y_max_all = max(all_percent_active(:)) * 1.1;
fill([1, binned_baseline_end, binned_baseline_end, 1], ...
     [0, 0, y_max_all, y_max_all], ...
     [0.8 0.9 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.2);
plot([binned_baseline_end+0.5, binned_baseline_end+0.5], ...
     [0, y_max_all], 'k--', 'LineWidth', 2);

xlabel('Frame', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('% Active Pixels', 'FontSize', 12, 'FontWeight', 'bold');
title('3× vs 4× Multiplier Comparison', 'FontSize', 13, 'FontWeight', 'bold');
legend('Location', 'best', 'FontSize', 11);
grid on;
set(gca, 'FontSize', 11);
xlim([1, T]);
hold off;

%% 4. FIGURE 2: Baseline vs Post-Baseline Comparison (BAR CHART)
fprintf('Creating Figure 2: Baseline vs Post-Baseline Summary...\n');
figure('Name', 'Baseline vs Post-Baseline Comparison', 'NumberTitle', 'off', 'Position', [100, 100, 1000, 700]);

% Extract values
baseline_values = [masks(:).baseline_mean];
post_baseline_values = [masks(:).post_baseline_mean];
separation_values = [masks(:).separation];
mult_labels = {sprintf('%d×', masks(1).multiplier), sprintf('%d×', masks(2).multiplier)};

% Subplot 1: Stacked comparison
subplot(2, 2, 1);
x = 1:length(multipliers_to_analyze);
b1 = bar(x, baseline_values, 'FaceColor', 'cyan', 'EdgeColor', 'k', 'LineWidth', 2);
hold on;
b2 = bar(x, post_baseline_values, 'FaceColor', 'magenta', 'EdgeColor', 'k', 'LineWidth', 2);
hold off;
ylabel('% Active Pixels', 'FontSize', 11, 'FontWeight', 'bold');
title('Baseline vs Post-Baseline Activity', 'FontSize', 12, 'FontWeight', 'bold');
set(gca, 'XTickLabel', mult_labels, 'FontSize', 10);
legend('Baseline (1-20)', 'Post-Baseline (21-150)', 'FontSize', 10);
grid on;
set(gca, 'FontSize', 10);

% Subplot 2: Separation (signal-to-noise metric)
subplot(2, 2, 2);
b = bar(x, separation_values, 'FaceColor', 'green', 'EdgeColor', 'k', 'LineWidth', 2);
ylabel('Separation (%)', 'FontSize', 11, 'FontWeight', 'bold');
title('Baseline-to-Post-Baseline Separation', 'FontSize', 12, 'FontWeight', 'bold');
set(gca, 'XTickLabel', mult_labels, 'FontSize', 10);
grid on;
set(gca, 'FontSize', 10);
ylim([0, max(separation_values)*1.2]);

% Add value labels on bars
for i = 1:length(separation_values)
    text(i, separation_values(i)+0.1, sprintf('%.2f%%', separation_values(i)), ...
        'HorizontalAlignment', 'center', 'FontSize', 10, 'FontWeight', 'bold');
end

% Subplot 3: Peak activation per frame
subplot(2, 2, 3);
for idx = 1:length(multipliers_to_analyze)
    mult = masks(idx).multiplier;
    active_pixels = masks(idx).active_pixels;
    max_active = max(active_pixels(:));
    mean_active = mean(active_pixels(:));
    
    bar_data = [max_active, mean_active];
    b = bar((idx-1)*2.5 + [1, 2], bar_data, 0.8, 'FaceColor', colors{idx}, 'EdgeColor', 'k', 'LineWidth', 1.5);
    hold on;
    
    text((idx-1)*2.5 + 1, max_active + 1000, sprintf('%d', max_active), ...
        'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold');
    text((idx-1)*2.5 + 2, mean_active + 1000, sprintf('%d', round(mean_active)), ...
        'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold');
end
ylabel('Number of Active Pixels', 'FontSize', 11, 'FontWeight', 'bold');
title('Peak vs Mean Active Pixels', 'FontSize', 12, 'FontWeight', 'bold');
set(gca, 'XTickLabel', {'3× Max', '3× Mean', '4× Max', '4× Mean'}, 'FontSize', 9);
grid on;
set(gca, 'FontSize', 10);
hold off;

% Subplot 4: Summary statistics table
subplot(2, 2, 4);
axis off;

table_data = [];
for idx = 1:length(multipliers_to_analyze)
    mult = masks(idx).multiplier;
    table_data = [table_data; mult, masks(idx).baseline_mean, masks(idx).post_baseline_mean, ...
                  masks(idx).separation, max(masks(idx).active_pixels(:)), round(mean(masks(idx).active_pixels(:)))];
end

t = uitable('Data', table_data, ...
    'ColumnName', {'Mult', 'Baseline%', 'Post-Base%', 'Separation%', 'Max Pixels', 'Mean Pixels'}, ...
    'ColumnWidth', {50, 70, 80, 90, 80, 80}, ...
    'Position', [0.1, 0.05, 0.8, 0.25]);
t.FontSize = 11;

fprintf('  ✓ Figure 2 complete\n\n');

%% 5. FIGURE 3: Spatial Activation Maps (Sample Frames)
fprintf('Creating Figure 3: Spatial Activation Maps...\n');
figure('Name', 'Spatial Activation Maps - Sample Frames', 'NumberTitle', 'off', 'Position', [100, 100, 1600, 900]);

sample_frames = [10, 50, 100, 140];  % Early baseline, mid, late, recent

for mult_idx = 1:length(multipliers_to_analyze)
    mult = masks(mult_idx).multiplier;
    mask = masks(mult_idx).mask;
    
    for frame_idx = 1:length(sample_frames)
        frame_num = sample_frames(frame_idx);
        
        % Plot activation mask
        subplot(length(multipliers_to_analyze), length(sample_frames), (mult_idx-1)*length(sample_frames) + frame_idx);
        
        activation_frame = mask(:, :, frame_num);
        imagesc(activation_frame);
        colormap(gca, 'gray');
        axis image;
        
        % Count active pixels
        n_active = sum(sum(activation_frame));
        
        title(sprintf('%d×: Frame %d\n(%d pixels active)', mult, frame_num, n_active), ...
            'FontSize', 10, 'FontWeight', 'bold');
        set(gca, 'FontSize', 9);
        
        % Add colorbar
        cbar = colorbar;
        cbar.Label.String = 'Active';
        cbar.Ticks = [0, 1];
        cbar.TickLabels = {'No', 'Yes'};
    end
end

fprintf('  ✓ Figure 3 complete\n\n');

%% 6. FIGURE 4: dF/F vs Activation Overlay (Side-by-side comparison)
fprintf('Creating Figure 4: dF/F vs Activation Overlay...\n');
figure('Name', 'dF/F vs Activation Masks', 'NumberTitle', 'off', 'Position', [100, 100, 1600, 900]);

sample_frames_detailed = [25, 75, 125];  % One from each period

for frame_idx = 1:length(sample_frames_detailed)
    frame_num = sample_frames_detailed(frame_idx);
    
    % dF/F frame
    subplot(3, 4, (frame_idx-1)*4 + 1);
    dff_frame = dff_movie(:, :, frame_num);
    imagesc(dff_frame);
    colormap(gca, 'jet');
    axis image;
    colorbar;
    title(sprintf('dF/F - Frame %d', frame_num), 'FontSize', 10, 'FontWeight', 'bold');
    set(gca, 'FontSize', 9);
    
    % 3x activation
    subplot(3, 4, (frame_idx-1)*4 + 2);
    mask_3x = masks(1).mask(:, :, frame_num);
    imagesc(mask_3x);
    colormap(gca, 'gray');
    axis image;
    n_active = sum(sum(mask_3x));
    title(sprintf('3× Mask - Frame %d\n(%d active)', frame_num, n_active), 'FontSize', 10, 'FontWeight', 'bold');
    set(gca, 'FontSize', 9);
    
    % 4x activation
    subplot(3, 4, (frame_idx-1)*4 + 3);
    mask_4x = masks(2).mask(:, :, frame_num);
    imagesc(mask_4x);
    colormap(gca, 'gray');
    axis image;
    n_active = sum(sum(mask_4x));
    title(sprintf('4× Mask - Frame %d\n(%d active)', frame_num, n_active), 'FontSize', 10, 'FontWeight', 'bold');
    set(gca, 'FontSize', 9);
    
    % Difference (3x - 4x)
    subplot(3, 4, (frame_idx-1)*4 + 4);
    diff_mask = mask_3x & ~mask_4x;  % Pixels in 3x but not in 4x
    imagesc(diff_mask);
    colormap(gca, 'gray');
    axis image;
    n_diff = sum(sum(diff_mask));
    title(sprintf('Difference (3× only)\nFrame %d\n(%d pixels)', frame_num, n_diff), ...
        'FontSize', 10, 'FontWeight', 'bold');
    set(gca, 'FontSize', 9);
end

fprintf('  ✓ Figure 4 complete\n\n');

%% 7. FIGURE 5: Interactive Frame Inspector (Quick reference)
fprintf('Creating Figure 5: Summary Statistics...\n');
figure('Name', 'Summary Statistics', 'NumberTitle', 'off', 'Position', [100, 100, 1200, 600]);

% Subplot 1: Activation histogram by frame
subplot(1, 3, 1);
for idx = 1:length(multipliers_to_analyze)
    mult = masks(idx).multiplier;
    percent_active = masks(idx).percent_active;
    histogram(percent_active, 20, 'DisplayName', sprintf('%d×', mult), 'EdgeColor', 'k', 'FaceAlpha', 0.7);
    hold on;
end
xlabel('% Active Pixels', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('Number of Frames', 'FontSize', 11, 'FontWeight', 'bold');
title('Distribution of Activation Across Frames', 'FontSize', 12, 'FontWeight', 'bold');
legend('FontSize', 10);
grid on;
set(gca, 'FontSize', 10);

% Subplot 2: Cumulative active pixels
subplot(1, 3, 2);
for idx = 1:length(multipliers_to_analyze)
    mult = masks(idx).multiplier;
    mask = masks(idx).mask;
    cumulative_active = squeeze(sum(sum(mask, 1), 2));
    plot(1:T, cumulative_active, 'LineWidth', 2.5, 'DisplayName', sprintf('%d×', mult));
    hold on;
end
xlabel('Frame', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('Cumulative Active Pixels', 'FontSize', 11, 'FontWeight', 'bold');
title('Cumulative Activation Over Time', 'FontSize', 12, 'FontWeight', 'bold');
legend('FontSize', 10);
grid on;
set(gca, 'FontSize', 10);
hold off;

% Subplot 3: Statistical comparison
subplot(1, 3, 3);
axis off;

stats_text = sprintf(['ACTIVATION MASK ANALYSIS SUMMARY\n\n', ...
    '3× MULTIPLIER:\n', ...
    '  Baseline activity: %.2f%%\n', ...
    '  Post-baseline activity: %.2f%%\n', ...
    '  Separation: %.2f%%\n', ...
    '  Max pixels per frame: %d\n', ...
    '  Mean pixels per frame: %d\n\n', ...
    '4× MULTIPLIER:\n', ...
    '  Baseline activity: %.2f%%\n', ...
    '  Post-baseline activity: %.2f%%\n', ...
    '  Separation: %.2f%%\n', ...
    '  Max pixels per frame: %d\n', ...
    '  Mean pixels per frame: %d\n\n', ...
    'RECOMMENDATION:\n', ...
    '  Use 3× for more detailed analysis\n', ...
    '  Use 4× for conservative approach'], ...
    masks(1).baseline_mean, masks(1).post_baseline_mean, masks(1).separation, ...
    max(masks(1).active_pixels(:)), round(mean(masks(1).active_pixels(:))), ...
    masks(2).baseline_mean, masks(2).post_baseline_mean, masks(2).separation, ...
    max(masks(2).active_pixels(:)), round(mean(masks(2).active_pixels(:))));

text(0.1, 0.95, stats_text, 'VerticalAlignment', 'top', 'FontSize', 11, ...
    'FontName', 'monospaced', 'BackgroundColor', 'white', 'EdgeColor', 'black');

fprintf('  ✓ Figure 5 complete\n\n');

%% 8. Print Summary
fprintf('========================================\n');
fprintf('VISUALIZATION & INSPECTION COMPLETE\n');
fprintf('========================================\n\n');

fprintf('Summary Statistics:\n');
fprintf('%-15s | %-15s | %-15s | %-15s\n', 'Multiplier', 'Baseline%', 'Post-Base%', 'Separation%');
fprintf('%s\n', repmat('-', 1, 65));
for idx = 1:length(multipliers_to_analyze)
    mult = masks(idx).multiplier;
    fprintf('%d×          | %14.2f%% | %14.2f%% | %14.2f%%\n', ...
        mult, masks(idx).baseline_mean, masks(idx).post_baseline_mean, masks(idx).separation);
end

fprintf('\nFiles Used:\n');
for idx = 1:length(multipliers_to_analyze)
    mult = multipliers_to_analyze(idx);
    fprintf('  - data/activation_mask_%dx.h5\n', mult);
end
fprintf('  - data/averaged_movie_E0B0-E0B3.h5\n');

fprintf('\nFigures Created:\n');
fprintf('  1. Frame-by-Frame Activation Dynamics (separate & comparison)\n');
fprintf('  2. Baseline vs Post-Baseline Summary (bar charts & statistics)\n');
fprintf('  3. Spatial Activation Maps (sample frames)\n');
fprintf('  4. dF/F vs Activation Masks (side-by-side comparison)\n');
fprintf('  5. Summary Statistics & Distributions\n');

fprintf('\n========================================\n\n');