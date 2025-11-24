clc; clear; close all;

%%
input_file = 'data/averaged_movie_E0B0-B3_unbinned.h5';
dataset_name = '/functional_dff';
Fs = 500;

fprintf('------------------------------------------------------------\n');
fprintf('SECTION 1: LOADING DATA & PCA\n');
fprintf('------------------------------------------------------------\n');

try
    mov = h5read(input_file, dataset_name);
catch
    error('File not found! Check the filename in input_file.');
end

[H, W, T] = size(mov);
fprintf('  Dimensions: %d x %d pixels, %d frames (%.2f s)\n', H, W, T, T/Fs);

% Reshape for PCA (time as rows, pixels as columns)
X = reshape(mov, H*W, T).';

if any(isnan(X), 'all')
    fprintf('  Warning: NaNs found. Replacing with zeros.\n');
    X(isnan(X)) = 0;
end

fprintf('  Running full PCA decomposition...\n');

[pca_coeff_full, pca_score_full, ~, ~, explained_full] = pca(X);

fprintf('  Full PCA complete.\n');

% Inspect PCA structure
total_components = length(explained_full);
fprintf('  Total PCA components available: %d\n', total_components);

figure(1);
plot(cumsum(explained_full), 'LineWidth', 2);
xlabel('Number of components');
ylabel('Cumulative variance (%)');
title('PCA cumulative variance');
grid on;

%% Select top components
num_components = 462;
fprintf('  Extracting first %d PCA components for analysis...\n', num_components);

pca_coeff = pca_coeff_full(:, 1:num_components);   % spatial components
pca_score = pca_score_full(:, 1:num_components);   % temporal components
explained = explained_full(1:num_components);

fprintf('  First %d components explain %.2f%% variance.\n', ...
        num_components, sum(explained_full(1:num_components)));

fprintf('  Ready for ICA or downstream analysis.\n');

%% ========================================================================
%  SECTION 2: INDEPENDENT COMPONENT ANALYSIS (ICA)
% =========================================================================
fprintf('------------------------------------------------------------\n');
fprintf('SECTION 2: RUNNING ICA (Spatial)\n');
fprintf('------------------------------------------------------------\n');

if ~exist('pca_score', 'var')
    error('PCA data not found. Please run Section 1 first.');
end

% --- Run Reconstruction ICA (RICA) ---
% We run ICA on pca_score (Spatial) to find independent spatial sources
Mdl = rica(pca_coeff, num_components);

% --- Recover Spatial and Temporal Parts ---
% NOTE: fixed the logic here. 
% transform(Mdl, pca_score) returns the sources found in the input. 
% Since input was [Pixels x PCs], the output is [Pixels x ICs].
ica_maps_flat = transform(Mdl, pca_coeff); 

% Project weights to get Time Courses
% [Time x PCs] * [PCs x ICs] = [Time x ICs]
ica_timecourses = pca_score * Mdl.TransformWeights;

% Reshape Flat Maps back to Image Dimensions
ica_maps = reshape(ica_maps_flat, H, W, num_components);

fprintf('  ICA Complete. Extracted %d components.\n', num_components);


%% ========================================================================
%  SECTION 3: STATISTICS, METRICS & VISUALIZATION
% =========================================================================
fprintf('------------------------------------------------------------\n');
fprintf('SECTION 3: METRICS & PLOTTING\n');
fprintf('------------------------------------------------------------\n');

if ~exist('ica_maps', 'var')
    error('ICA results not found. Please run Section 2 first.');
end

fprintf('%-4s | %-10s | %-10s | %-10s | %-15s\n', ...
    'IC#', 'Dom. Freq', 'Sp. Kurt', 'Max Z-Scr', 'Probable Source');
fprintf('------------------------------------------------------------\n');

% Pre-calculate frequency vector
L = T;
f = Fs*(0:(L/2))/L;
stats_struct = struct();

for i = 1:num_components
    
    % A. Spatial Statistics
    % Use the flattened map from Section 2
    this_map_flat = ica_maps_flat(:,i); 
    sp_kurt = kurtosis(this_map_flat); 
    
    % B. Temporal Statistics (Z-Score)
    this_tc = ica_timecourses(:,i);
    tc_z = (this_tc - mean(this_tc)) / std(this_tc);
    max_z = max(abs(tc_z)); 
    
    % C. Spectral Analysis
    Y = fft(this_tc);
    P2 = abs(Y/L);
    P1 = P2(1:L/2+1);
    P1(2:end-1) = 2*P1(2:end-1);
    
    [max_pow, idx] = max(P1(2:end)); 
    dom_freq = f(idx+1); 
    
    % D. Heuristic Identification
    guess = 'Unknown/Noise';
    if dom_freq >= 3 && dom_freq <= 7
        guess = 'HEARTBEAT';
    elseif dom_freq >= 0.5 && dom_freq <= 2.5
        guess = 'RESPIRATION';
    elseif dom_freq < 0.2
        guess = 'DRIFT/VASO';
    elseif max_z > 5 && sp_kurt > 6
        guess = '*** NEURONAL ***'; 
    end
    
    fprintf('%02d   | %5.1f Hz   | %7.1f    | %7.1f    | %s\n', ...
        i, dom_freq, sp_kurt, max_z, guess);
        
    % Store for plotting
    stats_struct(i).dom_freq = dom_freq;
    stats_struct(i).sp_kurt = sp_kurt;
    stats_struct(i).max_z = max_z;
    stats_struct(i).label = guess;
    stats_struct(i).P1 = P1;
    stats_struct(i).f = f;
    stats_struct(i).tc_z = tc_z;
end

% --- VISUALIZATION ---
figure('Name', 'ICA Component Inspector', 'Color', 'w', 'Position', [50, 50, 1400, 900]);

% Plot Top 5
for i = 1:5
    % 1. Spatial Map 
    subplot(5, 4, (i-1)*4 + 1);
    map_vis = ica_maps(:,:,i);
    clim = [prctile(map_vis(:), 1) prctile(map_vis(:), 99)];
    imagesc(map_vis, clim); 
    colormap(parula); axis image; axis off;
    title(sprintf('IC %02d: Map (Kurt=%.1f)', i, stats_struct(i).sp_kurt), 'FontWeight', 'bold');
    
    % 2. Time Course 
    subplot(5, 4, (i-1)*4 + 2);
    plot((1:T)*(1000/Fs), stats_struct(i).tc_z, 'k'); 
    axis tight; grid on;
    ylabel('Z-Score');
    title(sprintf('Time Course (MaxZ=%.1f)', stats_struct(i).max_z));
    
    % 3. Power Spectrum
    subplot(5, 4, (i-1)*4 + 3);
    plot(stats_struct(i).f, stats_struct(i).P1, 'b', 'LineWidth', 1.5);
    xlim([0 10]); grid on;
    xlabel('Freq (Hz)');
    title(sprintf('Peak=%.1f Hz', stats_struct(i).dom_freq));
    
    % 4. Info
    subplot(5, 4, (i-1)*4 + 4);
    axis off;
    text(0, 0.5, sprintf('Label: %s', stats_struct(i).label), ...
        'FontSize', 10, 'FontWeight', 'bold', 'Color', 'r', 'Interpreter', 'none');
end

fprintf('\nDone. Check figure.\n');