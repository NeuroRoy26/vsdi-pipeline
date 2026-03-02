% analysis_Step1_Concatenate.m
% Same as analysis_Step1.m script but concatenated
% Containes Trigger Extraction
% BATCH PROCESSOR: Signal Extraction with CONCATENATION Support
% Tried to apply spatial processing techniques
% calculated std dev and mean and max proj of the images
% recalculated dff (no difference in result)
% only thing to takeway from this script is the trigger detection logic
% rest are not that useful
%
% NEW FEATURES:
%   - Concatenates 1D traces across selected files
%   - Creates unified time axis
%   - Stores individual file metadata for Step 2 reconstruction
%   - SORTS FILES by embedded numbers (E0B0, E0B1, E0B2, etc.)
%   - SMART TRIGGER: Calculates Onset via Tangent Projection
%   - FLEXMEA72 OVERLAY: Visualizes electrode grid on spatial maps
%   - ADVANCED HARVESTING: Gradient Borders, Watershed ROIs, Wavefront Maps
%
% MEMORY EFFICIENT: Only processes one movie at a time, stores traces only
% 1. SMART CLEAR: Keeps files if they are already loaded
clearvars -except files path_name do_concat; 
clc; close all;
%% ======================== CONFIGURATION ========================
CONFIG.bandpass_freq = [0.1, 75];     % Hz - Bandpass filter range
CONFIG.filter_order = 4;              % Butterworth filter order
CONFIG.default_fs = 500;              % Hz - Default sampling frequency
CONFIG.output_file = 'All_Experiments_Summary.mat';
CONFIG.enable_concatenation = true;   % NEW: Enable concatenation mode
% --- FLEXMEA72 GRID SETTINGS ---
% Resolution: (4.7 x 4.7) * 2 = 9.4 microns per pixel
CONFIG.microns_per_pixel = 9.4; 
% Dimensions from Datasheet
CONFIG.grid_pitch_x_um = 625;  % Horizontal pitch
CONFIG.grid_pitch_y_um = 750;  % Vertical pitch
CONFIG.elec_diam_um = 100;     % Electrode diameter
CONFIG.grid_dim = [8, 9];      % 8 Columns x 9 Rows (A-J approx)
%% ======================== FILE SELECTION ========================
fprintf('========================================\n');
fprintf(' BATCH PROCESSOR - Signal Extraction\n');
fprintf(' WITH CONCATENATION SUPPORT\n');
fprintf('========================================\n\n');
% Smart Check: Only ask for files if we don't have them yet
if ~exist('files', 'var')
    fprintf('Please select your reconstruction files...\n');
    [files, path_name] = uigetfile('*.mat', ...
        'Select One or More Reconstruction Files (in order)', ...
        'MultiSelect', 'on');
    if isequal(files, 0)
        fprintf('Selection canceled by user.\n'); 
        return; 
    end
    
    % Ensure files is a cell array
    if ischar(files)
        files = {files}; 
    end
else
    fprintf('Using previously selected files from workspace.\n');
end
%% ======================== SORT FILES BY EMBEDDED NUMBERS ========================
% ROBUST SORTING: Prioritizes E...B... pattern, falls back to trailing numbers
if length(files) > 1
    file_scores = zeros(length(files), 1);
    
    for i = 1:length(files)
        fname = files{i};
        
        % 1. Look for specific E(number) and B(number) pattern (Case Insensitive)
        e_token = regexp(fname, '[Ee](\d+)', 'tokens', 'once');
        b_token = regexp(fname, '[Bb](\d+)', 'tokens', 'once');
        
        e_val = 0; b_val = 0; found_pattern = false;
        
        if ~isempty(e_token), e_val = str2double(e_token{1}); found_pattern = true; end
        if ~isempty(b_token), b_val = str2double(b_token{1}); found_pattern = true; end
        
        if found_pattern
            file_scores(i) = (e_val * 1000000) + b_val;
        else
            % Fallback strategies
            fallback_tok = regexp(fname, '(\d+)\.mat$', 'tokens', 'once');
            if ~isempty(fallback_tok)
                file_scores(i) = str2double(fallback_tok{1});
            else
                any_num = regexp(fname, '(\d+)', 'tokens');
                if ~isempty(any_num)
                    file_scores(i) = str2double(any_num{end}{1});
                else
                    file_scores(i) = 0;
                end
            end
        end
    end
    
    [~, sort_idx] = sort(file_scores);
    files = files(sort_idx);
    
    fprintf('Files sorted by number:\n');
    for i = 1:length(files)
        fprintf('  %d. %s\n', i, files{i});
    end
    fprintf('\n');
