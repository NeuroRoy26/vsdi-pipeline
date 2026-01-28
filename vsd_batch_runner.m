function vsd_batch_runner()
% VSD_BATCH_RUNNER
% Selects multiple HDF5 files and runs vsd_motion_correct.m on them
% using the specific protocol defined below.

    %% 1. Define Your Protocol Here
    % (These match the settings you provided in your snippet)
    config = struct();
    config.DatasetName      = 'image_stack';
    config.OutputFolder     = 'data/batch_output500'; % Change this if needed
    config.ReferenceFrames  = 70:200; 
    
    % Optical Flow settings
    config.OF = struct( ...
        'alpha', 1.0, ...
        'sigma', [2.0, 2.0, 0.2; 1.0, 1.0, 0.1], ... % [Struct(X,Y,T); Func(X,Y,T)]
        'weight', [0.8, 0.2], ...
        'quality_setting', 'quality', ...
        'bin_size', 1, ...
        'buffer_size', 100, ...
        'save_w', true, ...
        'save_meta_info', true, ...
        'verbose', true ...
    );

    %% 2. Select Files
    % 'MultiSelect', 'on' allows holding Ctrl/Shift to pick multiple files
    [files, path] = uigetfile('*.h5;*.hdf5', ...
                              'Select VSD files to process', ...
                              'MultiSelect', 'on');
                          
    if isequal(files, 0)
        disp('Batch processing cancelled.');
        return;
    end
    
    % Ensure 'files' is always a cell array (even if only 1 file selected)
    if ischar(files)
        files = {files};
    end
    
    total_files = length(files);
    fprintf('Batch job started. %d file(s) selected.\n', total_files);
    fprintf('Output folder: %s\n\n', config.OutputFolder);

    %% 3. Iterate and Process
    for i = 1:total_files
        filename = files{i};
        full_path = fullfile(path, filename);
        
        fprintf('--------------------------------------------------\n');
        fprintf('Processing file %d/%d: %s\n', i, total_files, filename);
        fprintf('--------------------------------------------------\n');
        
        try
            % Call your main motion correction function
            vsd_motion_correct(full_path, ...
                'DatasetName',      config.DatasetName, ...
                'OutputFolder',     config.OutputFolder, ...
                'ReferenceFrames',  config.ReferenceFrames, ...
                'OF',               config.OF);
            
            fprintf('SUCCESS: %s completed.\n\n', filename);
            
        catch ME
            % If one fails, print error in red but continue to next file
            fprintf(2, 'FAILED: %s encountered an error.\n', filename);
            fprintf(2, 'Error Message: %s\n\n', ME.message);
            % Optional: Save error log to disk
        end
    end
    
    fprintf('--------------------------------------------------\n');
    fprintf('Batch processing finished.\n');
end