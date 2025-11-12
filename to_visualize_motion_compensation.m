%% High-Speed Video Comparison for VSD Motion Correction
clear;

%% Configuration
input_h5_path = 'converted__500/led_E0B0.h5';
corrected_h5_path = 'data/motion_corrected/vsd_corrected.h5';
dataset_name = 'image_stack';
output_folder = 'data/motion_corrected/videos';
original_fps = 500.67; % Your original recording rate
new_fps = original_fps/2;

% Create video output folder
if ~isfolder(output_folder)
    mkdir(output_folder)
end

%% Load data
fprintf('Loading data for video comparison...\n');

% Load original interleaved data
original_data = h5read(input_h5_path, ['/' dataset_name]);
if size(original_data, 1) == 1500
    original_data = permute(original_data, [2, 3, 1]);
end

% Load corrected data and reconstruct interleaved
corrected_structural = h5read(corrected_h5_path, '/structural_corrected');
corrected_functional = h5read(corrected_h5_path, '/functional_corrected');

% Reconstruct corrected interleaved data
[height, width, total_frames] = size(original_data);
corrected_interleaved = zeros(height, width, total_frames, class(corrected_structural));
corrected_interleaved(:, :, 2:2:end) = corrected_structural; % Even frames (structural)
corrected_interleaved(:, :, 1:2:end) = corrected_functional;  % Odd frames (VSD)

fprintf('Data loaded: %dx%dx%d frames\n', height, width, total_frames);

%% Helper function for progress display (inline)
display_progress = @(i, total, start_time, task_name) ...
    fprintf('\r%s: Frame %d/%d (%.1f%%) - Elapsed: %.1fs, Est. remaining: %.1fs', ...
    task_name, i, total, 100*i/total, toc(start_time), ...
    toc(start_time) * (total/i - 1));

%% 1. Create side-by-side comparison video at original frame rate
fprintf('\nCreating side-by-side comparison video at %.2f fps...\n', original_fps);

video_filename = fullfile(output_folder, 'motion_correction_sidebyside.avi');
video_writer = VideoWriter(video_filename, 'Motion JPEG AVI');
video_writer.FrameRate = original_fps;
video_writer.Quality = 90; % High quality
open(video_writer);

% Normalize data for consistent display
original_norm = mat2gray(double(original_data));
corrected_norm = mat2gray(double(corrected_interleaved));

% Create side-by-side frames with progress
fprintf('Processing side-by-side frames:\n');
start_time = tic;
for i = 1:total_frames
    % Update progress every 10 frames for smoother display
    if mod(i, 10) == 0 || i == 1 || i == total_frames
        display_progress(i, total_frames, start_time, 'Side-by-side');
    end
    
    % Create side-by-side frame
    combined_frame = [original_norm(:, :, i), corrected_norm(:, :, i)];
    
    % Add text labels (optional, but helps identification)
    combined_frame = insertText(combined_frame, [10, 10], 'Original', ...
        'FontSize', 12, 'BoxColor', 'white', 'TextColor', 'black');
    combined_frame = insertText(combined_frame, [width + 10, 10], 'Corrected', ...
        'FontSize', 12, 'BoxColor', 'white', 'TextColor', 'black');
    
    writeVideo(video_writer, combined_frame);
end

close(video_writer);
fprintf('\n✓ Side-by-side video saved: %s (%.1f seconds)\n', video_filename, toc(start_time));

%% 2. Create separate original and corrected videos
fprintf('\nCreating separate original video...\n');

original_video_filename = fullfile(output_folder, 'original_data.avi');
original_writer = VideoWriter(original_video_filename, 'Motion JPEG AVI');
original_writer.FrameRate = original_fps;
original_writer.Quality = 90;
open(original_writer);

start_time = tic;
for i = 1:total_frames
    if mod(i, 10) == 0 || i == 1 || i == total_frames
        display_progress(i, total_frames, start_time, 'Original video');
    end
    writeVideo(original_writer, original_norm(:, :, i));
end
close(original_writer);
fprintf('\n✓ Original video saved (%.1f seconds)\n', toc(start_time));

