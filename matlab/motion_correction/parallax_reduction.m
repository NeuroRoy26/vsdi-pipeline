%% Pyramid-Based Residual Motion Correction for VSD Dual Illumination
% parallax_reduction.m
% Based on the Laplacian pyramid approach from Flotho et al. (2017)
% Adapted for slow gaussian dual illumination VSD imaging setup

clear; clc; close all;

%% Configuration
input_h5_path = 'data/motion_corrected/1000_led_E1B1_vsd_corrected.h5';  % Output from previous script motion_compensation.m
output_folder = 'data/parallax_corrected';
reference_frames = 80:200;  % Middle portion of no-stimulus condition

% Pyramid parameters (based on the paper)
max_pyramid_levels = 35;
eta = 0.9;  % Scaling factor between pyramid levels
alpha_values = [0.1, 0.5, 1.0, 2.0];  % Different smoothness weights for different frequencies

% Create output folder
if ~isfolder(output_folder)
    mkdir(output_folder)
end

%% Load motion-corrected data
fprintf('Loading motion-corrected VSD data...\n');

try
    structural_data = h5read(input_h5_path, '/structural');
    functional_data = h5read(input_h5_path, '/functional');
    fprintf('Successfully loaded structural and functional channels.\n');
catch ME
    fprintf('Error loading data: %s\n', ME.message);
    fprintf('Please ensure the motion correction script has been run first.\n');
    return;
end

[height, width, n_frames_struct] = size(structural_data);
[~, ~, n_frames_func] = size(functional_data);

fprintf('Data dimensions: %dx%d, Structural: %d frames, Functional: %d frames\n', ...
    height, width, n_frames_struct, n_frames_func);

%% Create reference frames for both channels
fprintf('Creating reference frames...\n');

% Adjust reference frame indices for each channel
ref_indices_struct = reference_frames;
ref_indices_struct = ref_indices_struct(ref_indices_struct <= n_frames_struct);

ref_indices_func = reference_frames;
ref_indices_func = ref_indices_func(ref_indices_func <= n_frames_func);

% Create reference frames
ref_structural = mean(double(structural_data(:, :, ref_indices_struct)), 3);
ref_functional = mean(double(functional_data(:, :, ref_indices_func)), 3);

%% Pyramid-Based Motion Correction Function
function corrected_frame = pyramid_motion_correction(frame, reference, max_levels, eta, alpha_vals)
    % Convert to double for processing
    frame = double(frame);
    reference = double(reference);
    
    % Determine actual number of levels based on image size
    min_size = min(size(frame));
    actual_levels = min(max_levels, floor(log(min_size/8) / log(1/eta)));
    
    % Initialize corrected frame with the coarsest level
    corrected_frame = zeros(size(frame));
    
    % Process each pyramid level from coarse to fine
    for level = actual_levels:-1:0
        % Calculate sigma for current level
        sigma = 0.5 * eta^(-level);
        
        % Create Gaussian kernels
        kernel_size = ceil(6 * sigma) | 1;  % Ensure odd size
        [X, Y] = meshgrid(-floor(kernel_size/2):floor(kernel_size/2));
        gaussian_kernel = exp(-(X.^2 + Y.^2) / (2 * sigma^2));
        gaussian_kernel = gaussian_kernel / sum(gaussian_kernel(:));
        
        % Apply Gaussian smoothing
        frame_smooth = conv2(frame, gaussian_kernel, 'same');
        ref_smooth = conv2(reference, gaussian_kernel, 'same');
        
        % Calculate optical flow for this level
        alpha = alpha_vals(min(level+1, length(alpha_vals)));
        [u, v] = calculate_optical_flow(ref_smooth, frame_smooth, alpha);
        
        if level == actual_levels
            % Initialize with the coarsest level
            corrected_frame = warp_image(frame_smooth, u, v);
        else
            % Calculate next level sigma
            sigma_next = 0.5 * eta^(-(level+1));
            
            % Create next level Gaussian kernel
            kernel_size_next = ceil(6 * sigma_next) | 1;
            [X_next, Y_next] = meshgrid(-floor(kernel_size_next/2):floor(kernel_size_next/2));
            gaussian_kernel_next = exp(-(X_next.^2 + Y_next.^2) / (2 * sigma_next^2));
            gaussian_kernel_next = gaussian_kernel_next / sum(gaussian_kernel_next(:));
            
            if level == 0
                % Final level: add original detail
                frame_next_smooth = conv2(frame, gaussian_kernel_next, 'same');
                laplacian_component = frame - frame_next_smooth;
            else
                % Intermediate level: add Laplacian component
                frame_next_smooth = conv2(frame, gaussian_kernel_next, 'same');
                laplacian_component = frame_smooth - frame_next_smooth;
            end
            
            % Warp and add the Laplacian component
            warped_component = warp_image(laplacian_component, u, v);
            corrected_frame = corrected_frame + warped_component;
        end
    end
