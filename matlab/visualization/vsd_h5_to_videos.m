function out_files = vsd_h5_to_videos(input_h5_path, varargin)
% Create two videos at 250.335 fps from a motion-compensated HDF5 file.
% Expects datasets '/structural' and '/functional' (as produced by vsd_motion_correct).
% Output file names are derived from the input file name + "_structural.mp4" / "_functional.mp4".
% Usage:
%   vsd_h5_to_videos('path/to/file_vsd_corrected.h5', ...
%       'OutputFolder','videos', ...
%       'FPS',250.335, ...
%       'ClipPercentiles',[0.5 99.5], ...
%       'Codec','MPEG-4', ...
%       'PixelSampleFraction',0.1, ...
%       'MaxSampleFrames',200);

%% Parse inputs
p = inputParser;
addRequired(p, 'input_h5_path', @(s)ischar(s) || isstring(s));
addParameter(p, 'OutputFolder', 'videos', @(s)ischar(s) || isstring(s));
addParameter(p, 'FPS', 250.335, @(x)isnumeric(x) && isscalar(x) && x>0);
addParameter(p, 'ClipPercentiles', [0.5 99.5], @(v)isnumeric(v) && numel(v)==2 && all(v>=0) && all(v<=100) && v(1)<v(2));
addParameter(p, 'Codec', 'MPEG-4', @(s)ischar(s) || isstring(s));
addParameter(p, 'PixelSampleFraction', 0.1, @(x)isnumeric(x) && isscalar(x) && x>0 && x<=1);
addParameter(p, 'MaxSampleFrames', 200, @(x)isnumeric(x) && isscalar(x) && x>0);
parse(p, input_h5_path, varargin{:});

% Convert to char arrays for compatibility
output_folder         = char(p.Results.OutputFolder);
fps                  = p.Results.FPS;
clip_percentiles     = p.Results.ClipPercentiles;
codec                = char(p.Results.Codec);
pixel_sample_frac    = p.Results.PixelSampleFraction;
max_sample_frames    = p.Results.MaxSampleFrames;

% Validate input file exists
if ~exist(input_h5_path, 'file')
    error('Input HDF5 file does not exist: %s', input_h5_path);
end

% Validate codec
valid_codecs = {'MPEG-4', 'Motion JPEG AVI', 'Archival', 'Motion JPEG 2000', 'Uncompressed AVI'};
if ~any(strcmpi(codec, valid_codecs))
    warning('Codec "%s" may not be supported. Valid options: %s', codec, strjoin(valid_codecs, ', '));
end

% Create output folder if it doesn't exist
if ~isfolder(output_folder)
    [success, msg] = mkdir(output_folder);
    if ~success
        error('Failed to create output folder %s: %s', output_folder, msg);
    end
end

% Derive output base name from input file
[~, base, ~] = fileparts(input_h5_path);

%% Load and validate HDF5 structure
fprintf('Loading HDF5 file: %s\n', input_h5_path);
try
    info = h5info(input_h5_path);
    dataset_names = {info.Datasets.Name};
catch ME
    error('Failed to read HDF5 file info: %s', ME.message);
end

% Check for required datasets
required_datasets = {'structural', 'functional'};
missing_datasets = setdiff(required_datasets, dataset_names);
if ~isempty(missing_datasets)
    error('Missing required datasets: %s. Available datasets: %s', ...
        strjoin(missing_datasets, ', '), strjoin(dataset_names, ', '));
end

fprintf('Found required datasets: %s\n', strjoin(required_datasets, ', '));

%% Validate dataset dimensions and get basic info
dataset_info = struct();
for i = 1:length(required_datasets)
    ds_name = required_datasets{i};
    try
        ds_info = h5info(input_h5_path, ['/' ds_name]);
        sz = ds_info.Dataspace.Size;
        
        if numel(sz) ~= 3
            error('Dataset "/%s" must be 3-dimensional (H x W x T), got %d dimensions', ds_name, numel(sz));
        end
        
        dataset_info.(ds_name) = struct('size', sz, 'H', sz(1), 'W', sz(2), 'T', sz(3));
        fprintf('Dataset "/%s": %dx%dx%d (H x W x T)\n', ds_name, sz(1), sz(2), sz(3));
        
        % Validate minimum frame count
        if sz(3) < 1
            error('Dataset "/%s" has no frames', ds_name);
        end
        
    catch ME
        error('Failed to validate dataset "/%s": %s', ds_name, ME.message);
    end
end

%% Process each dataset to video
fprintf('Starting video generation with FPS=%.3f, Codec=%s\n', fps, codec);
out_files = struct();

