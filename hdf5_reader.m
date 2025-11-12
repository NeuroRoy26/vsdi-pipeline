%% Dataset Parameter Configuration Script
% Run this first to understand data structure and set appropriate
% parameters for Flow Registration

clc; clear;

%% Examine HDF5 file structure
input_h5_path = 'converted__1000/led_E1B1.h5';
dataset_name = 'image_stack';     
fprintf('=== EXAMINING HDF5 FILE STRUCTURE ===\n');

if ~exist(input_h5_path, 'file')
    error('File not found: %s\nPlease update input_h5_path variable', input_h5_path);
end

file_info = h5info(input_h5_path);
fprintf('File: %s\n', input_h5_path);
fprintf('Available datasets:\n');
for i = 1:length(file_info.Datasets)
    fprintf('  - %s: %s\n', file_info.Datasets(i).Name, mat2str(file_info.Datasets(i).Dataspace.Size));
end

try
    data_info = h5info(input_h5_path, ['/' dataset_name]);
    data_size = data_info.Dataspace.Size;
    fprintf('\nSelected dataset "%s" dimensions: %s\n', dataset_name, mat2str(data_size));
catch
    error('Dataset "%s" not found. Available datasets listed above.', dataset_name);
end

%% understand data organization
fprintf('\n=== ANALYZING DATA ORGANIZATION ===\n');

% first few frames to analyze
if length(data_size) == 3
    if data_size(3) == 1500  % Frames are third dimension
        sample_data = h5read(input_h5_path, ['/' dataset_name], [1, 1, 1], [data_size(1), data_size(2), data_size(3)]);
        fprintf('Data format: [height=%d, width=%d, frames=%d]\n', data_size(1), data_size(2), data_size(3));
        height = data_size(1);
        width = data_size(2);
        total_frames = data_size(3);
    % elseif data_size(1) == 1500  % Frames are first dimension
    %     sample_data = h5read(input_h5_path, ['/' dataset_name], [1, 1, 1], [min(10, data_size(1)), data_size(2), data_size(3)]);
    %     sample_data = permute(sample_data, [2, 3, 1]); % Reorder to [height, width, frames]
    %     fprintf('Data format: [frames=%d, height=%d, width=%d] - will be reordered\n', data_size(1), data_size(2), data_size(3));
    %     height = data_size(2);
    %     width = data_size(3);
    %     total_frames = data_size(1);
    else
        error('Cannot determine frame dimension. Please check your data structure.');
    end
else
    error('Expected 3D data, got %dD', length(data_size));
end

%% interleaved pattern
fprintf('\n=== VERIFYING INTERLEAVED PATTERN ===\n');

structural_sample = double(sample_data(:, :, 1:2:end));
functional_sample = double(sample_data(:, :, 2:2:end));

structural_contrast = std(structural_sample(:));
functional_contrast = std(functional_sample(:));
contrast_ratio = structural_contrast / functional_contrast;

fprintf('Structural frames (even) contrast std: %.2f\n', structural_contrast);
fprintf('Functional frames (odd) contrast std: %.2f\n', functional_contrast);
fprintf('Contrast ratio (structural/functional): %.2f\n', contrast_ratio);

if contrast_ratio > 1.5
    fprintf(' Pattern confirmed: Structural frames have higher contrast\n');
else
    warning(' Contrast ratio is low. You may need to swap odd/even assignment or check your data');
end

%% show first 10 frames from each set
figure;
for i = 1:10
    subplot(2,10,i); 
    imshow(structural_sample(:,:,i), []); 
    title(sprintf('Struct Even %d', i));

    subplot(2,10,i+10); 
    imshow(functional_sample(:,:,i), []); 
    title(sprintf('Func Odd %d', i));
end

%% parameters that can be used
fprintf('\n=== RECOMMENDED PARAMETERS ===\n');

frame_rate = 500.67; 
structural_frame_rate = frame_rate / 2; % Since interleaved

% Reference frames recommendation
stable_duration = total_frames / frame_rate; % seconds of stable recording to use as reference
ref_frame_count = stable_duration * structural_frame_rate;
ref_start = round(total_frames * 0.1 / 2); % Start at 10% into structural frames
ref_end = ref_start + ref_frame_count - 1;

fprintf('\nDATA DIMENSIONS:\n');
fprintf('height = %d;\n', height);
fprintf('width = %d;\n', width);
fprintf('total_frames = %d;\n', total_frames);
fprintf('structural_frames = %d;\n', total_frames/2);
fprintf('functional_frames = %d;\n', total_frames/2);

fprintf('\nRECOMMENDED REFERENCE FRAMES:\n');
fprintf('reference_frames = %d:%d; %% Frames %d-%d of structural channel\n', ref_start, ref_end, ref_start, ref_end);

