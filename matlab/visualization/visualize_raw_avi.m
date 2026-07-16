function visualize_raw_avi(input_path, dataset_name, varargin)
    % Visualize HDF5 data as Motion JPEG AVI video with configurable parameters
    %
    % Usage:
    % visualize_raw_avi('path/to/file/led_E0B0.h5', 'image_stack', ...
    %     'channel', 'high_contrast', ...
    %     'clip_percentiles', [0 100], ...
    %     'frame_rate', 500.67, ...
    %     'output_filename', 'output_video.avi', ...
    %     'quality', 95, ...
    %     'max_frames', inf, ...
    %     'downsample_factor', 1, ...
    %     'colormap_name', 'gray');
    
    % -------------------- Parse inputs --------------------
    p = inputParser;
    addRequired(p, 'input_path', @ischar);
    addRequired(p, 'dataset_name', @ischar);
    
    % Channel selection: 'original', 'high_contrast', 'low_contrast', 'A', 'B'
    addParameter(p, 'channel', 'high_contrast', @ischar);
    
    % Intensity clipping percentiles [low high]
    addParameter(p, 'clip_percentiles', [0.5 99.5], @(x) isnumeric(x) && numel(x)==2);
    
    % Video parameters
    addParameter(p, 'frame_rate', 500.67, @isnumeric);
    addParameter(p, 'output_filename', '', @ischar);
    addParameter(p, 'quality', 95, @(x) isnumeric(x) && x>=1 && x<=100);
    
    % Processing parameters
    addParameter(p, 'max_frames', inf, @isnumeric);
    addParameter(p, 'downsample_factor', 1, @(x) isnumeric(x) && x>=1);
    addParameter(p, 'start_frame', 1, @isnumeric);
    
    % Display parameters
    addParameter(p, 'colormap_name', 'gray', @ischar);
    addParameter(p, 'show_progress', true, @islogical);
    addParameter(p, 'preview_only', false, @islogical);
    addParameter(p, 'preview_frames', 100, @isnumeric);
    
    % Memory management
    addParameter(p, 'buffer_size', 50, @isnumeric);
    
    parse(p, input_path, dataset_name, varargin{:});
    R = p.Results;
    
    % -------------------- Setup --------------------
    assert(exist(R.input_path,'file')==2, 'File not found: %s', R.input_path);
    
    % Get dataset info
    dset = ['/' R.dataset_name];
    info = h5info(R.input_path, dset);
    sz = info.Dataspace.Size;
    
    % Determine dimensions
    if numel(sz)==3 && sz(3) > sz(1)
        dims = struct('height', sz(1), 'width', sz(2), 'frames', sz(3));
        needs_permute = false;
    elseif numel(sz)==3 && sz(1) > sz(3)
        dims = struct('height', sz(2), 'width', sz(3), 'frames', sz(1));
        needs_permute = true;
    else
        error('Cannot determine frame dimension from size: %s', mat2str(sz));
    end
    
    H = dims.height; W = dims.width; T = dims.frames;
    
    % -------------------- Analyze interleaves --------------------
    fprintf('Analyzing interleave pattern...\n');
    sample_T = min(20, T);
    sample = read_block(R.input_path, dset, needs_permute, [1,1,1], [H,W,sample_T]);
    
    A = sample(:,:,1:2:end);
    B = sample(:,:,2:2:end);
    contrastA = std(double(A), [], 'all');
    contrastB = std(double(B), [], 'all');
    
    if contrastA > contrastB
        high_contrast_is_A = true;
        fprintf('Channel A has higher contrast (%.2f vs %.2f)\n', contrastA, contrastB);
    else
        high_contrast_is_A = false;
        fprintf('Channel B has higher contrast (%.2f vs %.2f)\n', contrastB, contrastA);
    end
    
    % -------------------- Determine channel selection --------------------
    switch lower(R.channel)
        case 'original'
            use_interleave = 'none';
            effective_fps = R.frame_rate;
        case 'high_contrast'
            use_interleave = ternary(high_contrast_is_A, 'A', 'B');
            effective_fps = R.frame_rate / 2;
        case 'low_contrast'
            use_interleave = ternary(high_contrast_is_A, 'B', 'A');
            effective_fps = R.frame_rate / 2;
        case 'a'
            use_interleave = 'A';
            effective_fps = R.frame_rate / 2;
        case 'b'
            use_interleave = 'B';
            effective_fps = R.frame_rate / 2;
        otherwise
            error('Unknown channel: %s', R.channel);
    end
    
    % Apply temporal downsampling to effective fps
    effective_fps = effective_fps / R.downsample_factor;
    
    fprintf('Channel: %s (use_interleave: %s), Effective FPS: %.2f\n', R.channel, use_interleave, effective_fps);
    
    % -------------------- Determine frame range and total frames --------------------
    % Calculate end_frame based on max_frames parameter
    end_frame = min(T, R.start_frame + R.max_frames - 1);
    
    % Adjust for preview mode
    if R.preview_only
        end_frame = min(end_frame, R.start_frame + R.preview_frames - 1);
    end
    
    % Calculate total_frames based on channel selection
    raw_frame_count = end_frame - R.start_frame + 1;
    
    if strcmp(use_interleave, 'none')
        % Original mode: all frames are used
        channel_frames = raw_frame_count;
    else
        % Interleaved mode: only half the frames are used
        % Count how many frames of the selected channel we'll actually get
        if strcmp(use_interleave, 'A')
            % Channel A: odd frames (1, 3, 5, ...)
            first_frame_is_A = mod(R.start_frame, 2) == 1;
            last_frame_is_A = mod(end_frame, 2) == 1;
        else
            % Channel B: even frames (2, 4, 6, ...)
            first_frame_is_A = mod(R.start_frame, 2) == 0;
            last_frame_is_A = mod(end_frame, 2) == 0;
        end
        
        % More accurate calculation of frames for the selected channel
        channel_frames = floor(raw_frame_count / 2);
        if first_frame_is_A || last_frame_is_A
            channel_frames = ceil(raw_frame_count / 2);
        end
    end
    
    % Apply downsampling factor
    total_frames = ceil(channel_frames / R.downsample_factor);
    
    fprintf('Processing range: frames %d to %d (%d raw frames)\n', R.start_frame, end_frame, raw_frame_count);
    fprintf('Expected output frames: %d (after channel selection and downsampling)\n', total_frames);
    
    % -------------------- Calculate intensity range --------------------
    fprintf('Calculating intensity range for clipping...\n');
    
    % Sample frames for percentile calculation
    sample_indices = round(linspace(R.start_frame, end_frame, min(100, raw_frame_count)));
    sample_data = [];
    
    for idx = sample_indices
        frame = read_block(R.input_path, dset, needs_permute, [1,1,idx], [H,W,1]);
        
        % Extract appropriate channel
        if strcmp(use_interleave, 'A') && mod(idx,2)==1
            sample_data = [sample_data; frame(:)];
        elseif strcmp(use_interleave, 'B') && mod(idx,2)==0
            sample_data = [sample_data; frame(:)];
        elseif strcmp(use_interleave, 'none')
            sample_data = [sample_data; frame(:)];
        end
    end
    
    % Calculate percentiles
    clip_low = prctile(double(sample_data), R.clip_percentiles(1));
    clip_high = prctile(double(sample_data), R.clip_percentiles(2));
    fprintf('Clipping range: [%.1f, %.1f] (percentiles: [%.1f, %.1f])\n', ...
        clip_low, clip_high, R.clip_percentiles(1), R.clip_percentiles(2));
    
    % -------------------- Setup output --------------------
    if isempty(R.output_filename)
        [~, name, ~] = fileparts(R.input_path);
        R.output_filename = sprintf('%s_%s_fps%.0f.avi', name, R.channel, effective_fps);
    end
    
    if ~R.preview_only
        v = VideoWriter(R.output_filename, 'Motion JPEG AVI');
        v.FrameRate = effective_fps; % No Cap at fps for playback
        v.Quality = R.quality;
        open(v);
        fprintf('Writing video to: %s\n', R.output_filename);
    else
        fprintf('Preview mode - no video will be saved\n');
        figure('Name', sprintf('Preview: %s channel', R.channel), 'Color', 'w');
    end
    
    % -------------------- Process frames --------------------
    fprintf('Processing frames...\n');
    
    if R.show_progress
        hw = waitbar(0, 'Processing frames...');
    end
    
    frame_count = 0;
    frame_processed_count = 0;  % Track frames before downsampling
    
    % Process in chunks for efficiency
    for start_idx = R.start_frame:R.buffer_size:end_frame
        chunk_end = min(start_idx + R.buffer_size - 1, end_frame);
        chunk_size = chunk_end - start_idx + 1;
        
        % Read chunk
        chunk = read_block(R.input_path, dset, needs_permute, ...
            [1, 1, start_idx], [H, W, chunk_size]);
        
        % Process each frame in chunk
        for i = 1:chunk_size
            global_idx = start_idx + i - 1;
            
            % Check if we should process this frame based on channel selection
            if strcmp(use_interleave, 'A') && mod(global_idx, 2) ~= 1
                continue;  % Skip even frames for channel A
            elseif strcmp(use_interleave, 'B') && mod(global_idx, 2) ~= 0
                continue;  % Skip odd frames for channel B
            end
            
            % Apply temporal downsampling
            if mod(frame_processed_count, R.downsample_factor) ~= 0
                frame_processed_count = frame_processed_count + 1;
                continue;
            end
            frame_processed_count = frame_processed_count + 1;
            
            frame = chunk(:,:,i);
            
            % Apply intensity clipping and normalize
            frame = double(frame);
            frame = (frame - clip_low) / (clip_high - clip_low);
            frame(frame < 0) = 0;
            frame(frame > 1) = 1;
            
            % Convert to uint8
            frame_uint8 = uint8(frame * 255);
            
            if R.preview_only
                % Show preview
                imshow(frame_uint8, 'Colormap', eval(R.colormap_name));
                title(sprintf('Frame %d (global: %d)', frame_count+1, global_idx));
                drawnow;
                
                if frame_count >= R.preview_frames - 1
                    break;
                end
            else
                % Write to video
                writeVideo(v, frame_uint8);
            end
            
            frame_count = frame_count + 1;
            
            if R.show_progress && mod(frame_count, 10) == 0
                waitbar(frame_count / total_frames, hw, ...
                    sprintf('Processing frames... %d/%d', frame_count, total_frames));
            end
        end
        
        if R.preview_only && frame_count >= R.preview_frames - 1
            break;
        end
    end
    
    % -------------------- Cleanup --------------------
    if R.show_progress
        close(hw);
    end
    
    if ~R.preview_only
        close(v);
        fprintf('Video saved: %s\n', R.output_filename);
        fprintf('Total frames written: %d (expected: %d)\n', frame_count, total_frames);
        fprintf('Duration: %.3f seconds at %.3f fps\n', frame_count / v.FrameRate, v.FrameRate);
    else
        fprintf('Preview complete: %d frames shown\n', frame_count);
    end
    
    % -------------------- Summary --------------------
    fprintf('\n=== Summary ===\n');
    fprintf('Input: %s\n', R.input_path);
    fprintf('Dataset: %s [%dx%dx%d]\n', R.dataset_name, H, W, T);
    fprintf('Channel: %s\n', R.channel);
    fprintf('Clipping percentiles: [%.1f, %.1f]\n', R.clip_percentiles(1), R.clip_percentiles(2));
    fprintf('Effective frame rate: %.2f fps\n', effective_fps);
    if ~R.preview_only
        fprintf('Output: %s\n', R.output_filename);
        
        % Get file size
        finfo = dir(R.output_filename);
        if ~isempty(finfo)
            fprintf('File size: %.2f MB\n', finfo.bytes / (1024^2));
        end
    end
end

% -------------------- Helper functions --------------------
function block = read_block(h5path, dset, needs_permute, startHW1, countHW1)
    H = countHW1(1); W = countHW1(2); Tcount = countHW1(3);
    Tstart = startHW1(3);
    
    if ~needs_permute
        start = [startHW1(1), startHW1(2), Tstart];
        count = [H, W, Tcount];
        block = h5read(h5path, dset, start, count);
    else
        start = [Tstart, startHW1(1), startHW1(2)];
        count = [Tcount, H, W];
        block = h5read(h5path, dset, start, count);
        block = permute(block, [2 3 1]);
    end
end

function out = ternary(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end