end

%% Simple Optical Flow Calculation (Lucas-Kanade style)
function [u, v] = calculate_optical_flow(ref_img, curr_img, alpha)
    % Simple gradient-based optical flow estimation
    % This is a simplified version - in practice you'd use the full
    % variational approach from the paper
    
    % Calculate gradients
    [Ix, Iy] = gradient(ref_img);
    It = curr_img - ref_img;
    
    % Smooth gradients
    sigma_flow = 1.0;
    kernel_size = ceil(6 * sigma_flow) | 1;
    [X, Y] = meshgrid(-floor(kernel_size/2):floor(kernel_size/2));
    flow_kernel = exp(-(X.^2 + Y.^2) / (2 * sigma_flow^2));
    flow_kernel = flow_kernel / sum(flow_kernel(:));
    
    Ix = conv2(Ix, flow_kernel, 'same');
    Iy = conv2(Iy, flow_kernel, 'same');
    It = conv2(It, flow_kernel, 'same');
    
    % Calculate flow using Lucas-Kanade approximation with regularization
    denominator = Ix.^2 + Iy.^2 + alpha;
    u = -(Ix .* It) ./ denominator;
    v = -(Iy .* It) ./ denominator;
    
    % Apply additional smoothing based on alpha
    if alpha < 1.0
        smooth_kernel = fspecial('gaussian', 5, 1.0);
        u = conv2(u, smooth_kernel, 'same');
        v = conv2(v, smooth_kernel, 'same');
    end
end

%% Image Warping Function
function warped = warp_image(img, u, v)
    [height, width] = size(img);
    [X, Y] = meshgrid(1:width, 1:height);
    
    % Apply displacement
    X_warped = X + u;
    Y_warped = Y + v;
    
    % Interpolate
    warped = interp2(X, Y, img, X_warped, Y_warped, 'linear', 0);
    
    % Handle NaN values
    warped(isnan(warped)) = 0;
end

%% Apply Pyramid Motion Correction to Both Channels
fprintf('Applying pyramid-based residual motion correction...\n');

% Initialize output arrays
structural_pyramid_corrected = zeros(size(structural_data));
functional_pyramid_corrected = zeros(size(functional_data));

% Progress tracking
total_frames = n_frames_struct + n_frames_func;
frame_count = 0;

% Process structural frames
fprintf('Processing structural channel...\n');
for frame_idx = 1:n_frames_struct
    if mod(frame_idx, 50) == 0 || frame_idx == 1
        fprintf('  Structural frame %d/%d\n', frame_idx, n_frames_struct);
    end
    
    current_frame = structural_data(:, :, frame_idx);
    
    % Apply pyramid correction
    corrected_frame = pyramid_motion_correction(current_frame, ref_structural, ...
        max_pyramid_levels, eta, alpha_values);
    
    structural_pyramid_corrected(:, :, frame_idx) = corrected_frame;
    frame_count = frame_count + 1;
end

% Process functional frames
fprintf('Processing functional channel...\n');
for frame_idx = 1:n_frames_func
    if mod(frame_idx, 50) == 0 || frame_idx == 1
        fprintf('  Functional frame %d/%d\n', frame_idx, n_frames_func);
    end
    
    current_frame = functional_data(:, :, frame_idx);
    
    % Apply pyramid correction
    corrected_frame = pyramid_motion_correction(current_frame, ref_functional, ...
        max_pyramid_levels, eta, alpha_values);
    
    functional_pyramid_corrected(:, :, frame_idx) = corrected_frame;
    frame_count = frame_count + 1;
