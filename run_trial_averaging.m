clc; clear; close all;
% -----------------------------------------------------------------
%                   run_trial_averaging_v2.m
% -----------------------------------------------------------------
%% 1. Define Files and Parameters
h5_files_to_average = { 
    'data/motion_compensated/led_E0B0_vsd_corrected.h5',  
     'data/motion_compensated/led_E0B1_vsd_corrected.h5',  
     'data/motion_compensated/led_E0B2_vsd_corrected.h5',  
     'data/motion_compensated/led_E0B3_vsd_corrected.h5',  
};
num_trials = length(h5_files_to_average);

% --- Processing Parameters ---
p.Bin = 5;
p.Sigma = 1;
p.MedianWin = 3;
p.BaselineIdx = 1:100;
p.Dataset = '/functional';

%% 2. Initialize Accumulator
sum_dff_movie = 0; 
trials_processed_count = 0;
fprintf('Starting trial averaging (v2) for %d trials...\n', num_trials);

%% 3. Loop Through Each Trial and Process
for i = 1:num_trials
    
    current_file = h5_files_to_average{i};
    fprintf('Processing Trial %d/%d: %s\n', i, num_trials, current_file);
    
    try
        % 3a. Load Raw Data
        F = double(h5read(current_file, p.Dataset)); 
        [H, W, T] = size(F); % T will be 750
        
        % 3b. Calculate Raw Baseline (F0)
        pre = p.BaselineIdx(p.BaselineIdx>=1 & p.BaselineIdx<=T);
        F0 = mean(F(:,:,pre), 3); 
        F0(F0==0) = eps;
             
        % 3c. Calculate RAW dF/F (using all 750 frames)
        % This is the correct order: calculate dF/F first.
        dff_raw = (F - F0) ./ F0;
        
        % 3d. Temporal Binning (on the dF/F movie)
        nOut = floor(T / p.Bin); % e.g., 750 / 5 = 150 frames
        if nOut == 0; error('Bin size is too large for this data.'); end
        dff_raw_reshaped = dff_raw(:,:,1:nOut*p.Bin);
        dff_binned = squeeze(mean(reshape(dff_raw_reshaped, H, W, p.Bin, nOut), 3)); 
        
        %NOTE squeeze after mean was necessary to preserve 3D array shape,
        %otherwise it became 4D array and screwed up the downprocessing
        %steps
        
        % 3e. Filtering (on the binned dF/F movie)
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
        
        % 3f. Add to Accumulator
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

%% 4. Calculate the Average and Save
if trials_processed_count > 0
    average_dff_movie = sum_dff_movie / trials_processed_count;
    fprintf('\nAveraging complete. Total trials included: %d\n', trials_processed_count);
    
    % --- Save the final averaged movie to a NEW HDF5 file ---
    output_h5_file = 'data/averaged_movie_E0B0-B3.h5';
    dataset_name = '/functional_dff';
    
    h5create(output_h5_file, dataset_name, size(average_dff_movie), 'DataType', 'double');
    h5write(output_h5_file, dataset_name, average_dff_movie);
    
    fprintf('Saved averaged movie to %s\n', output_h5_file);
    
    % 5. (Optional) Copy the structural data
    try
        structural_data = h5read(h5_files_to_average{1}, '/structural');
        h5create(output_h5_file, '/structural', size(structural_data), 'DataType', 'double');
        h5write(output_h5_file, '/structural', structural_data);
        fprintf('Copied structural data to new HDF5 file.\n');
    catch
        warning('Could not copy structural data.');
    end
    
    fprintf('\n--- All done! ---\n');
    
else
    fprintf('\nNo trials were processed successfully. No output file created.\n');
end