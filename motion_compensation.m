%% Improved VSD Motion Correction Script
clear; clc; close all;
% 
% % Add Flow-Registration toolbox to path
% addpath('C:/flow_registration-main/');

%% Configuration
input_h5_path = 'converted__1000/led_E1B1.h5';  % change filename in line161
dataset_name = 'image_stack';
output_folder = 'data/motion_corrected';
reference_frames = 80:200;  % Middle portion of no-stimulus condition

% Create output folder
if ~isfolder(output_folder)
    mkdir(output_folder)
end

%% Load and restructure data for Flow-Registration
fprintf('Loading and restructuring HDF5 data...\n');
data = h5read(input_h5_path, ['/' dataset_name]);

% Ensure correct orientation [height, width, frames]
if size(data, 1) == 1500
    data = permute(data, [2, 3, 1]);
end

[height, width, total_frames] = size(data);

% Separate channels
structural_frames = data(:, :, 1:2:end); % Even frames (high contrast)
functional_frames = data(:, :, 2:2:end); % Odd frames (low contrast VSD)

% Create temporary HDF5 file with proper structure for Flow-Registration
temp_file = fullfile(output_folder, 'temp_multichannel.h5');
if exist(temp_file, 'file'), delete(temp_file); end

% The HDF_file_reader expects datasets named 'ch1', 'ch2', etc. in 3D format [height, width, time]
fprintf('Creating temporary HDF5 file with proper structure...\n');

% Create datasets for each channel
h5create(temp_file, '/ch1', size(structural_frames), 'Datatype', class(structural_frames));
h5write(temp_file, '/ch1', structural_frames);

h5create(temp_file, '/ch2', size(functional_frames), 'Datatype', class(functional_frames));
h5write(temp_file, '/ch2', functional_frames);

%% Configure Flow-Registration options
try
    options = OF_options(...
        'input_file', temp_file, ...
        'output_path', output_folder, ...
        'output_format', 'HDF5', ...
        'alpha', 1.6, ... % Smoothness parameter
        'sigma', [1.5, 1.5, 0.1; 1.5, 1.5, 0.1], ... % Per-channel smoothing
        'weight', [0.8, 0.2], ... % Heavily weight structural channel
        'quality_setting', 'quality', ...
        'bin_size', 1, ...
        'buffer_size', 100, ...
        'reference_frames', ceil(reference_frames/2), ... % Adjust for structural channel indexing
        'save_w', true, ... % Save displacement fields
        'save_meta_info', true, ...
        'verbose', true); % Enable verbose for debugging
        
    fprintf('Flow-Registration options configured successfully.\n');
    
catch ME
    fprintf('Error creating OF_options: %s\n', ME.message);
    return;
end

%% Test file reader creation
try
    fprintf('Testing file reader creation...\n');
    video_reader = options.get_video_file_reader();
    fprintf('File reader created successfully. Properties:\n');
    fprintf('  Channels: %d\n', video_reader.n_channels);
    fprintf('  Frames: %d\n', video_reader.frame_count);
    fprintf('  Dimensions: %dx%d\n', video_reader.get_height(), video_reader.get_width());
    fprintf('  Data type: %s\n', video_reader.mat_data_type);
    
catch ME
    fprintf('Error creating file reader: %s\n', ME.message);
    fprintf('Stack trace:\n');
    for i = 1:length(ME.stack)
        fprintf('  %s at line %d\n', ME.stack(i).name, ME.stack(i).line);
    end
    return;
end

%% Run Flow-Registration
fprintf('Running Flow-Registration motion correction...\n');

try
    % Run the main compensation function
    compensate_recording(options);
    fprintf('Motion correction completed successfully!\n');
    
