%% Generate Summary
fprintf('\n=== VIDEO GENERATION COMPLETE ===\n');
fprintf('Output file: %s\n', output_video_path);
fprintf('Video specs:\n');
fprintf('  Resolution: %dx%d\n', width, height);
fprintf('  Duration: %.2f seconds\n', n_frames/fps);
fprintf('  Frame rate: %d fps\n', v.FrameRate);
fprintf('  Total frames: %d\n', n_frames);
fprintf('  Channel: %s\n', channel_to_visualize);
fprintf('  Colormap: %s\n', colormap_name);
fprintf('  Contrast: %.2f to %.2f\n', contrast_limits(1), contrast_limits(2));

% Calculate file size
file_info = dir(output_video_path);
if ~isempty(file_info)
    file_size_mb = file_info.bytes / (1024^2);
    fprintf('  File size: %.1f MB\n', file_size_mb);
end

fprintf('\nVideo successfully generated!\n');
fprintf('You can open the video with any media player.\n');

%% Helper Function: Add Text Overlay
function img_with_text = add_text_overlay(img, text_str, position, color, font_size)
    % Simple text overlay function
    % For more sophisticated text rendering, you might need additional toolboxes
    
    % Convert color string to RGB
    switch lower(color)
        case 'white'
            text_color = [1, 1, 1];
        case 'black'
            text_color = [0, 0, 0];
        case 'red'
            text_color = [1, 0, 0];
        case 'green'
            text_color = [0, 1, 0];
        case 'blue'
            text_color = [0, 0, 1];
        otherwise
            text_color = [1, 1, 1];  % Default to white
    end
    
    % For simplicity, we'll create a basic text overlay
    % In practice, you might want to use insertText() if Computer Vision Toolbox is available
    img_with_text = img;
    
    % Basic text rendering (simplified)
    % This creates a simple block where text would go
    x_pos = max(1, min(position(1), size(img, 2) - 100));
    y_pos = max(1, min(position(2), size(img, 1) - 20));
    
    % Create a simple text background
    text_width = min(length(text_str) * 8, size(img, 2) - x_pos);  % Approximate
    text_height = min(15, size(img, 1) - y_pos);
    
    if x_pos + text_width <= size(img, 2) && y_pos + text_height <= size(img, 1)
        % Add semi-transparent background
        for c = 1:3
            img_with_text(y_pos:y_pos+text_height-1, x_pos:x_pos+text_width-1, c) = ...
                img_with_text(y_pos:y_pos+text_height-1, x_pos:x_pos+text_width-1, c) * 0.7 + ...
                text_color(c) * 0.3;
        end
    end
end%% VSD Motion Correction Video Visualizer
% video_generator.m
% Creates comparison videos showing original vs pyramid-corrected VSD data

clear; clc; close all;

%% Configuration
input_original_path = 'data/motion_corrected/1000_led_E1B1_vsd_corrected.h5';  % Original motion-corrected data
input_pyramid_path = 'data/parallax_corrected/1000_led_E1B1_parallax.h5';     % Pyramid-corrected data
output_folder = 'data/videos';

% Video parameters
fps = 30;  % Frames per second - CHANGE THIS TO YOUR DESIRED FPS
video_quality = 75;  % Video quality (0-100)
channel_to_visualize = 'structural';  % 'structural', 'functional', or 'both'

% Display parameters
contrast_percentile = [1, 99];  % Percentiles for contrast adjustment
colormap_name = 'gray';  % 'gray', 'jet', 'parula', 'hot', etc.

% Create output folder
if ~isfolder(output_folder)
    mkdir(output_folder)
end

%% Auto-generate output filename
timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
base_filename = sprintf('vsd_motion_correction_comparison_%s_fps%d', timestamp, fps);

%% Load Corrected Data
fprintf('Loading pyramid-corrected VSD data...\n');