fprintf('\nCreating separate corrected video...\n');

corrected_video_filename = fullfile(output_folder, 'corrected_data.avi');
corrected_writer = VideoWriter(corrected_video_filename, 'Motion JPEG AVI');
corrected_writer.FrameRate = original_fps;
corrected_writer.Quality = 90;
open(corrected_writer);

start_time = tic;
for i = 1:total_frames
    if mod(i, 10) == 0 || i == 1 || i == total_frames
        display_progress(i, total_frames, start_time, 'Corrected video');
    end
    writeVideo(corrected_writer, corrected_norm(:, :, i));
end
close(corrected_writer);
fprintf('\n✓ Corrected video saved (%.1f seconds)\n', toc(start_time));

%% 3. Create structural channel comparison (higher contrast for motion detection)
fprintf('\nCreating structural channel comparison...\n');

original_structural = original_data(:, :, 2:2:end);
struct_frames = size(original_structural, 3);
struct_fps = original_fps / 2; % Half the frame rate since we're showing every other frame

struct_video_filename = fullfile(output_folder, 'structural_comparison.avi');
struct_writer = VideoWriter(struct_video_filename, 'Motion JPEG AVI');
struct_writer.FrameRate = struct_fps;
struct_writer.Quality = 90;
open(struct_writer);

% Normalize structural channels
original_struct_norm = mat2gray(double(original_structural));
corrected_struct_norm = mat2gray(double(corrected_structural));

start_time = tic;
for i = 1:struct_frames
    if mod(i, 10) == 0 || i == 1 || i == struct_frames
        display_progress(i, struct_frames, start_time, 'Structural comparison');
    end
    
    combined_struct_frame = [original_struct_norm(:, :, i), corrected_struct_norm(:, :, i)];
    combined_struct_frame = insertText(combined_struct_frame, [10, 10], 'Original Structural', ...
        'FontSize', 12, 'BoxColor', 'white', 'TextColor', 'black');
    combined_struct_frame = insertText(combined_struct_frame, [width + 10, 10], 'Corrected Structural', ...
        'FontSize', 12, 'BoxColor', 'white', 'TextColor', 'black');
    writeVideo(struct_writer, combined_struct_frame);
end
close(struct_writer);
fprintf('\n✓ Structural comparison saved (%.1f seconds)\n', toc(start_time));

%% 4. Create difference video to highlight motion correction
fprintf('\nCreating difference video...\n');

% Calculate absolute difference between original and corrected
difference_data = abs(double(original_data) - double(corrected_interleaved));
difference_norm = mat2gray(difference_data);

difference_video_filename = fullfile(output_folder, 'motion_difference.avi');
diff_writer = VideoWriter(difference_video_filename, 'Motion JPEG AVI');
diff_writer.FrameRate = original_fps;
diff_writer.Quality = 90;
open(diff_writer);

start_time = tic;
for i = 1:total_frames
    if mod(i, 10) == 0 || i == 1 || i == total_frames
        display_progress(i, total_frames, start_time, 'Difference video');
    end
    
    diff_frame = difference_norm(:, :, i);
    diff_frame = insertText(diff_frame, [10, 10], sprintf('Difference Frame %d', i), ...
        'FontSize', 12, 'BoxColor', 'white', 'TextColor', 'black');
    writeVideo(diff_writer, diff_frame);
end
close(diff_writer);
fprintf('\n✓ Difference video saved (%.1f seconds)\n', toc(start_time));