catch ME
    fprintf('Error during motion correction: %s\n', ME.message);
    fprintf('Stack trace:\n');
    for i = 1:length(ME.stack)
        fprintf('  %s at line %d\n', ME.stack(i).name, ME.stack(i).line);
    end
    
    % Try alternative approach using direct compensation
    fprintf('\nTrying alternative approach with compensate_inplace...\n');
    try
        % Read reference frames from structural channel
        ref_indices = ceil(reference_frames/2);
        ref_indices = ref_indices(ref_indices <= size(structural_frames, 3));
        reference_frame = mean(double(structural_frames(:, :, ref_indices)), 3);
        
        % Apply motion correction
        fprintf('Correcting structural frames...\n');
        structural_corrected = compensate_inplace(double(structural_frames), reference_frame, options);
        
        fprintf('Correcting functional frames...\n');
        functional_corrected = compensate_inplace(double(functional_frames), reference_frame, options);
        
        % Save results manually
        output_file = fullfile(output_folder, 'vsd_corrected_manual.h5');
        if exist(output_file, 'file'), delete(output_file); end
        
        h5create(output_file, '/structural_corrected', size(structural_corrected));
        h5write(output_file, '/structural_corrected', structural_corrected);
        
        h5create(output_file, '/functional_corrected', size(functional_corrected));
        h5write(output_file, '/functional_corrected', functional_corrected);
        
        fprintf('Alternative approach completed successfully!\n');
        
    catch ME2
        fprintf('Alternative approach also failed: %s\n', ME2.message);
        return;
    end
end

%% Process results if main approach worked
if exist(fullfile(output_folder, 'ch1.hdf5'), 'file') || exist(fullfile(output_folder, 'compensated.hdf5'), 'file')
    try
        fprintf('Processing Flow-Registration results...\n');
        
        % Check which output file exists
        if exist(fullfile(output_folder, 'ch1.hdf5'), 'file')
            % Multi-file output
            structural_corrected = h5read(fullfile(output_folder, 'ch1.hdf5'), '/ch1');
            functional_corrected = h5read(fullfile(output_folder, 'ch2.hdf5'), '/ch2');
        else
            % Single file output - need to check structure
            info = h5info(fullfile(output_folder, 'compensated.hdf5'));
            dataset_names = {info.Datasets.Name};
            if any(strcmp(dataset_names, 'ch1'))
                structural_corrected = h5read(fullfile(output_folder, 'compensated.hdf5'), '/ch1');
                functional_corrected = h5read(fullfile(output_folder, 'compensated.hdf5'), '/ch2');
            else
                fprintf('Unexpected output structure. Available datasets: %s\n', strjoin(dataset_names, ', '));
            end
        end
        
        % Save final results
        output_file = fullfile(output_folder, '1000_led_E1B1_vsd_corrected.h5');
        if exist(output_file, 'file'), delete(output_file); end
        
        h5create(output_file, '/structural', size(structural_corrected));
        h5write(output_file, '/structural', structural_corrected);
        
        h5create(output_file, '/functional', size(functional_corrected));
        h5write(output_file, '/functional', functional_corrected);
        
        % % Reconstruct interleaved data
        % interleaved_corrected = zeros(height, width, total_frames);
        % interleaved_corrected(:, :, 2:2:end) = structural_corrected;
        % interleaved_corrected(:, :, 1:2:end) = functional_corrected;
        % 
        % h5create(output_file, '/interleaved_corrected', size(interleaved_corrected));
        % h5write(output_file, '/interleaved_corrected', interleaved_corrected);
        
        fprintf('Results saved to: %s\n', output_file);
        
    catch ME
        fprintf('Error processing results: %s\n', ME.message);
    end
end

%% Cleanup and summary
if exist(temp_file, 'file')
    delete(temp_file);
    fprintf('Temporary files cleaned up.\n');
end

%% Display motion statistics if available
if exist(fullfile(output_folder, 'statistics.mat'), 'file')
    try
        stats = load(fullfile(output_folder, 'statistics.mat'));
        fprintf('\nMotion correction statistics:\n');
        fprintf('  Mean displacement: %.2f ± %.2f pixels\n', mean(stats.mean_disp), std(stats.mean_disp));
        fprintf('  Max displacement: %.2f pixels\n', max(stats.max_disp));
        if isfield(stats, 'mean_div')
            fprintf('  Mean divergence: %.4f ± %.4f\n', mean(stats.mean_div), std(stats.mean_div));
        end
        if isfield(stats, 'mean_translation')
            fprintf('  Mean translation: %.2f ± %.2f pixels\n', mean(stats.mean_translation), std(stats.mean_translation));
        end
    catch
        fprintf('Could not load motion statistics.\n');
    end
end

fprintf('\nVSD motion correction script completed!\n');