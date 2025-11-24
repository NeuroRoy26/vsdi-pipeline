% works similar to PCA_ICA_decompose.m
clc; clear; close all;

%% ============================================================
%  1. LOAD DATA
% ============================================================
input_file = 'data/averaged_movie_E0B0-B3_unbinned.h5';
dataset_name = '/functional_dff';
original_sampling_rate = 500; 
Fs = original_sampling_rate/2;   

mov = h5read(input_file, dataset_name);
[H, W, T] = size(mov);
fprintf('Loaded movie: %d x %d pixels, %d frames (%.2f s)\n', H, W, T, T/Fs);

X = reshape(mov, H*W, T).';
X(isnan(X)) = 0;
X = double(X); 

%% ============================================================
%  2. DE-STRIPING (Median Filter)
% ============================================================
fprintf('\n--- REMOVING STRIPES ---\n');
temp_mov = reshape(X.', H, W, T);

% Calculate Global Median first (faster baseline)
global_med = median(temp_mov, 3);

for t = 1:T
    frame = temp_mov(:,:,t);
    % Subtract column median to kill stripes
    col_profile = median(frame, 1);
    frame = frame - col_profile;
    temp_mov(:,:,t) = frame;
end
fprintf('Stripes removed.\n');

%% ============================================================
%  3. SMOOTHING (No Binning/Resizing)
%  We kept the smoothing but removed the "Zoom/Crop" effect.
% ============================================================
fprintf('\n--- SMOOTHING (Full Resolution) ---\n');

% Set new dimensions equal to original dimensions (No resizing)
H_new = H;
W_new = W;
mov_smoothed = zeros(H_new, W_new, T);

fprintf('Smoothing data at full resolution...\n');

for t = 1:T
    frame = temp_mov(:,:,t);
    
    % STRONG Smoothing (Sigma = 3.0)
    % We keep this to melt the "static" noise, but we do NOT resize the image.
    frame = imgaussfilt(frame, 3.0);
    
    mov_smoothed(:,:,t) = frame;
end

% Flatten
X_clean = reshape(mov_smoothed, H_new*W_new, T).';
fprintf('Data processed.\n');

%% ============================================================
%  4. PCA
% ============================================================
fprintf('\nRunning PCA...\n');
[pca_coeff, pca_score, ~, ~, explained] = pca(X_clean, 'Algorithm', 'svd', 'Economy', 'on');

% Reduced to 5 components (Based on your successful test)
num_components = 4; 
fprintf('Keeping top %d components (%.2f%% variance)\n', ...
    num_components, sum(explained(1:num_components)));

%% ============================================================
%  5. ICA
% ============================================================
fprintf('\nRunning FastICA...\n');

pca_tc_clean   = pca_score(:, 1:num_components);
pca_maps_clean = pca_coeff(:, 1:num_components);

[icasig, A, ~] = fastica(pca_maps_clean', ... 
    'verbose', 'on', ...
    'numOfIC', num_components, ...
    'approach', 'symm', ...
    'g', 'pow3'); 

ica_maps_flat = icasig.'; 
ica_timecourses = pca_tc_clean * A; 
num_ICs = size(ica_maps_flat, 2);
ica_maps = reshape(ica_maps_flat, H_new, W_new, num_ICs);

%% ============================================================
%  6. COMPUTE METRICS & STATS
% ============================================================
L = T;
f = Fs*(0:(L/2))/L;
stats = struct();

for k = 1:num_ICs
    map_flat = ica_maps_flat(:,k);
    tc = ica_timecourses(:,k);
    
    % Force positive skew (red blobs)
    if skewness(map_flat) < 0
        map_flat = -map_flat;
        tc = -tc;
        ica_maps(:,:,k) = -ica_maps(:,:,k);
        ica_timecourses(:,k) = tc;
    end
    
    stats(k).kurt = kurtosis(map_flat);
    
    % Spectrum
    Y = fft(tc);
    P2 = abs(Y/L);
    P1 = P2(1:L/2+1);
    P1(2:end-1) = 2*P1(2:end-1);
    stats(k).P1 = P1;
    [~, idx] = max(P1(2:end));
    stats(k).freq = f(idx+1);
end

%% ============================================================
%  7. ICA INSPECTOR (BATCH VIEW)
% ============================================================
fprintf('\nGenerating Inspector Figures...\n');
comps_per_fig = 4;
num_figs = ceil(num_ICs / comps_per_fig);

for fig_idx = 1:num_figs
    figure('Name', sprintf('ICA Batch %d', fig_idx), 'Color', 'w', 'Position', [50, 50, 1000, 800]);
    
    start_idx = (fig_idx-1)*comps_per_fig + 1;
    end_idx = min(start_idx + comps_per_fig - 1, num_ICs);
    
    plot_idx = 1;
    for k = start_idx:end_idx
        
        % 1. MAP
        subplot(comps_per_fig, 3, (plot_idx-1)*3 + 1);
        m = ica_maps(:,:,k);
        clim = [prctile(m(:), 5) prctile(m(:), 99.5)]; 
        imagesc(m, clim); axis image off; colormap jet;
        title(sprintf('IC #%d (Kurt: %.1f)', k, stats(k).kurt));
        
        % 2. TIME COURSE
        subplot(comps_per_fig, 3, (plot_idx-1)*3 + 2);
        plot((1:T)/Fs, ica_timecourses(:,k), 'k'); axis tight; box off;
        title('Trace');
        
        % 3. PSD
        subplot(comps_per_fig, 3, (plot_idx-1)*3 + 3);
        plot(f, stats(k).P1, 'r', 'LineWidth', 1.5); xlim([0 15]); box off;
        title(sprintf('Freq: %.2f Hz', stats(k).freq));
        
        plot_idx = plot_idx + 1;
    end
end

fprintf('\n=== DONE ===\n');
fprintf('Check the generated figures for details.\n');

%% ============================================================
%  8. MONTAGE VIEW
% ============================================================
fprintf('\nGenerating Final Montage...\n');
grid_cols = ceil(sqrt(num_ICs));
grid_rows = ceil(num_ICs / grid_cols);

stitched_im = zeros(grid_rows * H_new, grid_cols * W_new);

for k = 1:num_ICs
    [r_idx, c_idx] = ind2sub([grid_rows, grid_cols], k);
    
    this_map = ica_maps(:,:,k);
    clim = [prctile(this_map(:), 5) prctile(this_map(:), 99.5)];
    this_map(this_map < clim(1)) = clim(1);
    this_map(this_map > clim(2)) = clim(2);
    
    if clim(2) > clim(1)
        this_map = (this_map - clim(1)) / (clim(2) - clim(1));
    else
        this_map = zeros(size(this_map));
    end
    
    r_start = (r_idx-1)*H_new + 1;
    c_start = (c_idx-1)*W_new + 1;
    stitched_im(r_start:r_start+H_new-1, c_start:c_start+W_new-1) = this_map;
end

figure('Name', 'Final ICA Montage', 'Color', 'w');
imagesc(stitched_im);
colormap jet; 
axis image off;
title(sprintf('Montage of %d Components (Full Res & Destriped)', num_ICs));
fprintf('Montage generated.\n');