%% 5. Create motion vector overlay video (if displacement data available)
if exist('data/motion_corrected/w.hdf', 'file')
    fprintf('\nCreating motion vector visualization...\n');
    
    u_fields = h5read('data/motion_corrected/w.hdf', '/u');
    v_fields = h5read('data/motion_corrected/w.hdf', '/v');
    
    vector_frames = size(u_fields, 3);
    
    vector_video_filename = fullfile(output_folder, 'motion_vectors.avi');
    vector_writer = VideoWriter(vector_video_filename, 'Motion JPEG AVI');
    vector_writer.FrameRate = struct_fps; % Using structural frame rate
    vector_writer.Quality = 90;
    open(vector_writer);
    
    % Parameters for vector overlay
    vector_step = 15; % Show every 15th vector for clarity
    vector_scale = 5;  % Scale vectors for visibility
    
    start_time = tic;
    for i = 1:vector_frames
        if mod(i, 5) == 0 || i == 1 || i == vector_frames  % Less frequent updates due to complexity
            display_progress(i, vector_frames, start_time, 'Motion vectors');
        end
        
        % Base image
        base_frame = original_struct_norm(:, :, i);
        base_rgb = repmat(base_frame, [1, 1, 3]);
        
        % Create vector field overlay
        [X, Y] = meshgrid(1:vector_step:width, 1:vector_step:height);
        U_sub = u_fields(1:vector_step:end, 1:vector_step:end, i) * vector_scale;
        V_sub = v_fields(1:vector_step:end, 1:vector_step:end, i) * vector_scale;
        
        % Draw vectors on the image
        for row = 1:size(U_sub, 1)
            for col = 1:size(U_sub, 2)
                if abs(U_sub(row, col)) > 0.1 || abs(V_sub(row, col)) > 0.1
                    start_y = (row-1) * vector_step + 1;
                    start_x = (col-1) * vector_step + 1;
                    end_y = round(start_y + V_sub(row, col));
                    end_x = round(start_x + U_sub(row, col));
                    
                    % Ensure coordinates are within bounds
                    end_y = max(1, min(height, end_y));
                    end_x = max(1, min(width, end_x));
                    
                    % Draw red line for motion vector
                    base_rgb = insertShape(base_rgb, 'Line', ...
                        [start_x, start_y, end_x, end_y], ...
                        'Color', 'red', 'LineWidth', 1);
                end
            end
        end
        
        base_rgb = insertText(base_rgb, [10, 10], sprintf('Motion Vectors Frame %d', i), ...
            'FontSize', 12, 'BoxColor', 'white', 'TextColor', 'black');
        
        writeVideo(vector_writer, base_rgb);
    end
    close(vector_writer);
    fprintf('\n✓ Motion vector video saved (%.1f seconds)\n', toc(start_time));
end

fprintf('\n=== Video Files Created ===\n');
fprintf('• Side-by-side comparison (%.1f fps): %s\n', original_fps, video_filename);
fprintf('• Original data only (%.1f fps): %s\n', original_fps, original_video_filename);
fprintf('• Corrected data only (%.1f fps): %s\n', original_fps, corrected_video_filename);
fprintf('• Structural comparison (%.1f fps): %s\n', struct_fps, struct_video_filename);
fprintf('• Difference visualization (%.1f fps): %s\n', original_fps, difference_video_filename);

if exist('data/motion_corrected/w.hdf', 'file')
    fprintf('• Motion vectors (%.1f fps): %s\n', struct_fps, vector_video_filename);
end

%% File size information
file_info = dir(video_filename);
fprintf('• Side-by-side video: %.1f MB\n', file_info.bytes / 1e6);

if exist(original_video_filename, 'file')
    file_info = dir(original_video_filename);
    fprintf('• Original video: %.1f MB\n', file_info.bytes / 1e6);
end

if exist(corrected_video_filename, 'file')
    file_info = dir(corrected_video_filename);
    fprintf('• Corrected video: %.1f MB\n', file_info.bytes / 1e6);
end

if exist(struct_video_filename, 'file')
    file_info = dir(struct_video_filename);
    fprintf('• Structural comparison: %.1f MB\n', file_info.bytes / 1e6);
end

if exist(difference_video_filename, 'file')
    file_info = dir(difference_video_filename);
    fprintf('• Difference video: %.1f MB\n', file_info.bytes / 1e6);
end

if exist('vector_video_filename', 'var') && exist(vector_video_filename, 'file')
    file_info = dir(vector_video_filename);
    fprintf('• Motion vectors: %.1f MB\n', file_info.bytes / 1e6);
end

fprintf('\nVideo creation completed successfully!\n');