end

%% Quality Assessment
fprintf('Assessing correction quality...\n');

% Calculate motion metrics before and after correction
function metrics = calculate_motion_metrics(data, reference)
    n_frames = size(data, 3);
    displacement_magnitudes = zeros(n_frames, 1);
    gradient_errors = zeros(n_frames, 1);
    
    for i = 1:n_frames
        frame = data(:, :, i);
        
        % Calculate simple displacement using cross-correlation
        c = normxcorr2(reference, frame);
        [max_c, max_idx] = max(c(:));
        [ypeak, xpeak] = ind2sub(size(c), max_idx);
        
        % Calculate displacement
        displacement_magnitudes(i) = sqrt((ypeak - size(reference,1))^2 + ...
                                         (xpeak - size(reference,2))^2);
        
        % Calculate gradient error
        [ref_gx, ref_gy] = gradient(reference);
        [frame_gx, frame_gy] = gradient(frame);
        gradient_errors(i) = mean(abs(ref_gx(:) - frame_gx(:)) + ...
                                 abs(ref_gy(:) - frame_gy(:)));
    end
    
    metrics.mean_displacement = mean(displacement_magnitudes);
    metrics.std_displacement = std(displacement_magnitudes);
    metrics.max_displacement = max(displacement_magnitudes);
    metrics.mean_gradient_error = mean(gradient_errors);
    metrics.std_gradient_error = std(gradient_errors);
end

% Calculate metrics for original and corrected data
fprintf('Calculating quality metrics...\n');

% Original data metrics
original_struct_metrics = calculate_motion_metrics(structural_data, ref_structural);
original_func_metrics = calculate_motion_metrics(functional_data, ref_functional);

% Pyramid corrected metrics
pyramid_struct_metrics = calculate_motion_metrics(structural_pyramid_corrected, ref_structural);
pyramid_func_metrics = calculate_motion_metrics(functional_pyramid_corrected, ref_functional);

%% Save Results
fprintf('Saving pyramid-corrected data...\n');

output_file = fullfile(output_folder, '1000_led_E1B1_parallax.h5');
if exist(output_file, 'file'), delete(output_file); end

% Save corrected channels
h5create(output_file, '/structural_pyramid', size(structural_pyramid_corrected));
h5write(output_file, '/structural_pyramid', structural_pyramid_corrected);

h5create(output_file, '/functional_pyramid', size(functional_pyramid_corrected));
h5write(output_file, '/functional_pyramid', functional_pyramid_corrected);

% Save reference frames
h5create(output_file, '/reference_structural', size(ref_structural));
h5write(output_file, '/reference_structural', ref_structural);

h5create(output_file, '/reference_functional', size(ref_functional));
h5write(output_file, '/reference_functional', ref_functional);

% Save processing parameters
processing_params = struct(...
    'max_pyramid_levels', max_pyramid_levels, ...
    'eta', eta, ...
    'alpha_values', alpha_values, ...
    'reference_frames', reference_frames);

% Create a simple text file for parameters (HDF5 struct saving can be complex)
param_file = fullfile(output_folder, 'pyramid_parameters.txt');
fid = fopen(param_file, 'w');
fprintf(fid, 'Pyramid Motion Correction Parameters\n');
fprintf(fid, '====================================\n');
fprintf(fid, 'Max pyramid levels: %d\n', max_pyramid_levels);
fprintf(fid, 'Eta (scaling factor): %.2f\n', eta);
fprintf(fid, 'Alpha values: %s\n', mat2str(alpha_values));
fprintf(fid, 'Reference frames: %d:%d\n', min(reference_frames), max(reference_frames));
fclose(fid);

%% Display Quality Improvement Results
fprintf('\n=== MOTION CORRECTION QUALITY ASSESSMENT ===\n');
fprintf('\nSTRUCTURAL CHANNEL:\n');
fprintf('Original - Mean displacement: %.3f ± %.3f pixels (max: %.3f)\n', ...
    original_struct_metrics.mean_displacement, original_struct_metrics.std_displacement, ...
    original_struct_metrics.max_displacement);
