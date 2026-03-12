% =========================================================================
% BLK to HDF5 Batch Converter & Video Exporter
% =========================================================================
% Reads proprietary .BLK optical imaging files, extracts the header metadata,
% saves the raw image stack into a compressed .h5 file, and optionally 
% exports the sequence as a normalized .avi video.
% =========================================================================

clear; clc; close all;

% === CONFIGURATION BLOCK ===
input_pattern = 'dataset/*.BLK';      % Input file(s) pattern or specific file
output_folder = 'converted_output/';  % Output directory (will be created if missing)

% Video Export Settings
export_video = false;                  % Toggle video export (true/false)
video_fps = 60;                       % Frames per second for the exported .avi
% ===========================

% Create output folder if it doesn't exist
if ~exist(output_folder, 'dir')
    mkdir(output_folder);
    fprintf('Created output directory: %s\n', output_folder);
end

% Find files matching the input pattern
files = dir(input_pattern);
if isempty(files)
    error('No files found matching the pattern: %s', input_pattern);
end

fprintf('Found %d file(s) to process.\n\n', length(files));

for i = 1:length(files)
    % Get full file paths
    blk_path = fullfile(files(i).folder, files(i).name);
    [~, base_name, ~] = fileparts(files(i).name);
    
    h5_path = fullfile(output_folder, [base_name, '.h5']);
    avi_path = fullfile(output_folder, [base_name, '.avi']);
    
    fprintf('[%d/%d] Processing: %s\n', i, length(files), files(i).name);
    
    % ---------------------------------------------------------------------
    % 1. Parse BLK Header
    % ---------------------------------------------------------------------
    fid = fopen(blk_path, 'r');
    if fid == -1
        warning('Cannot open file: %s', blk_path);
        continue;
    end
    
    % Get total file size
    fseek(fid, 0, 'eof');
    total_size = ftell(fid);
    fseek(fid, 0, 'bof');
    
    % Read structured header
    filesize       = fread(fid, 1, 'int64');
    checksum_hdr   = fread(fid, 1, 'int16');
    checksum_data  = fread(fid, 1, 'int16');
    lenheader      = fread(fid, 1, 'int32');
    versionid      = fread(fid, 1, 'float32');
    filetype       = fread(fid, 1, 'int32');
    filesubtype    = fread(fid, 1, 'int32');
    datatype       = fread(fid, 1, 'int32');
    sizeof_elem    = fread(fid, 1, 'int32');
    framewidth     = fread(fid, 1, 'int32');
    frameheight    = fread(fid, 1, 'int32');
    nframesperstim = fread(fid, 1, 'int32');
    
    % Map data type (based on Python script mapping)
    switch datatype
        case 11
            mat_dtype = 'uint8';
        case 12
            mat_dtype = 'uint16';
        case 13
            mat_dtype = 'int32';
        case 14
            mat_dtype = 'single'; % float32
        otherwise
            fclose(fid);
            warning('Unsupported datatype code (%d) in file %s', datatype, files(i).name);
            continue;
    end
    
    % Map variant type
    switch filesubtype
        case 11
            variant = 'FROM_VDAQ';
        case 12
            variant = 'FROM_ORA';
        case 13
            variant = 'FROM_DYEDAQ';
        otherwise
            variant = 'Unknown';
    end
    
    % Calculate actual frame count (safeguard against corrupted headers)
    pixel_size = framewidth * frameheight * sizeof_elem;
    actual_nframes = floor((total_size - lenheader) / pixel_size);
    
    % ---------------------------------------------------------------------
    % 2. Read Image Data
    % ---------------------------------------------------------------------
    fseek(fid, lenheader, 'bof');
    raw_data = fread(fid, framewidth * frameheight * actual_nframes, mat_dtype);
    fclose(fid);
    
    % Reshape for HDF5. 
    % MATLAB reads column-major. To ensure Python reads this as (nframes, H, W),
    % we reshape to [W, H, nframes] in MATLAB.
    img_stack = reshape(raw_data, [framewidth, frameheight, actual_nframes]);
    
    % ---------------------------------------------------------------------
    % 3. Write HDF5 File & Metadata
    % ---------------------------------------------------------------------
    if exist(h5_path, 'file')
        delete(h5_path); % Overwrite if exists
    end
    
    % Create dataset with gzip compression (Deflate = 6)
    chunk_dims = [framewidth, frameheight, 1];
    h5create(h5_path, '/image_stack', size(img_stack), ...
        'Datatype', mat_dtype, 'ChunkSize', chunk_dims, 'Deflate', 6);
    
    % Write the data
    h5write(h5_path, '/image_stack', img_stack);
    
    % Write metadata as root attributes
    h5writeatt(h5_path, '/', 'frame_width', int32(framewidth));
    h5writeatt(h5_path, '/', 'frame_height', int32(frameheight));
    h5writeatt(h5_path, '/', 'nframes', int32(actual_nframes));
    h5writeatt(h5_path, '/', 'dtype', mat_dtype);
    h5writeatt(h5_path, '/', 'source_file', blk_path);
    h5writeatt(h5_path, '/', 'version_id', versionid);
    h5writeatt(h5_path, '/', 'variant', variant);
    
    fprintf('  -> Saved HDF5: %s\n', h5_path);
    
    % ---------------------------------------------------------------------
    % 4. Export Video (Optional)
    % ---------------------------------------------------------------------
    if export_video
        v = VideoWriter(avi_path, 'Motion JPEG AVI');
        v.FrameRate = video_fps;
        open(v);
        
        % Global min/max for proper contrast normalization across the whole video
        min_val = double(min(img_stack(:)));
        max_val = double(max(img_stack(:)));
        if max_val == min_val
            max_val = min_val + 1e-6; % Prevent division by zero
        end
        
        for k = 1:actual_nframes
            % Extract frame and transpose it for correct visual orientation
            % (MATLAB images are Height x Width)
            frame = double(img_stack(:, :, k))';
            
            % Normalize to 0-255 (uint8)
            frame_norm = uint8(255 * (frame - min_val) / (max_val - min_val));
            
            % Write frame to video
            writeVideo(v, frame_norm);
        end
        
        close(v);
        fprintf('  -> Exported Video: %s\n', avi_path);
    end
end

fprintf('\n=== Conversion Complete! ===\n');