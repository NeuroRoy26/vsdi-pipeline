% analysis_Step1_Master_Isochrones.m
% BATCH PROCESSOR: Signal Extraction + Isochrone Mapping + Virtual MEA
% support script for NNMF decompostion to visualize contours and isochrones
% for time lapse montage or to investigate the active areas
% 
% NEW FEATURES:
%   - HDF5 SUPPORT: Reads '/functional_dff' from .h5 files automatically.
%   - NMF COMPONENT SUPPORT: Automatically detects and labels individual NMF components.
%   - ISOCHRONE MAPPING: Maps time-to-peak for active pixels.
%   - VECTOR FIELD: Displays directional arrows of cortical propagation.

clearvars -except files path_name do_concat; 
clc; close all;

%% ======================== CONFIGURATION ========================
CONFIG.bandpass_freq = [0.1, 75];     % Hz
CONFIG.filter_order = 4;              
CONFIG.default_fs = 500;              
CONFIG.output_file = 'All_Experiments_Isochrones.mat';

% --- FLEXMEA72 GRID SETTINGS ---
CONFIG.microns_per_pixel = 9.4; 
CONFIG.grid_pitch_x_um = 625;  
CONFIG.grid_pitch_y_um = 750;  
CONFIG.elec_diam_um = 100;     
CONFIG.grid_dim = [8, 9];      

% --- OVERRIDES ---
CONFIG.files_to_invert = {}; % Files that need spatial * -1

%% ======================== FILE SELECTION & SORTING ========================
fprintf('========================================\n');
fprintf(' VSD PIPELINE: Isochrone Mapping & Virtual MEA\n');
fprintf('========================================\n\n');

if ~exist('files', 'var')
    [files, path_name] = uigetfile({'*.h5;*.mat', 'Data Files (*.h5, *.mat)'}, 'Select Files', 'MultiSelect', 'on');
    if isequal(files, 0), return; end
    if ischar(files), files = {files}; end
end

% Sort files logically
if length(files) > 1
    file_scores = zeros(length(files), 1);
    for i = 1:length(files)
        e_token = regexp(files{i}, '[Ee](\d+)', 'tokens', 'once');
        b_token = regexp(files{i}, '[Bb](\d+)', 'tokens', 'once');
        e_val = 0; b_val = 0;
        if ~isempty(e_token), e_val = str2double(e_token{1}); end
        if ~isempty(b_token), b_val = str2double(b_token{1}); end
        file_scores(i) = (e_val * 1000000) + b_val;
    end
    [~, sort_idx] = sort(file_scores);
    files = files(sort_idx);
end
num_files = length(files);

%% ======================== PROCESSING LOOP ========================
All_Experiments = struct();