fprintf('Original - Gradient error: %.6f ± %.6f\n', ...
    original_struct_metrics.mean_gradient_error, original_struct_metrics.std_gradient_error);

fprintf('Pyramid  - Mean displacement: %.3f ± %.3f pixels (max: %.3f)\n', ...
    pyramid_struct_metrics.mean_displacement, pyramid_struct_metrics.std_displacement, ...
    pyramid_struct_metrics.max_displacement);
fprintf('Pyramid  - Gradient error: %.6f ± %.6f\n', ...
    pyramid_struct_metrics.mean_gradient_error, pyramid_struct_metrics.std_gradient_error);

improvement_struct_disp = ((original_struct_metrics.mean_displacement - pyramid_struct_metrics.mean_displacement) / ...
    original_struct_metrics.mean_displacement) * 100;
improvement_struct_grad = ((original_struct_metrics.mean_gradient_error - pyramid_struct_metrics.mean_gradient_error) / ...
    original_struct_metrics.mean_gradient_error) * 100;

fprintf('Structural improvement: %.1f%% displacement, %.1f%% gradient error\n', ...
    improvement_struct_disp, improvement_struct_grad);

fprintf('\nFUNCTIONAL CHANNEL:\n');
fprintf('Original - Mean displacement: %.3f ± %.3f pixels (max: %.3f)\n', ...
    original_func_metrics.mean_displacement, original_func_metrics.std_displacement, ...
    original_func_metrics.max_displacement);
fprintf('Original - Gradient error: %.6f ± %.6f\n', ...
    original_func_metrics.mean_gradient_error, original_func_metrics.std_gradient_error);

fprintf('Pyramid  - Mean displacement: %.3f ± %.3f pixels (max: %.3f)\n', ...
    pyramid_func_metrics.mean_displacement, pyramid_func_metrics.std_displacement, ...
    pyramid_func_metrics.max_displacement);
fprintf('Pyramid  - Gradient error: %.6f ± %.6f\n', ...
    pyramid_func_metrics.mean_gradient_error, pyramid_func_metrics.std_gradient_error);

improvement_func_disp = ((original_func_metrics.mean_displacement - pyramid_func_metrics.mean_displacement) / ...
    original_func_metrics.mean_displacement) * 100;
improvement_func_grad = ((original_func_metrics.mean_gradient_error - pyramid_func_metrics.mean_gradient_error) / ...
    original_func_metrics.mean_gradient_error) * 100;

fprintf('Functional improvement: %.1f%% displacement, %.1f%% gradient error\n', ...
    improvement_func_disp, improvement_func_grad);

%% Generate Comparison Visualizations
fprintf('Generating comparison visualizations...\n');

% Select representative frames for comparison
comparison_frames = [50, 250, 350, 450, 550];
comparison_frames = comparison_frames(comparison_frames <= min(n_frames_struct, n_frames_func));

for frame_idx = comparison_frames
    figure('Name', sprintf('Frame %d Comparison', frame_idx), 'Position', [100, 100, 1200, 800]);
    
    % Structural comparison
    subplot(2, 4, 1);
    imagesc(structural_data(:, :, frame_idx)); colormap(gray); axis image;
    title(sprintf('Original Structural (Frame %d)', frame_idx));
    
    subplot(2, 4, 2);
    imagesc(structural_pyramid_corrected(:, :, frame_idx)); colormap(gray); axis image;
    title('Pyramid Corrected Structural');
    
    subplot(2, 4, 3);
    diff_struct = structural_data(:, :, frame_idx) - structural_pyramid_corrected(:, :, frame_idx);
    imagesc(diff_struct); colormap(jet); axis image; colorbar;
    title('Difference (Original - Corrected)');
    
    subplot(2, 4, 4);
    imagesc(abs(diff_struct)); colormap(hot); axis image; colorbar;
    title('Absolute Difference');
    
    % Functional comparison
    if frame_idx <= n_frames_func
        subplot(2, 4, 5);
        imagesc(functional_data(:, :, frame_idx)); colormap(gray); axis image;
        title(sprintf('Original Functional (Frame %d)', frame_idx));
        
        subplot(2, 4, 6);
        imagesc(functional_pyramid_corrected(:, :, frame_idx)); colormap(gray); axis image;
        title('Pyramid Corrected Functional');
        
        subplot(2, 4, 7);
        diff_func = functional_data(:, :, frame_idx) - functional_pyramid_corrected(:, :, frame_idx);
        imagesc(diff_func); colormap(jet); axis image; colorbar;
        title('Difference (Original - Corrected)');
        
        subplot(2, 4, 8);
        imagesc(abs(diff_func)); colormap(hot); axis image; colorbar;
        title('Absolute Difference');
    end
    
    % Save figure
    fig_filename = fullfile(output_folder, sprintf('comparison_frame_%d.png', frame_idx));
    saveas(gcf, fig_filename);