for i = 1:length(required_datasets)
    ds_name = required_datasets{i};
    ds_path = ['/' ds_name];
    info = dataset_info.(ds_name);
    
    fprintf('\nProcessing "%s" dataset (%dx%dx%d)...\n', ds_name, info.H, info.W, info.T);
    
    try
        % Compute percentiles for robust scaling
        fprintf('Computing intensity percentiles for scaling...\n');
        stats = compute_percentiles_robust(input_h5_path, ds_path, clip_percentiles, ...
                                         pixel_sample_frac, max_sample_frames);
        fprintf('Intensity range: %.2f to %.2f (%.1f%% to %.1f%% percentiles)\n', ...
            stats.lo, stats.hi, clip_percentiles(1), clip_percentiles(2));
        
        % Generate output filename
        if strcmpi(codec, 'Motion JPEG AVI')
            ext = '.avi';
        end
        
        out_path = fullfile(output_folder, sprintf('%s_%s_%.3ffps%s', base, ds_name, fps, ext));
        
        % Check if output file already exists
        if exist(out_path, 'file')
            fprintf('Warning: Output file already exists and will be overwritten: %s\n', out_path);
            try
                delete(out_path);
            catch
                warning('Could not delete existing file: %s', out_path);
            end
        end
        
        % Write video with progress tracking
        fprintf('Writing video: %s\n', out_path);
        write_video_robust(input_h5_path, ds_path, out_path, fps, codec, stats);
        
        % Verify output file was created successfully
        if exist(out_path, 'file')
            file_info = dir(out_path);
            fprintf('Video created successfully: %s (%.2f MB)\n', out_path, file_info.bytes/1e6);
            out_files.(ds_name) = out_path;
        else
            error('Failed to create video file: %s', out_path);
        end
        
    catch ME
        error('Failed to process dataset "%s": %s', ds_name, ME.message);
    end
end

fprintf('\nVideo generation completed successfully.\n');
fprintf('Output files:\n');
for ds_name = fieldnames(out_files)'
    fprintf('  %s: %s\n', ds_name{1}, out_files.(ds_name{1}));
end
fprintf('Done.\n');

end % function

%% --- Helper functions ---

function stats = compute_percentiles_robust(h5file, dspath, prc_pair, pixel_frac, max_frames)
% Efficient percentile computation using stratified frame and pixel sampling
    fprintf('  Sampling frames and pixels for percentile calculation...\n');
    
    try
        info = h5info(h5file, dspath);
        sz = info.Dataspace.Size;
        H = sz(1); W = sz(2); T = sz(3);
        
        % Determine frame sampling strategy
        if T <= max_frames
            frame_idx = 1:T;
            fprintf('  Using all %d frames for sampling\n', T);
        else
            % Stratified sampling across time to capture temporal variations
            frame_idx = unique(round(linspace(1, T, max_frames)));
            fprintf('  Using stratified sample of %d/%d frames\n', length(frame_idx), T);
        end
        
        % Determine pixel sampling strategy
        total_pixels = H * W;
        n_pixels = max(1, round(pixel_frac * total_pixels));
        fprintf('  Sampling %d/%d pixels per frame (%.1f%%)\n', n_pixels, total_pixels, 100*pixel_frac);
        
        % Generate reproducible random pixel indices
        rng(42); % Fixed seed for reproducibility
        [r, c] = deal(randi(H, n_pixels, 1), randi(W, n_pixels, 1));
        lin_idx = sub2ind([H W], r, c);
        
        % Collect sample values with progress reporting
        vals = [];
        progress_step = max(1, floor(length(frame_idx) / 10));
        
        for idx = 1:length(frame_idx)
            t = frame_idx(idx);
            try
                frame = double(h5read(h5file, dspath, [1 1 t], [H W 1]));
                sample_vals = frame(lin_idx);
                
                % Filter out non-finite values
                valid_vals = sample_vals(isfinite(sample_vals));
                if ~isempty(valid_vals)
                    vals = [vals; valid_vals]; 
                end
                
                if mod(idx, progress_step) == 0
                    fprintf('  Sampling progress: %d/%d frames (%.1f%%)\n', idx, length(frame_idx), 100*idx/length(frame_idx));
                end
                
            catch ME
                warning('Failed to read frame %d: %s', t, ME.message);
            end
        end
        
        if isempty(vals)
            error('No valid pixel values found for percentile calculation');
        end
        
        % Compute robust percentiles
        [lo, hi] = deal(prctile(vals, prc_pair(1)), prctile(vals, prc_pair(2)));
        
        % Handle edge cases
        if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
            fprintf('  Warning: Invalid percentile range [%.2f, %.2f], using data extremes\n', lo, hi);
            valid_vals = vals(isfinite(vals));
            if ~isempty(valid_vals)
                [lo, hi] = deal(min(valid_vals), max(valid_vals));
            else
                [lo, hi] = deal(0, 1); % Fallback
            end
        end
        
        stats = struct('lo', lo, 'hi', hi, 'H', H, 'W', W, 'T', T, 'n_samples', length(vals));
        fprintf('  Percentile calculation complete: %d samples analyzed\n', length(vals));
        
    catch ME
        error('Failed to compute percentiles: %s', ME.message);
    end
