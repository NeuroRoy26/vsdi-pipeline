clc; clear; close all;

%%
input_file = 'data/averaged_movie_E0B0-B3_unbinned.h5';
dataset_name = '/functional_dff';
original_sampling_rate = 500; %in Hz original is 500.67
Fs = original_sampling_rate/2;   %since interleaved frames
mov = h5read(input_file, dataset_name);
[H, W, T] = size(mov);
fprintf('Loaded movie: %d x %d pixels, %d frames (%.2f s)\n', H, W, T, T/Fs);

% Flatten -> rows = time, columns = pixels
X = reshape(mov, H*W, T).';   % [T x P]
X(isnan(X)) = 0;

%% spatial filtering
%it was already done in run_trial_averaging.m
%applying here again

fprintf('Spatial smoothing...\n');
% Reshape back to 3D for smoothing
temp_mov = reshape(X.', H, W, T); 

% Apply Gaussian filter with sigma = 2 pixels
% This blends adjacent pixels, reducing single-pixel noise
for t = 1:T
    temp_mov(:,:,t) = imgaussfilt(temp_mov(:,:,t), 2); 
end

% Flatten back to 2D for PCA
X = reshape(temp_mov, H*W, T).';
fprintf('Smoothing complete.\n');
%% ------------------------------------------------------------
%  2. PCA 
fprintf('\nRunning PCA...\n');
[pca_coeff_full, pca_score_full, ~, ~, explained_full] = pca(X, 'Algorithm', 'svd', 'Economy', 'on');
fprintf('PCA complete.\n');
Z = size(pca_score_full,2); % total number of PCs
fprintf('Total %d Principle components', Z);
num_components = 5; 
fprintf('Keeping %d components (%.2f%% variance)\n', ...
    num_components, sum(explained_full(1:num_components)));

pca_tc   = pca_score_full(:, 1:num_components);   % [T x K]; K is total PCs
pca_maps = pca_coeff_full(:, 1:num_components);   % [Pixels x K]

%% ------------------------------------------------------------
%  PSD to check dominant frequencies
fprintf('\nComputing Global PSD...\n');
L = T;
f = Fs*(0:(L/2))/L;
P1_global = zeros(L/2+1, 1);

% average the spectrum of the top 10 PCs weighted by their variance.
% gives a robust view of what frequencies dominate the data.
check_n_comps = max(num_components, Z);
for k = 1:check_n_comps
    Y = fft(pca_score_full(:,k));
    P2 = abs(Y/L);
    P1 = P2(1:L/2+1);
    P1(2:end-1) = 2*P1(2:end-1);
    % Add to global sum
    P1_global = P1_global + P1;
end

figure('Name', 'Global Power Spectral Density', 'Color', 'w');
plot(f, P1_global, 'k', 'LineWidth', 1);
grid on;
xlabel('Frequency (Hz)');
ylabel('Magnitude');
title('Power Spectral Density');

%% ------------------------------------------------------------
% %  Freddy the FREQUENCY HUNTER: Identify the Source of 0.3 and 0.6 Hz
% % ------------------------------------------------------------
% target_range = [0.2, 0.8]; % Looking for 0.33 Hz and 0.66 Hz
% fprintf('\nHunting for components between %.1f and %.1f Hz...\n', target_range(1), target_range(2));
% 
% figure('Name', 'Frequency Hunter', 'Color', 'w', 'Position', [100 100 1000 600]);
% 
% found_count = 0;
% 
% % Loop through the components we kept
% for k = 1:Z
%     % Get the time course
%     tc = pca_score_full(:, k);
%     tc = detrend(tc); % Remove linear drift
% 
%     % Calculate Peak Frequency for this specific component
%     Y = fft(tc);
%     P2 = abs(Y/L);
%     P1 = P2(1:L/2+1);
%     [max_val, idx] = max(P1(2:end)); % Skip DC
%     dom_freq = f(idx+1);
% 
%     % Check if this component matches your mystery frequency
%     if dom_freq >= target_range(1) && dom_freq <= target_range(2)
%         found_count = found_count + 1;
% 
%         % --- PLOT THE CULPRIT ---
%         clf;
% 
%         % 1. The Map (Where is it?)
%         subplot(2, 2, [1 3]); 
%         map = pca_coeff_full(:, k);
%         map = reshape(map, H, W);
% 
%         % Auto-contrast
%         clim = [prctile(map(:), 1) prctile(map(:), 99)];
%         imagesc(map, clim);
%         axis image off; colormap jet; colorbar;
%         title(sprintf('Component #%d (%.2f Hz)', k, dom_freq), 'FontSize', 14);
% 
%         % 2. The Trace (What does it look like?)
%         subplot(2, 2, 2);
%         plot((1:T)/Fs, tc, 'k', 'LineWidth', 1.5);
%         axis tight; grid on;
%         xlabel('Time (s)'); title('Time Course');
% 
%         % 3. The Spectrum (Proof)
%         subplot(2, 2, 4);
%         plot(f, P1, 'r', 'LineWidth', 1.5);
%         xlim([0 5]); grid on; % Zoom in on low freq
%         xlabel('Frequency (Hz)'); title('Spectrum');
% 
%         fprintf('Match found: Component #%d is oscillating at %.2f Hz.\n', k, dom_freq);
%         fprintf('Press SPACE to continue...\n');
%         waitforbuttonpress;
%     end
% end
% 
% if found_count == 0
%     fprintf('No specific components found peaking exactly in that range.\n');
%     fprintf('The signal might be distributed across many small components.\n');
% else
%     fprintf('Search complete.\n');
% end

%% ------------------------------------------------------------
%  3. ICA 
fprintf('\nRunning FastICA on spatial dimension...\n');
[icasig, A, ~] = fastica(pca_maps', ... 
    'verbose', 'on', ...
    'numOfIC', num_components, ...
    'approach', 'symm', ...
    'g', 'tanh'); 

% 1. Get Spatial Maps
ica_maps_flat = icasig.'; 
% 2. Get Time Courses
ica_timecourses = pca_tc * A; 

num_ICs = size(ica_maps_flat, 2);
ica_maps = reshape(ica_maps_flat, H, W, num_ICs);
fprintf('ICA complete. Extracted %d components.\n', num_ICs);

%% ------------------------------------------------------------
fprintf('\nComputing metrics...\n');
stats = struct();
for k = 1:num_ICs
    % Extract map and trace
    map_flat = ica_maps_flat(:,k);
    tc = ica_timecourses(:,k);
    
    % --- FLIP SIGN CHECK ---
    if skewness(map_flat) < 0
        map_flat = -map_flat;
        tc = -tc;
        ica_maps(:,:,k) = -ica_maps(:,:,k); 
    end
    
    sp_kurt = kurtosis(map_flat);
    tc_z = (tc - mean(tc)) / std(tc);
    max_z = max(abs(tc_z));
    
    Y = fft(tc);
    P2 = abs(Y/L);
    P1 = P2(1:L/2+1);
    P1(2:end-1) = 2*P1(2:end-1);
    
    [~, idx] = max(P1(2:end));
    dom_freq = f(idx+1);
    
    stats(k).freq = dom_freq;
    stats(k).kurt = sp_kurt;
    stats(k).maxz = max_z;
    stats(k).P1 = P1;
end
fprintf('Metrics complete.\n');

%% ------------------------------------------------------------
fprintf('\nGenerating Montage View...\n');
% Calculate grid dimensions (approx square)
grid_cols = ceil(sqrt(num_ICs));
grid_rows = ceil(num_ICs / grid_cols);

% Create a stitched image
stitched_im = zeros(grid_rows * H, grid_cols * W);

for k = 1:num_ICs
    % Get row/col index
    [r_idx, c_idx] = ind2sub([grid_rows, grid_cols], k);
    
    % Get map and normalize to 0-1 for display (so weak components are visible)
    this_map = ica_maps(:,:,k);
    clim = [prctile(this_map(:), 1) prctile(this_map(:), 99)];
    % Clip outliers
    this_map(this_map < clim(1)) = clim(1);
    this_map(this_map > clim(2)) = clim(2);
    % Normalize 0 to 1
    this_map = (this_map - clim(1)) / (clim(2) - clim(1));
    
    % Insert into grid
    r_start = (r_idx-1)*H + 1;
    c_start = (c_idx-1)*W + 1;
    stitched_im(r_start:r_start+H-1, c_start:c_start+W-1) = this_map;
end

figure('Name', 'Montage of All Components', 'Color', 'w');
imagesc(stitched_im);
colormap jet; 
axis image off;
title(sprintf('Montage of %d ICA Components', num_ICs));

%% ------------------------------------------------------------
figure('Name', 'ICA Inspector', 'Color', 'w', 'Position', [200 200 1200 500]);
fprintf('Go...!\n');

for k = 1:num_ICs
    subplot(1, 3, 1);
    m = ica_maps(:,:,k);
    clim = [prctile(m(:), 1) prctile(m(:), 99)]; 
    imagesc(m, clim); 
    axis image off; 
    colormap jet;
    title(sprintf('Component #%d\n(Kurt: %.1f)', k, stats(k).kurt), 'FontSize', 14);
    
    subplot(1, 3, 2);
    plot((1:T)/Fs, ica_timecourses(:,k), 'k', 'LineWidth', 1); 
    axis tight; grid on;
    xlabel('Time (s)'); 
    title('Time Course', 'FontSize', 12);
    
    subplot(1, 3, 3);
    plot(f, stats(k).P1, 'r', 'LineWidth', 1.5); 
    xlim([0 20]); 
    grid on;
    xlabel('Frequency (Hz)'); 
    title(sprintf('Dom Freq: %.1f Hz', stats(k).freq), 'FontSize', 12);
    
    w = waitforbuttonpress; 
end
%% ============================================================
fprintf('\nGenerating Inspector Figures...\n');
comps_per_fig = 4;
num_figs = ceil(num_ICs / comps_per_fig);

for fig_idx = 1:num_figs
    figure('Name', sprintf('ICA Batch %d', fig_idx), 'Color', 'w', 'Position', [50, 50, 1000, 800]);
    
    start_idx = (fig_idx-1)*comps_per_fig + 1;
    end_idx = min(start_idx + comps_per_fig - 1, num_ICs);
    
    plot_idx = 1;
    for k = start_idx:end_idx
        % Layout: 4 components, each gets 1 row (3 subplots per row)
        % Subplot indices: (TotalRows, TotalCols, Index)
        
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
