clc; clear; close all;
% -----------------------------------------------------------------
%                   run_trial_averaging_v2_autoresize.m
% -----------------------------------------------------------------
%% 1. Define Files and Parameters
%= UI file selector
fprintf('=== Select H5 Files to Average ===\n');
fprintf('You can select multiple files. Press Cancel when done.\n\n');
h5_files_to_average = {};
file_count = 0;
[fName, fPath] = uigetfile('*.h5', 'Select H5 File(s) to Average (or Cancel when done)', 'MultiSelect', 'on');
if isequal(fName, 0)
    fprintf('No files selected. Exiting.\n');
    return;
end
if ischar(fName)
    h5_files_to_average{1} = fullfile(fPath, fName);
    file_count = 1;
else
    file_count = length(fName);
    for i = 1:file_count
        h5_files_to_average{i} = fullfile(fPath, fName{i});
    end
end
num_trials = length(h5_files_to_average);
fprintf('\n--- Selected Files (%d total) ---\n', num_trials);
for i = 1:num_trials
    [~, name, ext] = fileparts(h5_files_to_average{i});
    fprintf('  %d. %s%s\n', i, name, ext);
end
fprintf('\n');
%=

% --- Processing Parameters ---
p.Bin = 1;
p.Sigma = 1;
p.MedianWin = 3;
p.BaselineIdx = 38:100;
p.Dataset = '/functional';

%% 2. Determine Target Dimensions (smallest file)
fprintf('Scanning file dimensions...\n');
min_H = inf;
min_W = inf;
min_T = inf;

for i = 1:num_trials
    try
        info = h5info(h5_files_to_average{i}, p.Dataset);
        dims = info.Dataspace.Size; % [H, W, T]
        min_H = min(min_H, dims(1));
        min_W = min(min_W, dims(2));
        min_T = min(min_T, dims(3));
        fprintf('  File %d: %dx%dx%d\n', i, dims(1), dims(2), dims(3));
    catch ME
        warning('Could not read dimensions from file %d: %s', i, ME.message);
    end
end

fprintf('\nTarget dimensions (smallest): %dx%dx%d\n', min_H, min_W, min_T);
fprintf('All files will be resized to match these dimensions.\n\n');

%% 3. Initialize Accumulator
sum_dff_movie = 0; 
trials_processed_count = 0;
fprintf('Starting trial averaging with auto-resize for %d trials...\n', num_trials);