try
    if strcmpi(channel_to_visualize, 'structural')
        data = h5read(input_pyramid_path, '/structural_pyramid');
        fprintf('Loaded structural channel: %dx%dx%d frames\n', size(data));
    elseif strcmpi(channel_to_visualize, 'functional')
        data = h5read(input_pyramid_path, '/functional_pyramid');
        fprintf('Loaded functional channel: %dx%dx%d frames\n', size(data));
    else
        error('Please specify either "structural" or "functional" for channel_to_visualize');
    end
catch ME
    fprintf('Error loading data: %s\n', ME.message);
    fprintf('Please ensure the pyramid correction script has been run first.\n');
    return;
end

[height, width, n_frames] = size(data);
fprintf('Video will be %dx%d pixels, %d frames at %d fps (%.2f seconds)\n', ...
    width, height, n_frames, fps, n_frames/fps);

%% Prepare Data for Video
fprintf('Preparing data for video generation...\n');

% Convert to double for processing
data = double(data);

% Calculate contrast limits based on all frames
all_pixels = data(:);
contrast_limits = prctile(all_pixels, contrast_percentile);
fprintf('Contrast limits: [%.2f, %.2f]\n', contrast_limits(1), contrast_limits(2));

% Normalize data to [0, 1] range
data_normalized = (data - contrast_limits(1)) / (contrast_limits(2) - contrast_limits(1));
data_normalized = max(0, min(1, data_normalized));  % Clamp to [0, 1]

%% Create Video
output_video_path = fullfile(output_folder, [base_filename, '.mp4']);
fprintf('Creating video: %s\n', output_video_path);

% Create video writer
v = VideoWriter(output_video_path, 'MPEG-4');
v.FrameRate = fps;
v.Quality = video_quality;
open(v);

% Generate frames
fprintf('Writing video frames...\n');
progress_interval = max(1, round(n_frames / 20));  % Update progress every 5%

for frame_idx = 1:n_frames
    % Show progress
    if mod(frame_idx, progress_interval) == 0 || frame_idx == 1 || frame_idx == n_frames
        fprintf('  Frame %d/%d (%.1f%%)\n', frame_idx, n_frames, 100*frame_idx/n_frames);
    end
    
    % Get current frame
    current_frame = data_normalized(:, :, frame_idx);
    
    % Create figure for this frame
    fig = figure('Visible', 'off', 'Position', [100, 100, width, height]);
    
    % Display frame
    imagesc(current_frame);
    colormap(colormap_name);
    axis image off;
    
    % Add frame number overlay
    text(10, 20, sprintf('Frame %d', frame_idx), ...
        'Color', 'white', 'FontSize', 12, 'FontWeight', 'bold');
    
    % Add timestamp overlay
    time_ms = (frame_idx - 1) * (1000 / fps);
    text(10, height - 10, sprintf('%.0f ms', time_ms), ...
        'Color', 'white', 'FontSize', 10);
    
    % Capture frame
    frame_data = getframe(fig);
    writeVideo(v, frame_data);
    
    % Close figure to save memory
    close(fig);
end

% Close video writer
close(v);

%% Generate Summary
fprintf('\n=== VIDEO GENERATION COMPLETE ===\n');
fprintf('Output file: %s\n', output_video_path);
fprintf('Video specs:\n');
fprintf('  Resolution: %dx%d\n', width, height);
fprintf('  Duration: %.2f seconds\n', n_frames/fps);
fprintf('  Frame rate: %d fps\n', fps);
fprintf('  Total frames: %d\n', n_frames);
fprintf('  Channel: %s\n', channel_to_visualize);
fprintf('  Colormap: %s\n', colormap_name);
fprintf('  Contrast: %.2f to %.2f\n', contrast_limits(1), contrast_limits(2));

% Calculate file size
file_info = dir(output_video_path);
if ~isempty(file_info)
    file_size_mb = file_info.bytes / (1024^2);
    fprintf('  File size: %.1f MB\n', file_size_mb);
end

fprintf('\nVideo successfully generated!\n');
fprintf('You can open the video with any media player.\n');