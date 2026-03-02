% NMF_Reconstruction_Master.m
% Extracts, isolates, and reconstructs VSD components using NMF.
% Includes Spatial Binning for vastly faster computation.
% NEW: Option to output and save individual components separately.

% replaces the pca-ica step for decomposition
% ica does blind polarity assignment which inverts the spatial maps
% non negative matrix factorization prevents that by shifting everything to
% positive and then later applying a threshold of 50% to get only the
% positive peaks and applying them on the maps.
% the postive peaks in this maps are actually the negative peaks or the
% depolarization of the neurons, for better visualization and processing it
% has been converted to positive peaks as per varous papers that did the
% same as well, refer to Morales-Botello et al., 1999, imaging the spatio-temporal
% dynamics of supragranular activity in the rat somatosensory cortex paper
% and grinvald and hildesheim 2004, nature, VSDI a new era in funcitonal
% imaging of cortical dynamics

clc; clear; close all;

%% 1. Setup and Load
fprintf('=== NMF CORTICAL WAVE SEPARATOR ===\n\n');

[fName, fPath] = uigetfile('*.h5', 'Select H5 File');
if isequal(fName, 0)
    error('User canceled file selection.');
end
input_file = fullfile(fPath, fName);
fprintf('Selected: %s\n', input_file);

dataset_name = '/functional_dff';

fprintf('\nSelect Sampling Rate:\n 1) 500 Hz\n 2) 1000 Hz\n 3) Custom\n');
choice = input('Enter your choice (1, 2, or 3): ');
switch choice
    case 1, Fs = 500;
    case 2, Fs = 1000;
    case 3, Fs = input('Enter custom sampling rate (Hz): ');
    otherwise, error('Invalid selection.');
end

% Load Data
try
    mov = h5read(input_file, dataset_name);
catch
    error('Could not find %s in the H5 file.', dataset_name);
end

[H, W, T] = size(mov);
fprintf('Loaded movie: %d x %d pixels, %d frames\n', H, W, T);

%% 2. Speed Optimization (Spatial Binning) & Smoothing
bin_factor = 2; % Shrinks image by half, making NMF 4x faster
fprintf('Applying spatial binning (factor of %d) for faster computation...\n', bin_factor);

% Resize the movie
mov_binned = imresize(mov, 1/bin_factor);
[Hb, Wb, ~] = size(mov_binned);

fprintf('Spatial smoothing...\n');
for t = 1:T
    mov_binned(:,:,t) = imgaussfilt(mov_binned(:,:,t), 2); 
end

% Flatten using the binned dimensions
X = reshape(mov_binned, Hb*Wb, T);
X(isnan(X)) = 0;

% Shift data so there are no negative numbers (Required for NMF)
min_val = min(X(:));
if min_val < 0
    fprintf('Data contains negative values (min: %.4f). Shifting to strictly positive...\n', min_val);
    X_pos = X - min_val;
else
    X_pos = X;
end

%% 3. Run Non-Negative Matrix Factorization (NMF)
num_components = 8; 
fprintf('\nRunning NMF to extract %d components on optimized matrix...\n', num_components);

% Use W_nmf and H_nmf to prevent overwriting dimensions!
options = statset('UseParallel', true); 
[W_nmf, H_nmf] = nnmf(X_pos, num_components, 'options', options, 'algorithm', 'als', 'replicates', 3);

% Reshape spatial maps back into the binned 2D shape
nmf_maps_binned = reshape(W_nmf, Hb, Wb, num_components);

fprintf('NMF Complete.\n');

%% 4. Visual Dashboard for Component Selection
fprintf('\nGenerating visual dashboard for component selection...\n');

time_axis = (1:T) / Fs;
figure('Name', 'NMF Component Selector', 'Color', 'w', 'Position', [100 100 1400 800]);

for k = 1:num_components
    % Plot Spatial Map
    subplot(4, 4, (k-1)*2 + 1);
    imagesc(nmf_maps_binned(:,:,k)); 
    axis image off; colormap(gca, 'turbo');
    title(sprintf('NMF Component %d', k), 'FontWeight', 'bold');
    
    % Plot Timecourse
    subplot(4, 4, (k-1)*2 + 2);
    plot(time_axis, H_nmf(k,:), 'k', 'LineWidth', 1.2);
    axis tight; box off;
    xlabel('Time (s)'); ylabel('Intensity');
end

%% 5. Interactive Selection
fprintf('\n======================================================\n');
fprintf(' Look at the figure window. Identify the components \n');
fprintf(' that represent your actual wave propagation.       \n');
fprintf(' (Ignore stationary noise, global flashes, etc.)    \n');
fprintf('======================================================\n');

% Pause and wait for user input
selected_ICs = input('Enter the components you want to keep as an array (e.g., [1 3 4]): ');

if isempty(selected_ICs)
    error('No components selected. Aborting.');
end

fprintf('\nHow would you like to save the selected components?\n');
fprintf('  1) Combined (Reconstructed as one movie)\n');
fprintf('  2) Individually (Separate .mat file for each component)\n');
fprintf('  3) Both Combined and Individually\n');
save_mode = input('Enter choice (1, 2, or 3): ');

if isempty(save_mode) || ~ismember(save_mode, [1, 2, 3])
    fprintf('Invalid choice. Defaulting to Both (3).\n');
    save_mode = 3;
end

%% 6. Reconstruction and Saving
[~, base_name, ~] = fileparts(fName);

% --- SAVE COMBINED ---
if save_mode == 1 || save_mode == 3
    fprintf('\nReconstructing COMBINED movie using components: %s\n', mat2str(selected_ICs));
    
    % Reconstruct using selected components
    X_recon = W_nmf(:, selected_ICs) * H_nmf(selected_ICs, :);
    reconstructed_binned = reshape(X_recon, Hb, Wb, T);
    
    % Restore Original Resolution
    reconstructed_movie = imresize(reconstructed_binned, [H, W]);
    
    out_file = sprintf('reconstructed_NMF_COMBINED_%s.mat', base_name);
    out_path = fullfile(fPath, out_file);
    fprintf('Saving combined movie to: %s\n', out_path);
    save(out_path, 'reconstructed_movie', 'Fs', 'selected_ICs');
end

% --- SAVE INDIVIDUALLY ---
if save_mode == 2 || save_mode == 3
    fprintf('\nReconstructing INDIVIDUAL components...\n');
    
    for c = selected_ICs
        fprintf('  -> Processing Component %d...\n', c);
        
        % Reconstruct using ONLY this single component
        X_recon_single = W_nmf(:, c) * H_nmf(c, :);
        recon_binned_single = reshape(X_recon_single, Hb, Wb, T);
        
        % Restore Original Resolution
        reconstructed_movie = imresize(recon_binned_single, [H, W]);
        
        out_file_single = sprintf('reconstructed_NMF_Comp%d_%s.mat', c, base_name);
        out_path_single = fullfile(fPath, out_file_single);
        
        % Keep track of which component this file is for reference
        selected_component = c; 
        
        fprintf('     Saving to: %s\n', out_file_single);
        save(out_path_single, 'reconstructed_movie', 'Fs', 'selected_component');
    end
end

fprintf('\n=== DONE ===\n');
fprintf('Files are ready for Isochrone Mapping!\n');