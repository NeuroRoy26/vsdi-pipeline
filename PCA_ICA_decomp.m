clc; clear; close all;

%%
% input_file = 'data/averaged_movie_E0B0-B3_unbinned.h5';
input_file = 'data/preprocessing/led_E0B0_dff_unbinned.h5';

dataset_name = '/functional_dff';
original_sampling_rate = 500; % in Hz (original is ~500.67)
Fs = original_sampling_rate / 2;   % interleaved frames → half rate

mov = h5read(input_file, dataset_name);
[H, W, T] = size(mov);
fprintf('Loaded movie: %d x %d pixels, %d frames (%.2f s)\n', ...
    H, W, T, T/Fs);

% Flatten -> rows = time, columns = pixels
X = reshape(mov, H*W, T).';
X(isnan(X)) = 0;

%% ------------------------------------------------------------
% Spatial filtering
fprintf('Spatial smoothing...\n');

temp_mov = reshape(X.', H, W, T); 
for t = 1:T
    temp_mov(:,:,t) = imgaussfilt(temp_mov(:,:,t), 2); 
end

X = reshape(temp_mov, H*W, T).';
fprintf('Smoothing complete.\n');

%% ------------------------------------------------------------
% PCA
fprintf('\nRunning PCA...\n');
[pca_coeff_full, pca_score_full, ~, ~, explained_full] = pca(X, ...
    'Algorithm', 'svd', 'Economy', 'on');

Z = size(pca_score_full,2);
fprintf('PCA complete. Total PCs: %d\n', Z);

num_components = 7; 
fprintf('Keeping %d PCs (%.2f%% variance)\n', ...
    num_components, sum(explained_full(1:num_components)));

pca_tc   = pca_score_full(:, 1:num_components);
pca_maps = pca_coeff_full(:, 1:num_components);

%% ------------------------------------------------------------
% Global PSD (actual top-10 PCs)
fprintf('\nComputing Global PSD (top 10 PCs)...\n');

L = T;
f = Fs*(0:(L/2))/L;
P1_global = zeros(L/2+1, 1);

n_psd = min(Z, 10);   % top 10 PCs or fewer if Z < 10
for k = 1:n_psd
    Y = fft(pca_score_full(:,k));
    P2 = abs(Y/L);
    P1 = P2(1:L/2+1);
    P1(2:end-1) = 2*P1(2:end-1);
    P1_global = P1_global + P1;
end

figure('Name', 'Global Power Spectral Density', 'Color', 'w');
plot(f, P1_global, 'k', 'LineWidth', 1);
grid on; xlabel('Frequency (Hz)'); ylabel('Magnitude');
title('Power Spectral Density (Top 10 PCs)');

%% ------------------------------------------------------------
% ICA
fprintf('\nRunning FastICA (spatial domain)...\n');

[icasig, A, ~] = fastica(pca_maps', ...
    'verbose', 'on', ...
    'numOfIC', num_components, ...
    'approach', 'symm', ...
    'g', 'tanh');

ica_maps_flat = icasig.';         % [pixels x IC]
ica_timecourses = pca_tc * A;     % [T x IC]

num_ICs = size(ica_maps_flat, 2);
ica_maps = reshape(ica_maps_flat, H, W, num_ICs);

fprintf('ICA complete. Extracted %d components.\n', num_ICs);

%% ------------------------------------------------------------
% Metrics + sign correction (fixed bug)
fprintf('\nComputing metrics (with sign correction)...\n');

stats = struct();

for k = 1:num_ICs
    map_flat = ica_maps_flat(:,k);
    tc = ica_timecourses(:,k);

    % sign alignment based on spatial skewness
    if skewness(map_flat) < 0
        map_flat = -map_flat;
        tc = -tc;

        % update BOTH maps and timecourses everywhere
        ica_maps_flat(:,k) = map_flat;
        ica_timecourses(:,k) = tc;
        ica_maps(:,:,k) = -ica_maps(:,:,k);
    end

    % metrics
    sp_kurt = kurtosis(map_flat);
    tc_z = (tc - mean(tc)) / std(tc);
    max_z = max(abs(tc_z));

    % PSD
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
% Montage view
fprintf('\nGenerating Montage View...\n');

grid_cols = ceil(sqrt(num_ICs));
grid_rows = ceil(num_ICs / grid_cols);
stitched_im = zeros(grid_rows * H, grid_cols * W);

for k = 1:num_ICs
    [r_idx, c_idx] = ind2sub([grid_rows, grid_cols], k);

    this_map = ica_maps(:,:,k);
    clim = [prctile(this_map(:), 1) prctile(this_map(:), 99)];

    this_map = max(min(this_map, clim(2)), clim(1));
    this_map = (this_map - clim(1)) / (clim(2) - clim(1));

    r_start = (r_idx-1)*H + 1;
    c_start = (c_idx-1)*W + 1;
    stitched_im(r_start:r_start+H-1, c_start:c_start+W-1) = this_map;
end

figure('Name', 'Montage of All Components', 'Color', 'w');
imagesc(stitched_im); axis image off; colormap jet;
title(sprintf('Montage of %d ICA Components', num_ICs));
colorbar;

%% ------------------------------------------------------------
% % Interactive ICA inspector
% figure('Name', 'ICA Inspector', 'Color', 'w', 'Position', [200 200 1200 500]);
% fprintf('Go...!\n');
% 
% for k = 1:num_ICs
%     subplot(1, 3, 1);
%     m = ica_maps(:,:,k);
%     clim = [prctile(m(:), 1) prctile(m(:), 99)];
%     imagesc(m, clim); axis image off; colormap jet;
%     title(sprintf('Component #%d (Kurt: %.1f)', k, stats(k).kurt));
% 
%     subplot(1, 3, 2);
%     plot((1:T)/Fs, ica_timecourses(:,k), 'k', 'LineWidth', 1);
%     axis tight; grid on; xlabel('Time (s)');
%     title('Time Course');
% 
%     subplot(1, 3, 3);
%     plot(f, stats(k).P1, 'r', 'LineWidth', 1.5);
%     xlim([0 20]); grid on; xlabel('Frequency (Hz)');
%     title(sprintf('Dom Freq: %.1f Hz', stats(k).freq));
% 
%     waitforbuttonpress;
% end

%% ------------------------------------------------------------
% Batch figures
fprintf('\nGenerating Inspector Figures...\n');

comps_per_fig = 4;
num_figs = ceil(num_ICs / comps_per_fig);

for fig_idx = 1:num_figs
    figure('Name', sprintf('ICA Batch %d', fig_idx), 'Color', 'w', ...
        'Position', [50, 50, 1000, 800]);

    start_idx = (fig_idx-1)*comps_per_fig + 1;
    end_idx = min(start_idx + comps_per_fig - 1, num_ICs);

    plot_idx = 1;
    for k = start_idx:end_idx
        
        subplot(comps_per_fig, 3, (plot_idx-1)*3 + 1);
        m = ica_maps(:,:,k);
        clim = [prctile(m(:), 5) prctile(m(:), 99.5)];
        imagesc(m, clim); axis image off; colormap jet;
        title(sprintf('IC #%d (Kurt %.1f)', k, stats(k).kurt));

        subplot(comps_per_fig, 3, (plot_idx-1)*3 + 2);
        plot((1:T)/Fs, ica_timecourses(:,k), 'k'); axis tight; box off;
        title('Trace');

        subplot(comps_per_fig, 3, (plot_idx-1)*3 + 3);
        plot(f, stats(k).P1, 'r', 'LineWidth', 1.5);
        xlim([0 15]); box off;
        title(sprintf('Freq %.2f Hz', stats(k).freq));

        plot_idx = plot_idx + 1;
    end
end

fprintf('\n=== DONE ===\n');
fprintf('Check the generated figures for details.\n');