%% 4. Loop Through Each Trial and Process
for i = 1:num_trials
    
    current_file = h5_files_to_average{i};
    fprintf('Processing Trial %d/%d: %s\n', i, num_trials, current_file);
    
    try
        % 4a. Load Raw Data
        F = double(h5read(current_file, p.Dataset)); 
        [H, W, T] = size(F);
        
        % 4b. RESIZE to target dimensions if necessary
        if H ~= min_H || W ~= min_W || T ~= min_T
            fprintf('  -> Resizing from %dx%dx%d to %dx%dx%d\n', H, W, T, min_H, min_W, min_T);
            
            % Spatial resize (crop or pad to center)
            F_resized = zeros(min_H, min_W, T);
            
            % Calculate crop/pad indices
            h_start = max(1, floor((H - min_H)/2) + 1);
            h_end = h_start + min_H - 1;
            w_start = max(1, floor((W - min_W)/2) + 1);
            w_end = w_start + min_W - 1;
            
            % Handle cases where target is larger (pad) or smaller (crop)
            if H >= min_H && W >= min_W
                % Crop (take center region)
                F_resized = F(h_start:h_end, w_start:w_end, :);
            else
                % This would require padding - for now we'll crop what we can
                h_out_start = max(1, floor((min_H - H)/2) + 1);
                w_out_start = max(1, floor((min_W - W)/2) + 1);
                h_copy = min(H, min_H);
                w_copy = min(W, min_W);
                F_resized(h_out_start:(h_out_start+h_copy-1), w_out_start:(w_out_start+w_copy-1), :) = ...
                    F(1:h_copy, 1:w_copy, :);
            end
            
            % Temporal resize (truncate to shortest)
            if T > min_T
                F = F_resized(:, :, 1:min_T);
            else
                F = F_resized;
            end
            T = min_T;
        end
        
        % 4c. Calculate Raw Baseline (F0)
        pre = p.BaselineIdx(p.BaselineIdx>=1 & p.BaselineIdx<=T);
        F0 = mean(F(:,:,pre), 3); 
        F0(F0==0) = eps;
             
        % 4d. Calculate RAW dF/F (using all frames)
        dff_raw = (F - F0) ./ F0;
        
        % 4e. Temporal Binning (on the dF/F movie)
        nOut = floor(T / p.Bin);
        if nOut == 0; error('Bin size is too large for this data.'); end
        dff_raw_reshaped = dff_raw(:,:,1:nOut*p.Bin);
        dff_binned = squeeze(mean(reshape(dff_raw_reshaped, min_H, min_W, p.Bin, nOut), 3)); 
        
        % 4f. Filtering (on the binned dF/F movie)
        dff_processed = dff_binned;
        
        % Median Filter
        if p.MedianWin >= 3 && mod(p.MedianWin,2)==1
            for t = 1:nOut
                frame = dff_processed(:,:,t);
                nanmask = isnan(frame);
                frame(nanmask) = 0;
                frame = medfilt2(frame, [p.MedianWin p.MedianWin], 'symmetric');
                frame(nanmask) = NaN;
                dff_processed(:,:,t) = frame;
            end
        end
        
        % Gaussian Filter
        if p.Sigma > 0
            fsz = max(3, 2*ceil(3*p.Sigma)+1);
            for t = 1:nOut
                dff_processed(:,:,t) = imgaussfilt(dff_processed(:,:,t), p.Sigma, 'FilterSize', fsz);
            end
        end
        
        % 4g. Add to Accumulator
        if i == 1
            sum_dff_movie = zeros(size(dff_processed), 'double');
        end
        
        % Add this trial's *processed* dF/F movie to the sum
        sum_dff_movie = sum_dff_movie + dff_processed;
        trials_processed_count = trials_processed_count + 1;
        
    catch ME
        warning('Failed to process file %s. Error: %s. SKIPPING THIS TRIAL.', current_file, ME.message);
    end
end

%% 5. Calculate the Average and Save
if trials_processed_count > 0
    average_dff_movie = sum_dff_movie / trials_processed_count;
    fprintf('\nAveraging complete. Total trials included: %d\n', trials_processed_count);
    
    % --- Save the final averaged movie to a NEW HDF5 file ---
    output_h5_file = 'data/preprocessing/led_averaged_E1_1000.h5';
    
    dataset_name = '/functional_dff';
    
    h5create(output_h5_file, dataset_name, size(average_dff_movie), 'DataType', 'double');
    h5write(output_h5_file, dataset_name, average_dff_movie);
    
    fprintf('Saved averaged movie to %s\n', output_h5_file);
    
    % 6. (Optional) Copy the structural data
    try
        structural_data = h5read(h5_files_to_average{1}, '/structural');
        % Resize structural data to match if needed
        [sH, sW] = size(structural_data);
        if sH ~= min_H || sW ~= min_W
            fprintf('Resizing structural data from %dx%d to %dx%d\n', sH, sW, min_H, min_W);
            if sH >= min_H && sW >= min_W
                h_start = floor((sH - min_H)/2) + 1;
                w_start = floor((sW - min_W)/2) + 1;
                structural_data = structural_data(h_start:(h_start+min_H-1), w_start:(w_start+min_W-1));
            end
        end
        h5create(output_h5_file, '/structural', size(structural_data), 'DataType', 'double');
        h5write(output_h5_file, '/structural', structural_data);
        fprintf('Copied structural data to new HDF5 file.\n');
    catch
        warning('Could not copy structural data.');
    end
    
    fprintf('\n--- All done! ---\n');
    fprintf('Final output dimensions: %dx%dx%d\n', size(average_dff_movie));
    
else
    fprintf('\nNo trials were processed successfully. No output file created.\n');
end