% Flow-Registration parameters based on contrast
if contrast_ratio > 3
    alpha_rec = 1.0; % Lower smoothing for high contrast
    sigma_rec = [1.0, 1.0, 0.1];
elseif contrast_ratio > 2
    alpha_rec = 1.5; % Medium smoothing
    sigma_rec = [1.5, 1.5, 0.1];
else
    alpha_rec = 2.5; % Higher smoothing for lower contrast
    sigma_rec = [2.0, 2.0, 0.2];
end

fprintf('\nFLOW-REGISTRATION PARAMETERS:\n');
fprintf('alpha = %.1f; %% Smoothness parameter\n', alpha_rec);
fprintf('sigma = [%.1f, %.1f, %.1f]; %% Gaussian kernel [x, y, t]\n', sigma_rec);

% Buffer size based on available memory (rough estimate)
memory_gb = 8; % CHANGE THIS to your available RAM in GB
frame_size_mb = height * width * 2 / (1024^2); % Assuming 16-bit data
buffer_size_rec = min(100, floor(memory_gb * 200 / frame_size_mb)); % Conservative estimate

fprintf('\nMEMORY MANAGEMENT:\n');
fprintf('buffer_size = %d; %% Estimated based on %.1f MB per frame\n', buffer_size_rec, frame_size_mb);

%% sample frames
fprintf('\n=== VISUAL VERIFICATION ===\n');
fprintf('Displaying sample frames for verification...\n');

figure('Position', [100, 100, 1200, 400]);

% Display first structural frame
subplot(1, 3, 1);
imshow(structural_sample(:, :, 1), []);
title('Structural Frame (Odd #1)');
colorbar;

% Display first functional frame  
subplot(1, 3, 2);
imshow(functional_sample(:, :, 1), []);
title('Functional Frame (Even #2)');
colorbar;

% Display difference to highlight motion
if size(structural_sample, 3) >= 2
    subplot(1, 3, 3);
    diff_frame = abs(double(structural_sample(:, :, 1)) - double(structural_sample(:, :, 2)));
    imshow(diff_frame, []);
    title('Difference: Structural Frames 1-2');
    colorbar;
end

%% Generate configuration
fprintf('\n=== CONFIGURATION CODE FOR MAIN SCRIPT ===\n');
fprintf('%% Copy these parameters to your main motion correction script:\n\n');

fprintf('%% File paths\n');
fprintf('input_h5_path = ''%s'';\n', input_h5_path);
fprintf('dataset_name = ''%s'';\n', dataset_name);
fprintf('output_folder = ''vsd_motion_corrected'';\n\n');

fprintf('%% Data dimensions (verify these match your data)\n');
fprintf('expected_height = %d;\n', height);
fprintf('expected_width = %d;\n', width);
fprintf('expected_total_frames = %d;\n', total_frames);
fprintf('\n');

fprintf('%% Reference frames for motion estimation\n');
fprintf('reference_frames = %d:%d; %% Adjust based on your stable recording period\n\n', ref_start, ref_end);

fprintf('%% Flow-Registration parameters\n');
fprintf('alpha = %.1f; %% Smoothness (higher = smoother motion fields)\n', alpha_rec);
fprintf('sigma = [%.1f, %.1f, %.1f]; %% Gaussian smoothing [spatial_x, spatial_y, temporal]\n', sigma_rec);
fprintf('buffer_size = %d; %% Memory management\n', buffer_size_rec);

fprintf('\n%% Data loading configuration\n');
if data_size(1) == 1500
    fprintf('%% Your data has frames in first dimension - will be reordered\n');
    fprintf('data_needs_permute = true;\n');
else
    fprintf('%% Your data has frames in third dimension - no reordering needed\n');
    fprintf('data_needs_permute = false;\n');
end

%% Validation
fprintf('\n=== VALIDATION CHECKLIST ===\n');
fprintf('Before running motion correction, verify:\n');
fprintf('1. ✓ File path and dataset name are correct\n');
fprintf('2. ✓ Interleaved pattern is confirmed (contrast ratio: %.2f)\n', contrast_ratio);
fprintf('3. ⚠ Reference frames %d:%d contain stable, motion-free periods\n', ref_start, ref_end);
fprintf('4. ⚠ Frame rate assumption (%.1f Hz) is correct for your acquisition\n', frame_rate);
fprintf('5. ⚠ Available memory (%.1f GB assumed) can handle buffer size %d\n', memory_gb, buffer_size_rec);

if contrast_ratio < 1.5
    fprintf('\n⚠ WARNING: Low contrast ratio detected!\n');
    fprintf('  - Consider swapping structural/functional assignment\n');
    fprintf('  - Or verify your interleaved acquisition pattern\n');
end

fprintf('\nConfiguration analysis complete!\n');