end

%% Create Motion Timeline Plot
% figure('Name', 'Motion Correction Timeline', 'Position', [100, 100, 1200, 600]);
% 
% % Plot displacement over time
% subplot(2, 1, 1);
% time_struct = (1:n_frames_struct) * 10;  % Convert to ms (assuming 100 Hz)
% plot(time_struct, original_struct_metrics.displacement_timeline, 'r-', 'LineWidth', 1.5);
% hold on;
% plot(time_struct, pyramid_struct_metrics.displacement_timeline, 'b-', 'LineWidth', 1.5);
% xlabel('Time (ms)');
% ylabel('Displacement (pixels)');
% title('Structural Channel Displacement Over Time');
% legend('Original', 'Pyramid Corrected', 'Location', 'best');
% grid on;
% 
% subplot(2, 1, 2);
% if n_frames_func > 0
%     time_func = (1:n_frames_func) * 10;
%     plot(time_func, original_func_metrics.displacement_timeline, 'r-', 'LineWidth', 1.5);
%     hold on;
%     plot(time_func, pyramid_func_metrics.displacement_timeline, 'b-', 'LineWidth', 1.5);
% end
% xlabel('Time (ms)');
% ylabel('Displacement (pixels)');
% title('Functional Channel Displacement Over Time');
% legend('Original', 'Pyramid Corrected', 'Location', 'best');
% grid on;
% 
% % Save timeline plot
% timeline_filename = fullfile(output_folder, 'motion_timeline_comparison.png');
% saveas(gcf, timeline_filename);

%% Summary Report
fprintf('Input file: %s\n', input_h5_path);
fprintf('Output file: %s\n', output_file);
fprintf('Processing completed successfully!\n');

fprintf('\nPyramid parameters used:\n');
fprintf('  Maximum levels: %d\n', max_pyramid_levels);
fprintf('  Scaling factor (eta): %.2f\n', eta);
fprintf('  Alpha values: %s\n', mat2str(alpha_values));

%% Optional: Create Analysis-Ready Output
% % If you need the data in a specific format for further analysis
% fprintf('\nCreating analysis-ready output...\n');
% 
% % Save in format compatible with your analysis pipeline
% analysis_file = fullfile(output_folder, 'vsd_analysis_ready.h5');
% if exist(analysis_file, 'file'), delete(analysis_file); end
% 
% % Reconstruct interleaved format if needed
% total_frames_interleaved = n_frames_struct + n_frames_func;
% interleaved_corrected = zeros(height, width, total_frames_interleaved);
% 
% % Assuming original interleaving: structural=even, functional=odd
% interleaved_corrected(:, :, 1:2:end) = structural_pyramid_corrected;
% if n_frames_func > 0
%     end_idx = min(size(interleaved_corrected, 3), 2 * n_frames_func);
%     interleaved_corrected(:, :, 2:2:end_idx) = functional_pyramid_corrected(:, :, 1:floor(end_idx/2));
% end
% 
% h5create(analysis_file, '/image_stack_pyramid_corrected', size(interleaved_corrected));
% h5write(analysis_file, '/image_stack_pyramid_corrected', interleaved_corrected);
% 
% fprintf('Analysis-ready file saved: %s\n', analysis_file);
fprintf('\nPyramid-based residual motion correction completed!\n');