for k = 1:num_files
    fname = files{k};
    full_path = fullfile(path_name, fname);
    fprintf('\n[%d/%d] Processing: %s\n', k, num_files, fname);
    
    try
        %% --- LOAD DATA (.MAT or .H5) ---
        [~, ~, ext] = fileparts(fname);
        comp_label = ''; % Default empty label
        
        if strcmp(ext, '.mat')
            % Load data, also check for 'selected_component' from the NMF script
            D = load(full_path, 'reconstructed_movie', 'Fs', 'selected_component');
            if ~isfield(D, 'reconstructed_movie'), continue; end
            mov = D.reconstructed_movie;
            if isfield(D, 'Fs'), Fs = D.Fs; else, Fs = CONFIG.default_fs; end
            
            % Check if this is a specific NMF component
            if isfield(D, 'selected_component')
                comp_label = sprintf(' [Component %d]', D.selected_component);
                fprintf('  -> Detected NMF Component %d\n', D.selected_component);
            end
            
        elseif strcmp(ext, '.h5')
            try
                mov = h5read(full_path, '/functional_dff'); 
                Fs = CONFIG.default_fs; 
            catch ME
                fprintf('  ✗ ERROR: Could not read /functional_dff from %s\n', fname);
                continue;
            end
        else
            continue; 
        end
        
        %% --- TRIM ---
        frames_trim_start = 10; frames_trim_end = 5;
        if size(mov,3) > 15
            mov = mov(:, :, (frames_trim_start+1):(end-frames_trim_end));
        end
        [height, width, num_frames] = size(mov);
        
        %% --- MANUAL POLARITY OVERRIDE ---
        is_inverted = false;
        for i = 1:length(CONFIG.files_to_invert)
            if contains(fname, CONFIG.files_to_invert{i})
                mov = -mov; 
                is_inverted = true;
                fprintf('  -> Applied manual spatial inversion (-1) for %s\n', fname);
                break;
            end
        end
        
        %% --- GLOBAL TRACE EXTRACTION ---
        raw_trace = squeeze(mean(mean(mov, 1), 2));
        nyq = Fs / 2;
        [b, a] = butter(CONFIG.filter_order, CONFIG.bandpass_freq / nyq, 'bandpass');
        clean_trace = filtfilt(b, a, raw_trace);
        
        mu = mean(clean_trace); sigma = std(clean_trace);
        final_trace = (clean_trace - mu) / sigma;
        current_time_axis = (0:length(final_trace)-1) / Fs;
        
        %% --- VIRTUAL MEA EXTRACTION ---
        px_pitch_x = CONFIG.grid_pitch_x_um / CONFIG.microns_per_pixel;
        px_pitch_y = CONFIG.grid_pitch_y_um / CONFIG.microns_per_pixel;
        [GX, GY] = meshgrid(((0:7) - 3.5) * px_pitch_x, ((0:8) - 4) * px_pitch_y);
        
        GX = GX + (width/2); GY = GY + (height/2);
        
        valid_mask = true(9, 8);
        valid_mask(1, [4, 5]) = false; valid_mask(9, [1, 8]) = false; 
        valid_mask(2, [4, 5]) = false; valid_mask(8, [1, 8]) = false; 
        
        GX_rec = GX(valid_mask); GY_rec = GY(valid_mask);
        num_elecs = length(GX_rec);
        virtual_mea_traces = zeros(num_elecs, num_frames);
        elec_radius_px = (CONFIG.elec_diam_um / CONFIG.microns_per_pixel) / 2;
        
        [XX, YY] = meshgrid(1:width, 1:height);
        tmp_mov = reshape(mov, [], num_frames);
        
        for e = 1:num_elecs
            dist_map = sqrt((XX - GX_rec(e)).^2 + (YY - GY_rec(e)).^2);
            elec_mask = dist_map <= elec_radius_px;
            virtual_mea_traces(e, :) = mean(tmp_mov(elec_mask(:), :), 1);
        end
        
        %% --- ISOCHRONE (LATENCY) MAPPING ---
        mov_smooth = imgaussfilt(mov, [1, 5]);
        [~, global_peak_idx] = max(final_trace);
        
        search_win_frames = round(0.100 * Fs); 
        win_start = max(1, global_peak_idx - search_win_frames);
        win_end   = min(num_frames, global_peak_idx + search_win_frames);
        active_window = mov_smooth(:, :, win_start:win_end);
        
        min_vals = min(active_window, [], 3);
        max_vals = max(active_window, [], 3);
        thresholds = min_vals + ((max_vals - min_vals) * 0.5);
        
        above_half = active_window >= thresholds;
        [~, onset_indices_in_window] = max(above_half, [], 3);
        
        absolute_peak_frames = onset_indices_in_window + (win_start - 1);
        latency_ms = double(absolute_peak_frames) * (1000 / Fs);
        
        brightness_thresh = prctile(max_vals(:), 85);
        signal_mask = max_vals > brightness_thresh;
        latency_ms(~signal_mask) = NaN;
        
        first_activation_ms = min(latency_ms(:));
        relative_latency_ms = latency_ms - first_activation_ms;
        
        %% --- VISUALIZATION ---
        % Notice the title now dynamically includes the NMF component label
        figure('Name', sprintf('VSD Dynamics: %s%s', fname, comp_label), 'Color', 'w', 'Position', [100 100 1200 500]);
        
        subplot(1, 2, 1);
        bg_img = mat2gray(max(mov, [], 3)); 
        imshow(bg_img, []); hold on;
        
        h = imagesc(relative_latency_ms);
        set(h, 'AlphaData', signal_mask * 0.7); 
        colormap(gca, 'turbo');
        c = colorbar; 
        ylabel(c, 'Time since onset (ms)', 'FontSize', 12, 'FontWeight', 'bold');
        
        contour(relative_latency_ms, 8, 'k', 'LineWidth', 1.2);
        
        [DX, DY] = gradient(relative_latency_ms);
        skip = 4; 
        [X_grid, Y_grid] = meshgrid(1:width, 1:height);
        quiver(X_grid(1:skip:end, 1:skip:end), Y_grid(1:skip:end, 1:skip:end), ...
               DX(1:skip:end, 1:skip:end), DY(1:skip:end, 1:skip:end), ...
               1.5, 'w', 'LineWidth', 1);
               
        title(sprintf('Wave Propagation%s', comp_label), 'FontSize', 14);
        axis image off;
        
        subplot(1, 2, 2);
        imagesc(current_time_axis, 1:num_elecs, virtual_mea_traces);
        xlabel('Time (s)'); ylabel('Virtual Electrode #');
        title(sprintf('Virtual MEA Evoked Response%s', comp_label));
        colorbar;
        xline(global_peak_idx / Fs, 'r--', 'Global Peak', 'LineWidth', 1.5);
        
        %% --- STORAGE ---
        All_Experiments(k).filename = fname;
        if ~isempty(comp_label)
            All_Experiments(k).nmf_component = D.selected_component;
        end
        All_Experiments(k).inverted = is_inverted;
        All_Experiments(k).trace = final_trace;
        All_Experiments(k).fs = Fs;
        All_Experiments(k).Virtual_MEA.traces = virtual_mea_traces;
        All_Experiments(k).Virtual_MEA.coords_X = GX_rec;
        All_Experiments(k).Virtual_MEA.coords_Y = GY_rec;
        All_Experiments(k).LatencyMap = relative_latency_ms;
        
    catch ME
        fprintf('  ✗ ERROR: %s\n', ME.message);
    end
end

% Save Results
save(CONFIG.output_file, 'All_Experiments', 'CONFIG');
fprintf('\n========================================\n');
fprintf('  ✓ Processing Complete. Data saved.\n');