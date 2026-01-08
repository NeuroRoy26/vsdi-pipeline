clc; clear; close all;

% -----------------------------------------------------------------
%% 1. UI: Select Files
fprintf('Opening file selector...\n');
% Allow multi-select
[file_list, path_name] = uigetfile('*.h5', ...
    'Select H5 Files to Process (Ctrl+Click for multiple)', ...
    'MultiSelect', 'on');

if isequal(file_list, 0)
    disp('User canceled file selection.');
    return;
end

% Ensure file_list is a cell array (handles single file selection)
if ischar(file_list)
    file_list = {file_list}; 
end

num_files = length(file_list);

% -----------------------------------------------------------------
%% 2. Processing Parameters
p.Bin = 1;
p.Sigma = 1;
p.MedianWin = 3;
p.BaselineIdx = 38:100;
p.Dataset = '/functional'; 

fprintf('Batch processing started for %d files...\n', num_files);
hWait = waitbar(0, 'Initializing Batch Processing...');

% -----------------------------------------------------------------
%% 3. Loop Through Each File Individually
for i = 1:num_files
    
    % --- Get File Info ---
    input_filename = file_list{i};
    full_input_path = fullfile(path_name, input_filename);
    
    % Generate Output Filename (InputName_dff.h5)
    [~, name_only, ~] = fileparts(input_filename);
    output_filename = [name_only, '_dff.h5'];
    full_output_path = fullfile(path_name, output_filename);
    
    % Update UI
    waitbar((i-1)/num_files, hWait, sprintf('Processing %d/%d: %s', i, num_files, input_filename));
    fprintf('(%d/%d) Processing: %s  -->  Saving as: %s\n', i, num_files, input_filename, output_filename);
    
    try
        % ----------------------------------------
        % A. Load Data
        % ----------------------------------------
        F = double(h5read(full_input_path, p.Dataset)); 
        [H, W, T] = size(F);
        
        % ----------------------------------------
        % B. Calculate dF/F
        % ----------------------------------------
        % Check baseline indices
        valid_base_idx = p.BaselineIdx(p.BaselineIdx>=1 & p.BaselineIdx<=T);
        if isempty(valid_base_idx)
             warning('Baseline indices out of range for %s. Skipping.', input_filename);
             continue;
        end
        
        F0 = mean(F(:,:,valid_base_idx), 3); 
        F0(F0==0) = eps;
        dff_raw = (F - F0) ./ F0;
        
        % ----------------------------------------
        % C. Binning
        % ----------------------------------------
        nOut = floor(T / p.Bin);
        if p.Bin > 1
            dff_raw_reshaped = dff_raw(:,:,1:nOut*p.Bin);
            dff_binned = squeeze(mean(reshape(dff_raw_reshaped, H, W, p.Bin, nOut), 3)); 
        else
            dff_binned = dff_raw;
        end
        
        % ----------------------------------------
        % D. Filtering (Median & Gaussian)
        % ----------------------------------------
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
        
        % ----------------------------------------
        % E. Save Result Immediately
        % ----------------------------------------
        if exist(full_output_path, 'file')
            delete(full_output_path); % Overwrite if exists
        end
        
        % Save Functional Data
        h5create(full_output_path, '/functional_dff', size(dff_processed), 'DataType', 'double');
        h5write(full_output_path, '/functional_dff', dff_processed);
        
        % Copy Structural Data (if available)
        try
            structural_data = h5read(full_input_path, '/structural');
            h5create(full_output_path, '/structural', size(structural_data), 'DataType', 'double');
            h5write(full_output_path, '/structural', structural_data);
        catch
            % If structural doesn't exist, just ignore it
        end
        
    catch ME
        fprintf('  [ERROR] Failed to process %s: %s\n', input_filename, ME.message);
    end
end

delete(hWait);
fprintf('\n--- Batch Processing Complete ---\n');
msgbox(sprintf('Processed %d files successfully.', num_files), 'Done');