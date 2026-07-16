clc; clear; close all;
%% PCA Publication Figure Generator
% Lightweight script to generate publication-quality PCA scatter plots
% showing projections across different PC axes
%
% Compatible with dff data from preprocessing pipeline
% Outputs: 2D scatter plots of PC projections with variance explained

%% File Selection
[fName, fPath] = uigetfile('*.h5', 'Select H5 File');
if isequal(fName, 0)
    error('User canceled file selection.');
end
input_file = fullfile(fPath, fName);
fprintf('Selected: %s\n', input_file);

%% Dataset and Sampling Rate Configuration
dataset_name = '/functional_dff';  % Change to '/functional' if needed

fprintf('Select Sampling Rate:\n 1) 500 Hz\n 2) 1000 Hz\n 3) Custom\n');
choice = input('Enter your choice (1, 2, or 3): ');
switch choice
    case 1
        original_sampling_rate = 500;
    case 2
        original_sampling_rate = 1000;
    case 3
        original_sampling_rate = input('Enter custom sampling rate (Hz): ');
    otherwise
        error('Invalid selection.');
end
fprintf('Sampling rate set to: %.2f Hz\n', original_sampling_rate);

Fs = original_sampling_rate / 2;  % Interleaved frames → effective half rate

%% Load Data
fprintf('Loading data...\n');
mov = h5read(input_file, dataset_name);
[H, W, T] = size(mov);
fprintf('Loaded: %d x %d pixels, %d frames (%.2f s)\n', H, W, T, T/Fs);

% Reshape to [time x pixels] matrix
X = reshape(mov, H*W, T).';
X(isnan(X)) = 0;  % Replace NaNs with zeros

%% Spatial Smoothing
fprintf('Applying spatial smoothing...\n');
temp_mov = reshape(X.', H, W, T);
for t = 1:T
    temp_mov(:,:,t) = imgaussfilt(temp_mov(:,:,t), 2);
end
X = reshape(temp_mov, H*W, T).';
fprintf('Smoothing complete.\n');

%% Run PCA
fprintf('Running PCA...\n');
[pca_coeff, pca_score, ~, ~, explained] = pca(X, ...
    'Algorithm', 'svd', 'Economy', 'on');

num_PCs = size(pca_score, 2);
fprintf('PCA complete. Total PCs: %d\n', num_PCs);

% Calculate cumulative variance explained
cumulative_var = cumsum(explained);
fprintf('Top 10 PCs explain %.2f%% of variance\n', cumulative_var(10));

%% Generate Publication Figure
% Create figure with multiple PC projection pairs
figure('Name', 'PCA Projections', 'Color', 'w', 'Position', [100, 100, 1200, 400]);

% Time vector for color coding (optional)
time_vec = (1:T)' / Fs;  % Time in seconds

% Define which PC pairs to plot (you can modify these)
pc_pairs = [1 2; 2 3; 1 3];  % [PC1 vs PC2, PC2 vs PC3, PC1 vs PC3]
num_plots = size(pc_pairs, 1);

for i = 1:num_plots
    subplot(1, num_plots, i);
    
    % Extract PC pair indices
    pc_x = pc_pairs(i, 1);
    pc_y = pc_pairs(i, 2);
    
    % Create scatter plot colored by time
    scatter(pca_score(:, pc_x), pca_score(:, pc_y), 20, time_vec, 'filled', ...
        'MarkerFaceAlpha', 0.6);
    
    % Formatting
    xlabel(sprintf('PC%d (%.1f%%)', pc_x, explained(pc_x)), 'FontSize', 12);
    ylabel(sprintf('PC%d (%.1f%%)', pc_y, explained(pc_y)), 'FontSize', 12);
    title(sprintf('PC%d vs PC%d', pc_x, pc_y), 'FontSize', 13, 'FontWeight', 'bold');
    
    % Add colorbar only to the last subplot
    if i == num_plots
        c = colorbar;
        c.Label.String = 'Time (s)';
        c.Label.FontSize = 11;
    end
    
    axis square;  % Square axes for better comparison
    grid on;
    box on;
end

% Add overall title
sgtitle('Principal Component Analysis', 'FontSize', 15, 'FontWeight', 'bold');

%% Scree Plot (Variance Explained)
figure('Name', 'Variance Explained', 'Color', 'w', 'Position', [100, 600, 800, 400]);

subplot(1, 2, 1);
% Bar plot of variance explained by each PC
num_show = min(50, num_PCs);  % Show first 50 PCs
bar(1:num_show, explained(1:num_show), 'FaceColor', [0.3 0.5 0.8]);
xlabel('Principal Component', 'FontSize', 12);
ylabel('Variance Explained (%)', 'FontSize', 12);
title('Scree Plot', 'FontSize', 13, 'FontWeight', 'bold');
grid on;
box on;

subplot(1, 2, 2);
% Cumulative variance explained
plot(1:num_show, cumulative_var(1:num_show), 'o-', 'LineWidth', 2, ...
    'MarkerSize', 6, 'Color', [0.8 0.3 0.3]);
xlabel('Number of Components', 'FontSize', 12);
ylabel('Cumulative Variance Explained (%)', 'FontSize', 12);
title('Cumulative Variance', 'FontSize', 13, 'FontWeight', 'bold');
grid on;
box on;
ylim([0 100]);

% Add 95% variance line
hold on;
yline(95, '--k', '95%', 'LineWidth', 1.5, 'FontSize', 10);
hold off;

%% Summary Statistics
fprintf('\n=== PCA Summary ===\n');
fprintf('Total variance explained by top 10 PCs: %.2f%%\n', cumulative_var(10));
fprintf('Number of PCs for 95%% variance: %d\n', find(cumulative_var >= 95, 1));
fprintf('Number of PCs for 99%% variance: %d\n', find(cumulative_var >= 99, 1));

fprintf('\n=== DONE ===\n');
fprintf('Figures generated successfully.\n');