end

function write_video_robust(h5file, dspath, out_path, fps, codec, stats)
% Stream frames to video with comprehensive progress reporting and error handling
    fprintf('  Initializing video writer...\n');
    
    try
        % Create video writer with error handling
        vr = VideoWriter(out_path, codec);
        vr.FrameRate = fps;
        
        % Set quality if supported by codec
        try
            if strcmpi(codec, 'Motion JPEG AVI')
               vr.Quality = 90;  % High quality for MJPEG
            end
        catch
            % Some codecs don't support Quality parameter
            fprintf('  Note: Quality parameter not supported for codec %s\n', codec);
        end
        
        open(vr);
        cleanup_obj = onCleanup(@() close_video_safely(vr));
        
        fprintf('  Writing %d frames to video...\n', stats.T);
        
        % Process frames with detailed progress reporting
        progress_steps = [10, 25, 50, 75, 90, 100]; % Progress milestones
        progress_idx = 1;
        start_time = tic;
        
        for t = 1:stats.T
            try
                % Read frame
                frame = h5read(h5file, dspath, [1 1 t], [stats.H stats.W 1]);
                
                % Convert to uint8 with robust scaling
                img8 = scale_to_uint8_robust(frame, stats.lo, stats.hi);
                
                % Ensure RGB format for video
                if size(img8, 3) == 1
                    img8 = repmat(img8, [1 1 3]);
                end
                
                % Write frame to video
                writeVideo(vr, img8);
                
                % Progress reporting at milestones
                progress_pct = 100 * t / stats.T;
                if progress_idx <= length(progress_steps) && progress_pct >= progress_steps(progress_idx)
                    elapsed = toc(start_time);
                    if progress_pct < 100
                        est_total = elapsed * 100 / progress_pct;
                        est_remaining = est_total - elapsed;
                        fprintf('  Progress: %.0f%% (%d/%d frames, %.1fs elapsed, ~%.1fs remaining)\n', ...
                            progress_pct, t, stats.T, elapsed, est_remaining);
                    else
                        fprintf('  Progress: 100%% (%d/%d frames, %.1fs total)\n', t, stats.T, elapsed);
                    end
                    progress_idx = progress_idx + 1;
                end
                
            catch ME
                warning('Failed to process frame %d: %s', t, ME.message);
                % Continue with next frame rather than failing completely
            end
        end
        
        fprintf('  Video writing completed in %.1fs\n', toc(start_time));    
    end
end

function close_video_safely(vr)
% Safely close video writer with error handling
try
    close(vr);
catch ME
    warning(ME, 'Error closing video writer: %s', ME.message);
end
end

function img8 = scale_to_uint8_robust(frame, lo, hi)
% Robust linear scaling with comprehensive input validation and error handling
    try
        % Convert to double for processing
        f = double(frame);
        
        % Handle non-finite values
        finite_mask = isfinite(f);
        if ~all(finite_mask(:))
            f(~finite_mask) = 0; % Replace non-finite values with 0
        end
        
        % Validate scaling parameters
        if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
            valid_vals = f(finite_mask);
            if ~isempty(valid_vals)
                [lo, hi] = deal(min(valid_vals), max(valid_vals));
            else
                [lo, hi] = deal(0, 1); % Fallback for pathological cases
            end
        end
        
        % Apply linear scaling with clamping
        if hi > lo
            f = (f - lo) / (hi - lo);
        else
            f = f * 0; % All values become 0 if no dynamic range
        end
        
        % Clamp to [0,1] range
        f = max(0, min(1, f));
        
        % Convert to uint8
        img8 = uint8(f * 255);
        
    catch ME
        % Emergency fallback: create blank frame
        warning(ME,'Frame scaling failed, using blank frame: %s', ME.message);
        img8 = zeros(size(frame), 'uint8');
    end
end