end
num_files = length(files);
fprintf('Selected %d file(s).\n\n', num_files);
% Ask user if they want concatenation (Only if not already decided/scripted)
if ~exist('do_concat', 'var')
    if num_files > 1 && CONFIG.enable_concatenation
    % Note: You can comment this out to force YES if you prefer
    answer = questdlg(sprintf(['You selected %d files.\n\n' ...
                               'Do you want to CONCATENATE them?\n'], num_files), ...
                      'Concatenation Mode', ...
                      'YES - Concatenate', 'NO - Separate', 'YES - Concatenate');
    do_concat = strcmp(answer, 'YES - Concatenate');
    else
    do_concat = false;
    end
else
    fprintf('Automatic Concatenation, run clear; to remove \n');
end
fprintf('\n');
if do_concat
    fprintf('🔗 CONCATENATION MODE: Merging %d files into unified recording\n\n', num_files);
else
    fprintf('📁 INDIVIDUAL MODE: Processing %d files separately\n\n', num_files);
end
%% ======================== PROCESSING LOOP ========================
All_Experiments = struct();
% Storage for concatenation
if do_concat
    concat_traces = [];
    concat_metadata = struct();
    concat_metadata.file_segments = [];
    concat_metadata.total_frames = 0;
end
%%
for k = 1:num_files
    fname = files{k};
    full_path = fullfile(path_name, fname);
    
    fprintf('[%d/%d] Processing: %s\n', k, num_files, fname);
    
    try
        %% --- LOAD DATA ---
        D = load(full_path, 'reconstructed_movie', 'Fs');
        
        if ~isfield(D, 'reconstructed_movie')
            warning('  ⚠ No reconstructed_movie field found. Skipping...');
            All_Experiments(k).filename = fname;
            All_Experiments(k).error = 'Missing reconstructed_movie field';
            continue;
        end
        
        mov = D.reconstructed_movie;
        
        %% --- TRIMMING (Happens First) ---
        frames_to_trim_start = 10;  
        frames_to_trim_end   = 5;   
        
        if size(mov, 3) > (frames_to_trim_start + frames_to_trim_end)
            % The 3D Slicing Operation: mov(Rows, Cols, Time)
            mov = mov(:, :, (frames_to_trim_start+1) : (end - frames_to_trim_end));
            fprintf('  ✂ Trimmed data: Removed first %d and last %d frames.\n', ...
                    frames_to_trim_start, frames_to_trim_end);
        else
            warning('  ⚠ Too short to trim. Keeping original length.');
        end
        
        [height, width, num_frames] = size(mov);
        
        %% --- DETERMINE SAMPLING FREQUENCY ---
        if isfield(D, 'Fs')
            Fs = D.Fs;
        else
            tok = regexp(fname, '_(\d+)_', 'tokens', 'once');
            if ~isempty(tok), Fs = str2double(tok{1}); else, Fs = CONFIG.default_fs; end
        end
        
        %% --- EXTRACT TRACE ---
        raw_trace = squeeze(mean(mean(mov, 1), 2));
        
        %% --- BANDPASS FILTERING ---
        nyq = Fs / 2;
        [b, a] = butter(CONFIG.filter_order, CONFIG.bandpass_freq / nyq, 'bandpass');
        clean_trace = filtfilt(b, a, raw_trace);
        
        %% --- POLARITY CORRECTION ---
        half_idx = floor(num_frames / 2);
        second_half_trace = clean_trace(half_idx:end);
        sk_2nd_half = skewness(second_half_trace);
        
        if sk_2nd_half < 0
            curr_trace = -clean_trace;
            polarity_action = 'FLIPPED';
        else
            curr_trace = clean_trace;
            polarity_action = 'KEPT';
        end
        
        %% --- Z-SCORE NORMALIZATION ---
        mu = mean(curr_trace);
        sigma = std(curr_trace);
        
        if sigma ~= 0
            final_trace = (curr_trace - mu) / sigma;
            fprintf('  ✓ Polarity: %s | Z-Scored (Mean=%.2f, Std=%.2f)\n', ...
                    polarity_action, mu, sigma);
        else
            final_trace = curr_trace;
            fprintf('  ⚠ Warning: Flat line detected (Std=0)\n');
        end
        %% --- TIME AXIS CREATION ---
        % (We will shift this later once we find the trigger)
        current_time_axis = (0:length(final_trace)-1) / Fs;
        %% --- TRIGGER DETECTION (WITH PARALLEL FILTERING) ---
        % 1. Create a temporary 'Detection Trace' (Heavily smoothed)
        %    We use a moving average filter to kill noise spikes
        smooth_window = round(Fs * 0.05); % 50ms smoothing window
        detection_trace = smooth(final_trace, smooth_window, 'moving');
        
        % 2. Calculate derivative on the SMOOTHED trace
        deriv_trace = [0; diff(detection_trace)];
        
        % 3. VISUALIZATION (Comparing Raw vs. Filtered)
        if k == 1
            figure('Name', ['Trigger Logic Check - ' fname], 'Color', 'w', 'Position', [100, 100, 1000, 800]);
            
            % Plot 1: Raw vs Smooth Signal
            subplot(2, 1, 1);
            plot(current_time_axis, final_trace, 'Color', [0.7 0.7 0.7], 'DisplayName', 'Raw Data (kept)');
            hold on;
            plot(current_time_axis, detection_trace, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Filtered (for detection only)');
            title('Step 1: Create Smoothed Copy');
            legend('show'); grid on; axis tight;
            
            % Plot 2: The Derivative of the SMOOTHED signal
            subplot(2, 1, 2);
            plot(current_time_axis, deriv_trace, 'r-', 'LineWidth', 1);
            title('Step 2: Derivative of Filtered Trace');
            ylabel('dF/dt (Smoothed)');
            grid on; axis tight;
            
           
            % fprintf(' Paused for visualization. Press any key to continue...\n');
            % pause; 
            
        end
        
        %%  STEP 1.5: FlexMEA72 GRID OVERLAY
        % ============================================================
        
        % --- GENERATE PREVIEW IMAGE ---
        preview_img = max(mov, [], 3);
        % 1. Calculate Pixel Dimensions
        px_pitch_x = CONFIG.grid_pitch_x_um / CONFIG.microns_per_pixel;
        px_pitch_y = CONFIG.grid_pitch_y_um / CONFIG.microns_per_pixel;
        px_diam    = CONFIG.elec_diam_um / CONFIG.microns_per_pixel;
        
        % 2. Create Centered Grid Coordinates
        % The FlexMEA72 is an 8x9 grid
        cols = CONFIG.grid_dim(1);
        rows = CONFIG.grid_dim(2);
        
        % Define grid vectors centered around 0
        x_vec = ((0:cols-1) - (cols-1)/2) * px_pitch_x;
        y_vec = ((0:rows-1) - (rows-1)/2) * px_pitch_y;
        
        [GX, GY] = meshgrid(x_vec, y_vec);
        
        % 3. MASKING: Remove GND and REF Electrodes
        % Mask is 9 Rows x 8 Cols
        % True = Recording Electrode, False = GND/REF
        valid_mask = true(rows, cols);
        
        % Remove GNDs (Row 1: Cols 4,5 AND Row 9: Cols 1,8)
        valid_mask(1, [4, 5]) = false; 
        valid_mask(9, [1, 8]) = false;
        
        % Remove REFs (Row 2: Cols 4,5 AND Row 8: Cols 1,8)
        valid_mask(2, [4, 5]) = false; 
        valid_mask(8, [1, 8]) = false;
        
        % 4. Apply Shift to Center
        center_x = width / 2;
        center_y = height / 2;
        
        GX = GX + center_x;
        GY = GY + center_y;
        
        % 5. Filter for Plotting
        GX_rec = GX(valid_mask);
        GY_rec = GY(valid_mask);
        
        % 6. Visualization Check (First file only)
        if k == 1
            figure('Name', 'FlexMEA72 Recording Sites', 'Color', 'w');
            imshow(preview_img, []);
            hold on;
            title(sprintf('MEA Overlay | Pitch: %.1fum x %.1fum | Res: %.2f um/px', ...
                  CONFIG.grid_pitch_x_um, CONFIG.grid_pitch_y_um, CONFIG.microns_per_pixel));
            
            % Plot Recording Electrodes (Black)
            plot(GX_rec, GY_rec, 'o', 'MarkerSize', px_diam/2, ...
                 'Color', 'k', 'LineWidth', 1.5, 'DisplayName', 'Recording');
                 
            % Optional: Plot Disabled sites nicely (faint red x) if you want to verify positions
            GX_bad = GX(~valid_mask); GY_bad = GY(~valid_mask);
            plot(GX_bad, GY_bad, 'rx', 'MarkerSize', 8, 'DisplayName', 'GND/REF');
        
            hold off;
        end
        
        if k == 1
            mov_filtered = zeros(size(mov));
            mov_filtered = imgaussfilt(mov, 2);      %sigma = 2
            % mov_filtered = medfilt3(mov, [3 3 1]); %medianfilter= 3x3x1frame
            preview_img_2 = mean(mov_filtered, 3);
            figure('Name', 'Mean Spatial Image', 'Color', 'w');
            imshow(preview_img_2, []);
            title(sprintf('average across all frames anatomy'));
            
            preview_img_3 = max(mov_filtered, [], 3);
            figure('Name', 'Max Spatial Image', 'Color', 'w');
            imshow(preview_img_3, []);
            title(sprintf('Max pixels per frame across all frames'));
            preview_img_4 = std(double(mov_filtered), 0, 3);
            figure('Name', 'STD DEV Spatial Image', 'Color', 'w');
            imshow(preview_img_4, []);
            title(sprintf('Std Dev across all frames Activity'));
            
            % mov_centered = double(mov) - mean(mov, 3); 
            % im_right = circshift(mov_centered, [0 1 0]); % Calculate Correlation approx using multiplication of neighbors
            % im_left  = circshift(mov_centered, [0 -1 0]); % Shift image right, left, up, down
            % im_up    = circshift(mov_centered, [-1 0 0]);
            % im_down  = circshift(mov_centered, [1 0 0]);
            % % Calculate average product (covariance approximation)
            % corr_map = mean(mov_centered .* im_right + ...
            %                 mov_centered .* im_left + ...
            %                 mov_centered .* im_up + ...
            %                 mov_centered .* im_down, 3);
            % 
            % figure;
            % imagesc(corr_map);
            % axis image off;
            % title('Correlation Image (Active Neurons)');
            F_max = max(mov, [], 3); 
            F_0 = median(mov, 3); 
            F_0 = double(F_0); 
            F_0(F_0 < 1) = 1; 
            dFF_map = (double(F_max) - F_0) ./ F_0;
            figure('Name', 'Delta F / F Map', 'Color', 'w');
            imagesc(dFF_map); 
            % clim([0 2]); % Adjust this: Try [0 1] or [0 5] depending on signal strength
            % colormap('jet'); % 'Jet' or 'Parula' works well here
            % colorbar;
            axis image off;
            title('Max \DeltaF/F Map (Normalized Activity)');
            
%% --- NEW: HARVESTING THE "DOODLING" ARTIFACTS (VERSION 3) ---
            figure('Name', 'Harvesting Analysis', 'Color', 'w', 'Position', [150 150 1200 400]);
            
            % STEP 0: CREATE ROBUST MASK (The Key Fix)
            % imbinarize(mat2gray(...)) automatically finds the best threshold 
            % to separate bright signal from dark background.
            active_mask = imbinarize(mat2gray(dFF_map)); 
            
            % Clean up the mask: Fill holes inside neurons, remove tiny noise specks
            active_mask = imfill(active_mask, 'holes');
            active_mask = bwareaopen(active_mask, 20); % Remove spots < 20 pixels
            
            % STEP 1: GRADIENT (Weighted)
            % We multiply by the mask so the background turns pure black
            dFF_smooth = medfilt2(dFF_map, [3 3]); 
            [Gmag, ~] = imgradient(dFF_smooth);
            Gmag_clean = Gmag .* double(active_mask); 
            
            subplot(1, 3, 1);
            imagesc(Gmag_clean);
            % Focus contrast only on the active parts
            clim([0 prctile(Gmag(active_mask), 95)]); 
            colormap(gca, 'hot'); 
            axis image off;
            title('1. Spatial Gradient (Active Borders)');
            
            % STEP 2: WATERSHED (Masked)
            % 1. Smooth Gmag slightly so neurons don't break into tiny pieces
            % 2. Run Watershed
            L = watershed(imgaussfilt(Gmag, 4.0)); 
            % 3. APPLY MASK: Force background to be Black (0)
            L(~active_mask) = 0; 
            
            L_rgb = label2rgb(L, 'jet', 'k', 'shuffle'); 
            subplot(1, 3, 2);
            imshow(L_rgb);
            title('2. Watershed (Signal Only)');
            
            % STEP 3: WAVEFRONT (Time-to-Peak)
            [~, max_indices] = max(mov, [], 3);
            time_map = double(max_indices) / Fs; 
            
            % Apply the same mask
            time_map(~active_mask) = NaN; 
            
            subplot(1, 3, 3);
            h = imagesc(time_map);
            set(h, 'AlphaData', ~isnan(time_map)); % Make background transparent
            colormap(gca, 'jet');
            cb = colorbar; ylabel(cb, 'Time of Peak (s)');
            axis image off;
            title('3. Wavefront (Time-to-Peak)');
            
            linkaxes(findall(gcf, 'type', 'axes'));
            
        end
        
        %% --- STORE INDIVIDUAL FILE DATA ---
        All_Experiments(k).filename       = fname;
        All_Experiments(k).folder         = path_name;
        All_Experiments(k).fs             = Fs;
        All_Experiments(k).dimensions     = [height, width, num_frames];
        All_Experiments(k).trace          = final_trace; 
        All_Experiments(k).raw_trace      = raw_trace;
        All_Experiments(k).skewness_2nd   = sk_2nd_half;
        All_Experiments(k).polarity       = polarity_action;
        All_Experiments(k).preview_img    = preview_img;
        % Store Grid Coordinates in case we need them later
        All_Experiments(k).grid_overlay.X = GX;
        All_Experiments(k).grid_overlay.Y = GY;
        All_Experiments(k).time_axis      = current_time_axis; % Saved safely
        All_Experiments(k).processing_date = datestr(now);
        
        %% --- CONCATENATION DATA COLLECTION ---
        if do_concat
            concat_traces = [concat_traces; final_trace(:)];
            
            segment = struct();
            segment.file_index = k;
            segment.filename = fname;
            segment.start_frame = concat_metadata.total_frames + 1;
            segment.end_frame = concat_metadata.total_frames + num_frames;
            segment.num_frames = num_frames;
            segment.fs = Fs;
            segment.polarity = polarity_action;
            
            concat_metadata.file_segments = [concat_metadata.file_segments; segment];
            concat_metadata.total_frames = concat_metadata.total_frames + num_frames;
        end
        
        fprintf('  ✓ Successfully processed (%d frames)\n', num_frames);
        
    catch ME
        fprintf('  ✗ ERROR: %s\n', ME.message);
        All_Experiments(k).filename = fname;
        All_Experiments(k).error = ME.message;
    end
    
    % Memory cleanup
    clear D mov raw_trace clean_trace final_trace preview_img second_half_trace curr_trace;
    fprintf('\n');
end
%% ======================== CREATE CONCATENATED RECORDING ========================
% ROBUST VERSION: Checks for actual segments before running
if do_concat && ~isempty(concat_traces) && isfield(concat_metadata, 'file_segments') && ~isempty(concat_metadata.file_segments)
    
    fprintf('========================================\n');
    fprintf('🔗 CREATING CONCATENATED RECORDING\n');
    fprintf('========================================\n');
    
    % --- 1. ROBUSTLY FIND SAMPLING RATE ---
    valid_idx = find(~arrayfun(@(x) isempty(x.fs), All_Experiments), 1);
    if isempty(valid_idx)
        Fs_concat = CONFIG.default_fs; 
    else
        Fs_concat = All_Experiments(valid_idx).fs(1); % Ensure scalar
    end
    
    % --- 2. CREATE TIME AXIS ---
    time_concat = (0:length(concat_traces)-1)' / Fs_concat;
    
    % --- 3. IDENTIFY SEGMENTS (ROBUST) ---
    num_segments = length(concat_metadata.file_segments);
    segment_times = zeros(num_segments, 1);
    
    for k = 1:num_segments
        seg = concat_metadata.file_segments(k);
        if seg.start_frame <= length(time_concat)
            segment_times(k) = time_concat(seg.start_frame);
        end
    end
    
    % --- 4. STORE RESULTS ---
    Concatenated_Recording = struct();
    Concatenated_Recording.trace = concat_traces;
    Concatenated_Recording.time_axis = time_concat;
    Concatenated_Recording.fs = Fs_concat;
    Concatenated_Recording.total_frames = concat_metadata.total_frames;
    Concatenated_Recording.num_files = num_files;        
    Concatenated_Recording.num_segments = num_segments; 
    Concatenated_Recording.file_segments = concat_metadata.file_segments;
    Concatenated_Recording.segment_start_times = segment_times;
    Concatenated_Recording.creation_date = datestr(now);
    fprintf('  ✓ Total duration: %.2f seconds\n', time_concat(end));
    fprintf('  ✓ Total frames: %d\n', concat_metadata.total_frames);
    fprintf('  ✓ Files merged: %d (Attempted: %d)\n', num_segments, num_files);
    fprintf('\n');
    
    % --- 5. VISUALIZATION ---
    if exist('segment_times', 'var')
        figure('Name', 'Concatenated Trace Preview', 'Position', [100, 100, 1200, 400]);
        plot(time_concat, concat_traces, 'k-', 'LineWidth', 1);
        hold on;
        
        for k = 1:num_segments
            safe_name = concat_metadata.file_segments(k).filename;
            xline(segment_times(k), 'r--', safe_name, ...
                  'LineWidth', 1.5, 'LabelOrientation', 'horizontal', ...
                  'Interpreter', 'none', 'FontSize', 8);
        end
        
        xlabel('Time (s)', 'FontSize', 11);
        ylabel('ΔF/F (a.u.)', 'FontSize', 11);
        title(sprintf('Concatenated Recording (%d segments, %.1f sec total)', num_segments, time_concat(end)), ...
              'FontSize', 12, 'FontWeight', 'bold');
        grid on; axis tight;
    end
    % ============================================================
    % 🔗 NEW: CONCATENATED DERIVATIVE ANALYSIS
    % ============================================================
    figure('Name', 'Concatenated Derivative Analysis', 'Position', [150, 150, 1200, 600]);
    
    % --- Top Plot: Full Z-Scored Trace ---
    subplot(2,1,1);
    plot(time_concat, concat_traces, 'k-', 'LineWidth', 0.8);
    hold on;
    % Mark segment boundaries
    for k = 1:num_segments
        xline(segment_times(k), 'r--', 'LineWidth', 1);
    end
    title('Full Concatenated Recording (Z-Score)', 'FontSize', 12);
    ylabel('Amplitude (SD)');
    grid on; axis tight;
    
    % --- Bottom Plot: Full Derivative ---
    concat_deriv = [0; diff(concat_traces)];
    
    subplot(2,1,2);
    plot(time_concat, concat_deriv, 'b-', 'LineWidth', 0.8);
    hold on;
    
    % Mark segment boundaries (Critical to see edge artifacts!)
    for k = 1:num_segments
        xline(segment_times(k), 'r--', 'LineWidth', 1);
    end
    
    % Add a zero line for reference
    yline(0, 'k-', 'Alpha', 0.3);
    
    title('Derivative of Concatenated Recording (dF/dt)', 'FontSize', 12);
    xlabel('Time (s)');
    ylabel('Rate of Change');
    grid on; axis tight;
    
    % Add a global title
    sgtitle(sprintf('Concatenated Signal vs. Derivative (%d Files merged)', num_segments));
    
    % ============================================================
    % 🔗 NEW: PEAK DETECTION LOGIC (1 Max Peak Per File)
    % ============================================================
    if exist('Concatenated_Recording', 'var')
        figure('Name', 'Max Peak Per File Detection', 'Position', [200, 200, 1200, 500]);
        
        % 1. Plot the Full Concatenated Trace
        plot(time_concat, concat_traces, 'k-', 'LineWidth', 0.8, ...
             'Color', [0.2 0.2 0.2], 'DisplayName', 'Signal Trace');
        hold on;
        
        % 2. Loop through each file segment to find its local max
        fprintf(' PEAK DETECTION: Finding max peak for each file...\n');
        
        for k = 1:num_segments
            % Get segment boundaries from metadata
            seg_start = concat_metadata.file_segments(k).start_frame;
            seg_end   = concat_metadata.file_segments(k).end_frame;
            
            % Extract the data for just this file
            current_segment_data = concat_traces(seg_start:seg_end);
            
            % Find the single highest point in this segment
            [max_val, rel_idx] = max(current_segment_data);
            
            % Convert relative index to global index
            global_idx = seg_start + rel_idx - 1;
            
            % Get time and value
            peak_time = time_concat(global_idx);
            peak_amp  = concat_traces(global_idx);
            
            % Mark with Red Star
            plot(peak_time, peak_amp, 'r*', 'MarkerSize', 12, 'LineWidth', 1.5, ...
                 'HandleVisibility', 'off'); % Hide from legend to avoid clutter
              
            % Optional: Add text label (File Index) above the star
            text(peak_time, peak_amp + (peak_amp*0.05), sprintf('F%d', k), ...
                 'Color', 'r', 'FontSize', 8, 'HorizontalAlignment', 'center');
              
            fprintf('    - File %d: Max at %.2fs (Amp: %.2f)\n', k, peak_time, peak_amp);
        end
        
        % 3. Draw Segment Boundaries for visual clarity
        for k = 1:num_segments
            xline(segment_times(k), 'b--', 'LineWidth', 0.8, 'HandleVisibility', 'off');
        end
        
        % 4. Formatting
        % Create a dummy plot just to get one "Red Star" entry in the legend
        h = plot(nan, nan, 'r*', 'MarkerSize', 12, 'LineWidth', 1.5, 'DisplayName', 'Max Peak (per file)');
        
        title(sprintf('Trigger Detection: Max Peak per File (%d Files)', num_segments), 'FontSize', 12);
        xlabel('Time (s)', 'FontSize', 11);
        ylabel('ΔF/F (a.u.)', 'FontSize', 11);
        legend([findobj(gca, 'DisplayName', 'Signal Trace'), h], 'Location', 'best');
        grid on; axis tight;
        
        % Expand Y-limits slightly so stars/text aren't cut off
        yl = ylim;
        ylim([yl(1), yl(2) * 1.15]);
        
        hold off;
    end
    
    % ============================================================
    % 🔗 NEW: OVERLAPPING SIGNAL & DERIVATIVE (Single Plot)
    % ============================================================
    if exist('Concatenated_Recording', 'var')
        figure('Name', 'Overlapping Analysis', 'Position', [150, 150, 1200, 600]);
        
        % --- Left Axis: Main Signal & Peaks ---
        yyaxis left;
        p1 = plot(time_concat, concat_traces, '-', 'Color', [0.2 0.2 0.2], ...
             'LineWidth', 1.5, 'DisplayName', 'Signal (Z-Score)');
        hold on;
        ylabel('Signal Amplitude (ΔF/F)', 'FontSize', 12, 'FontWeight', 'bold');
        
        % --- Loop to Find & Mark Max Peaks (Per File) ---
        fprintf('  ★ OVERLAY PLOT: Marking max peaks on Signal axis...\n');
        
        for k = 1:num_segments
            % 1. Identify segment range
            idx_start = concat_metadata.file_segments(k).start_frame;
            idx_end   = concat_metadata.file_segments(k).end_frame;
            
            % 2. Find max in this specific file segment
            segment_data = concat_traces(idx_start:idx_end);
            [max_val, rel_idx] = max(segment_data);
            
            % 3. Convert to global index
            global_idx = idx_start + rel_idx - 1;
            
            % 4. Mark with Red Star (on Left Axis)
            plot(time_concat(global_idx), max_val, 'r*', 'MarkerSize', 12, ...
                 'LineWidth', 2, 'HandleVisibility', 'off'); % Hide individual stars from legend
        end
        
        % Dummy plot for Legend entry for the Red Star
        p2 = plot(nan, nan, 'r*', 'MarkerSize', 12, 'LineWidth', 2, 'DisplayName', 'Max Peak');
        
        % --- Right Axis: Derivative ---
        yyaxis right;
        deriv_trace = [0; diff(concat_traces)]; % Calculate Derivative
        
        % Plot Derivative in Blue (slightly transparent to see signal behind it)
        p3 = plot(time_concat, deriv_trace, '-', 'Color', [0 0.45 0.74, 0.6], ...
             'LineWidth', 1, 'DisplayName', 'Derivative (dF/dt)');
        ylabel('Rate of Change (dF/dt)', 'FontSize', 12, 'FontWeight', 'bold');
        
        % Add a zero line for the derivative
        yline(0, '--', 'Color', [0 0.45 0.74, 0.3], 'HandleVisibility', 'off');
        
        % --- Final Formatting ---
        title(sprintf('Combined Signal & Derivative (%d Files)', num_segments), ...
              'FontSize', 14, 'FontWeight', 'bold');
        xlabel('Time (s)', 'FontSize', 12, 'FontWeight', 'bold');
        
        % Combined Legend
        legend([p1, p2, p3], 'Location', 'best');
        
        grid on; axis tight;
        
        % Set Left Axis color to Black (default is usually blue/orange in yyaxis)
        ax = gca;
        ax.YAxis(1).Color = 'k'; 
        ax.YAxis(2).Color = [0 0.45 0.74]; % Match derivative color
        
        hold off;
    end
    
    % ============================================================
    % 🔗 NEW: SMART TRIGGER DETECTION (Tangent Method)
    % ============================================================
    if exist('Concatenated_Recording', 'var')
        figure('Name', 'Smart Trigger Detection', 'Position', [150, 150, 1200, 700]);
        
        % --- Calculate Derivative Globally First ---
        global_deriv = [0; diff(concat_traces)];
        
        % --- Setup Axes ---
        yyaxis left;
        h_sig = plot(time_concat, concat_traces, '-', 'Color', [0.2 0.2 0.2], ...
             'LineWidth', 1.5, 'DisplayName', 'Signal (Z-Score)');
        hold on;
        ylabel('Signal Amplitude (ΔF/F)', 'FontSize', 12, 'FontWeight', 'bold');
        
        yyaxis right;
        % Plot derivative with high transparency just for context
        h_deriv = plot(time_concat, global_deriv, '-', 'Color', [0 0.45 0.74, 0.3], ...
             'LineWidth', 1, 'DisplayName', 'Derivative (dF/dt)');
        ylabel('Rate of Change', 'FontSize', 12, 'FontWeight', 'bold');
        
        % --- TRIGGER DETECTION LOOP ---
        fprintf('  ★ SMART TRIGGER: Finding Onset via Tangent Projection...\n');
        
        % Parameters
        lookback_window_sec = 0.20; % Look 200ms before peak for the rise
        
        for k = 1:num_segments
            % 1. Get Segment Indices
            idx_start = concat_metadata.file_segments(k).start_frame;
            idx_end   = concat_metadata.file_segments(k).end_frame;
            
            % 2. Find Signal Peak (The Anchor)
            segment_data = concat_traces(idx_start:idx_end);
            [peak_amp, rel_idx_peak] = max(segment_data);
            global_idx_peak = idx_start + rel_idx_peak - 1;
            t_peak = time_concat(global_idx_peak);
            
            % 3. Define Lookback Window (Start of segment to Peak)
            % We don't want to look before the file started
            window_start_idx = max(idx_start, global_idx_peak - round(lookback_window_sec * Fs_concat));
            window_indices = window_start_idx : global_idx_peak;
            
            % 4. Find Max Derivative in this Window (The Slope)
            deriv_segment = global_deriv(window_indices);
            [slope_val, rel_idx_slope] = max(deriv_segment);
            
            if slope_val <= 0
                warning('  ⚠ File %d: No positive rise found before peak.', k);
                continue;
            end
            
            global_idx_slope = window_indices(rel_idx_slope);
            t_slope = time_concat(global_idx_slope);
            amp_at_slope = concat_traces(global_idx_slope);
            
            % 5. Calculate Tangent Intercept (The True Onset)
            % Formula: t_onset = t_slope - (amplitude / slope)
            % Note: We assume baseline is roughly 0 (Z-scored). 
            t_onset = t_slope - (amp_at_slope / (slope_val * Fs_concat)); 
            
            % --- PLOTTING ---
            yyaxis left;
            
            % A. Mark the Peak (Red Star)
            plot(t_peak, peak_amp, 'r*', 'MarkerSize', 10, 'LineWidth', 1.5, 'HandleVisibility', 'off');
            
            % B. Mark the Max Slope Point (Blue Circle)
            plot(t_slope, amp_at_slope, 'bo', 'MarkerSize', 8, 'LineWidth', 1.5, 'HandleVisibility', 'off');
            
            % C. Mark the Calculated Onset (Green Square & Line)
            xline(t_onset, 'g-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
            plot(t_onset, 0, 'gs', 'MarkerSize', 10, 'LineWidth', 2, 'MarkerFaceColor', 'w', 'HandleVisibility', 'off');
            
            % D. Visualize the Tangent Line (Optional visual check)
            % Plot a short line segment to show the tangent slope
            plot([t_onset, t_slope], [0, amp_at_slope], 'g--', 'LineWidth', 1, 'HandleVisibility', 'off');
            fprintf('    - File %d: Peak=%.3fs | MaxSlope=%.3fs | Calc.Onset=%.3fs\n', ...
                    k, t_peak, t_slope, t_onset);
        end
        
        % --- Final Formatting ---
        title('Smart Onset Detection: Peak (Red) → Max Slope (Blue) → Onset (Green)', 'FontSize', 12);
        xlabel('Time (s)');
        
        % Add dummy legend entries
        hold on;
        h1 = plot(nan, nan, 'r*', 'MarkerSize', 10, 'DisplayName', 'Signal Peak');
        h2 = plot(nan, nan, 'bo', 'MarkerSize', 8, 'DisplayName', 'Max Slope Point');
        h3 = plot(nan, nan, 'gs', 'MarkerSize', 10, 'LineWidth', 2, 'DisplayName', 'Calculated Onset');
        
        legend([h_sig, h_deriv, h1, h2, h3], 'Location', 'best');
        grid on; axis tight;
        
        % Fix Colors
        ax = gca;
        ax.YAxis(1).Color = 'k';
        ax.YAxis(2).Color = [0 0.45 0.74];
        
        hold off;
    end
end
%% ======================== SAVE RESULTS ========================
fprintf('========================================\n');
fprintf('Saving results to: %s\n', CONFIG.output_file);
if do_concat && exist('Concatenated_Recording', 'var')
    save(CONFIG.output_file, 'All_Experiments', 'CONFIG', 'Concatenated_Recording');
    fprintf('  ✓ Saved individual files + concatenated recording\n');
else
    save(CONFIG.output_file, 'All_Experiments', 'CONFIG');
    fprintf('  ✓ Saved individual files only\n');
end
% Summary statistics
num_success = sum(~arrayfun(@(x) isfield(x, 'error'), All_Experiments));
num_failed = num_files - num_success;
fprintf('========================================\n');
fprintf('PROCESSING COMPLETE\n');
fprintf('  ✓ Successful: %d/%d\n', num_success, num_files);
if num_failed > 0
    fprintf('  ✗ Failed: %d/%d\n', num_failed, num_files);
end
fprintf('========================================\n');
%% ======================== STEP 3: OVERLAY & TRIGGER INSPECTION ========================
if exist('All_Experiments', 'var') && length(All_Experiments) > 1
    figure('Name', 'Overlay Analysis', 'Position', [100, 100, 1000, 600]);
    hold on;
    colors = parula(length(All_Experiments));
    
    for k = 1:length(All_Experiments)
        if isfield(All_Experiments(k), 'trace') && ~isempty(All_Experiments(k).trace)
            tr = All_Experiments(k).trace;
            % Use the time axis stored in the struct (it exists now!)
            if isfield(All_Experiments(k), 'time_axis')
                t_axis = All_Experiments(k).time_axis;
            else
                t_axis = (0:length(tr)-1) / All_Experiments(k).fs;
            end
            
            plot(t_axis, tr, 'Color', [colors(k, :), 0.6], 'LineWidth', 1.2, ...
                 'DisplayName', All_Experiments(k).filename);
        end
    end
    
    try
        min_len = min(arrayfun(@(x) length(x.trace), All_Experiments));
        trace_matrix = zeros(length(All_Experiments), min_len);
        for k = 1:length(All_Experiments)
             trace_matrix(k, :) = All_Experiments(k).trace(1:min_len);
        end
        avg_trace = mean(trace_matrix, 1);
        t_avg = (0:min_len-1) / All_Experiments(1).fs;
        plot(t_avg, avg_trace, 'k-', 'LineWidth', 3, 'DisplayName', 'AVERAGE (Mean)');
        legend('show', 'Location', 'best');
    catch
        legend('show', 'Location', 'best');
    end
    
    title('Overlay of All Sweeps', 'FontSize', 14);
    xlabel('Time (s)'); ylabel('Z-Score'); grid on; axis tight; hold off;
end