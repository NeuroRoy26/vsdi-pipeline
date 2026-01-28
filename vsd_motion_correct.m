function output_file = vsd_motion_correct(input_h5_path, varargin)
% Full-pipeline VSD motion correction with automatic structural/functional detection.
% assumes your input to be raw .h5 files converted from .blk files
% Output file name is derived from the input file name + "_vsd_corrected.h5".
% See vsd_batch_runner.m for batch motion compensation
% Usage:
%   vsd_motion_correct('file.h5', ...
%       'DatasetName','image_stack', ...
%       'OutputFolder','data/motion_corrected', ...
%       'ReferenceFrames',80:200, ...
%       'FlowRegistrationPath','C:/flow_registration-main', ...
%       'OF', struct(...));
% **SUPER IMPORTANT**= make sure the flow_registration toolbox is configured
% note =displacement_fields output file (w.h5) are overwritten (change file name to preserve)
%% Parse inputs
p = inputParser;
addRequired(p, 'input_h5_path', @(s)ischar(s) || isstring(s));
addParameter(p, 'DatasetName','image_stack', @(s)ischar(s) || isstring(s));
addParameter(p, 'OutputFolder','data/motion_corrected', @(s)ischar(s) || isstring(s));
addParameter(p, 'ReferenceFrames',[], @(v)isnumeric(v) || isempty(v));
addParameter(p, 'FlowRegistrationPath','', @(s)ischar(s) || isstring(s));
defaultOF = struct('alpha',1.6, ...
                   'sigma',[1.5,1.5,0.1; 1.5,1.5,0.1], ...
                   'weight',[0.8,0.2], ...
                   'quality_setting','quality', ...
                   'bin_size',1, ...
                   'buffer_size',100, ...
                   'save_w',true, ...
                   'save_meta_info',true, ...
                   'verbose',true);
addParameter(p, 'OF', defaultOF, @isstruct);
parse(p, input_h5_path, varargin{:});
% Convert to char arrays for compatibility
dataset_name      = char(p.Results.DatasetName);
output_folder     = char(p.Results.OutputFolder);
reference_frames  = p.Results.ReferenceFrames;
flowreg_path      = char(p.Results.FlowRegistrationPath);
OF                = p.Results.OF;
% Validate input file exists
if ~exist(input_h5_path, 'file')
    error('Input HDF5 file does not exist: %s', input_h5_path);
end
% Add Flow-Registration path if provided and valid
if ~isempty(flowreg_path)
    if isfolder(flowreg_path)
        addpath(flowreg_path);
    else
        warning('FlowRegistrationPath does not exist: %s', flowreg_path);
    end
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
%% Load and validate data
fprintf('Loading HDF5 dataset "/%s" from %s ...\n', dataset_name, input_h5_path);
try
    % Check if dataset exists
    info = h5info(input_h5_path);
    dataset_names = {info.Datasets.Name};
    if ~any(strcmp(dataset_names, dataset_name))
        error('Dataset "/%s" not found. Available datasets: %s', ...
            dataset_name, strjoin(dataset_names, ', '));
    end
    
    data = h5read(input_h5_path, ['/' dataset_name]);
catch ME
    error('Failed to read HDF5 dataset: %s', ME.message);
end
% Ensure orientation [height, width, frames] and validate dimensions
if ndims(data) ~= 3
    error('Data must be 3-dimensional (height x width x frames), got %d dimensions', ndims(data));
end
% Handle different possible orientations
sz = size(data);
if sz(1) == 1500  % Likely frames in first dimension
    data = permute(data, [2, 3, 1]);
    fprintf('Data reoriented from %dx%dx%d to frames-last format.\n', sz(1), sz(2), sz(3));
elseif sz(3) == 1500  % Likely frames in third dimension (correct)
    % Already correct
elseif sz(2) == 1500  % Likely frames in second dimension
    data = permute(data, [1, 3, 2]);
    fprintf('Data reoriented from %dx%dx%d to frames-last format.\n', sz(1), sz(2), sz(3));
end
[height, width, total_frames] = size(data);
fprintf('Data: %dx%dx%d (H x W x T)\n', height, width, total_frames);
% Validate minimum frame count
if total_frames < 4
    error('Insufficient frames for processing: %d (minimum 4 required)', total_frames);
end

% <<< MODIFIED SECTION START >>>
%% Dynamically assign frames based on pair-wise contrast
fprintf('Assigning structural/functional frames based on pair-wise contrast...\n');
dataD = double(data);
% Calculate per-frame contrast
means = zeros(1, total_frames);
stds = zeros(1, total_frames);
for t = 1:total_frames
    frame = dataD(:, :, t);
    means(t) = mean(frame(:));
    stds(t) = std(frame(:));
end
contrast = stds ./ max(means, eps); % Avoid division by zero
% Initialize index arrays
structural_indices = [];
functional_indices = [];
% Iterate through frame pairs to assign based on local contrast
for t = 1:2:total_frames-1
    if contrast(t) > contrast(t+1)
        structural_indices(end+1) = t;
        functional_indices(end+1) = t+1;
    else
        structural_indices(end+1) = t+1;
        functional_indices(end+1) = t;
    end
end
if isempty(structural_indices) || isempty(functional_indices)
    error('Could not assign frames based on contrast. Check data quality.');
end
% Create data stacks from the dynamically generated indices
structural_frames = data(:, :, structural_indices);
functional_frames = data(:, :, functional_indices);
fprintf('Assigned %d structural and %d functional frames.\n', ...
    numel(structural_indices), numel(functional_indices));
%% Map reference frames into structural index space
if isempty(reference_frames)
    nS = size(structural_frames,3);
    if nS < 3
        error('Insufficient structural frames: %d (minimum 3 required)', nS);
    end
    ref_lo = max(1, floor(0.375*nS));
    ref_hi = min(nS, ceil(0.625*nS));
    ref_indices_struct = ref_lo:ref_hi;
    fprintf('ReferenceFrames not provided. Using structural %d:%d (middle portion).\n', ref_lo, ref_hi);
else
    % Filter user-provided frames to those that are valid and were assigned as structural
    rf = round(reference_frames(:)');
    rf = rf(rf >= 1 & rf <= total_frames);
    
    % Find which of the requested reference frames exist in our structural list
    valid_structural_ref_frames = intersect(rf, structural_indices);
    
    % Find the indices of these frames within the structural_frames stack
    [~, ref_indices_struct] = ismember(valid_structural_ref_frames, structural_indices);
    ref_indices_struct = ref_indices_struct(ref_indices_struct > 0)'; % Ensure valid indices and row vector
    
    % Fallback if no valid reference frames were found
    if isempty(ref_indices_struct)
        nS = size(structural_frames,3);
        if nS < 3
            error('Insufficient structural frames: %d (minimum 3 required)', nS);
        end
        ref_indices_struct = max(1,floor(0.4*nS)) : min(nS,ceil(0.6*nS));
        fprintf('Provided ReferenceFrames had no valid structural frames. Using default %d:%d.\n', ...
            ref_indices_struct(1), ref_indices_struct(end));
    else
        fprintf('Using %d mapped reference frames in structural indexing.\n', numel(ref_indices_struct));
    end
end
% <<< MODIFIED SECTION END >>>

%% Create temporary multi-channel HDF5 for Flow-Registration
temp_file = fullfile(output_folder, 'temp_multichannel.h5');
if exist(temp_file, 'file')
    delete(temp_file);
end
fprintf('Creating Flow-Registration input: %s\n', temp_file);
try
    h5create(temp_file, '/ch1', size(structural_frames), 'Datatype', class(structural_frames));
    h5write(temp_file, '/ch1', structural_frames);
    h5create(temp_file, '/ch2', size(functional_frames), 'Datatype', class(functional_frames));
    h5write(temp_file, '/ch2', functional_frames);
catch ME
    cleanup_temp(temp_file);
    error('Failed to create temporary HDF5 file: %s', ME.message);
end
%% Configure Flow-Registration options
try
    options = OF_options( ...
        'input_file',     temp_file, ...
        'output_path',    output_folder, ...
        'output_format',  'HDF5', ...
        'alpha',          getfield_safe(OF,'alpha',defaultOF.alpha), ...
        'sigma',          getfield_safe(OF,'sigma',defaultOF.sigma), ...
        'weight',         getfield_safe(OF,'weight',defaultOF.weight), ...
        'quality_setting',getfield_safe(OF,'quality_setting',defaultOF.quality_setting), ...
        'bin_size',       getfield_safe(OF,'bin_size',defaultOF.bin_size), ...
        'buffer_size',    getfield_safe(OF,'buffer_size',defaultOF.buffer_size), ...
        'reference_frames', ref_indices_struct, ...
        'save_w',         getfield_safe(OF,'save_w',defaultOF.save_w), ...
        'save_meta_info', getfield_safe(OF,'save_meta_info',defaultOF.save_meta_info), ...
        'verbose',        getfield_safe(OF,'verbose',defaultOF.verbose) );
    fprintf('Flow-Registration options configured.\n');
catch ME
    cleanup_temp(temp_file);
    error('Failed to create OF_options: %s', ME.message);
end
%% Quick reader sanity-check
try
    vr = options.get_video_file_reader();
    fprintf('Reader OK — Channels: %d | Frames: %d | Size: %dx%d | Type: %s\n', ...
        vr.n_channels, vr.frame_count, vr.get_height(), vr.get_width(), vr.mat_data_type);
catch ME
    cleanup_temp(temp_file);
    error('Failed to create video reader: %s', ME.message);
end
%% Run full pipeline
fprintf('Running compensate_recording (full pipeline)...\n');
try
    compensate_recording(options);
    fprintf('Motion correction finished.\n');
catch ME
    cleanup_temp(temp_file);
    error('compensate_recording failed: %s', ME.message);
end
%% Collect outputs and consolidate
try
    structural_corrected = [];
    functional_corrected = [];
    ch1file = fullfile(output_folder, 'ch1.hdf5');
    ch2file = fullfile(output_folder, 'ch2.hdf5');
    compfile = fullfile(output_folder, 'compensated.hdf5');
    if exist(ch1file,'file') && exist(ch2file,'file')
        try
            structural_corrected = h5read(ch1file, '/ch1');
            functional_corrected = h5read(ch2file, '/ch2');
        catch ME
            cleanup_temp(temp_file);
            error('Failed to read corrected data from ch1.hdf5/ch2.hdf5: %s', ME.message);
        end
    elseif exist(compfile,'file')
        try
            info = h5info(compfile);
            names = {info.Datasets.Name};
            if any(strcmp(names,'ch1')) && any(strcmp(names,'ch2'))
                structural_corrected = h5read(compfile, '/ch1');
                functional_corrected = h5read(compfile, '/ch2');
            else
                cleanup_temp(temp_file);
                error('Unexpected dataset structure in compensated.hdf5. Datasets: %s', strjoin(names, ', '));
            end
        catch ME
            cleanup_temp(temp_file);
            error('Failed to read compensated.hdf5: %s', ME.message);
        end
    else
        cleanup_temp(temp_file);
        error('No expected Flow-Registration output found (ch1.hdf5/ch2.hdf5 or compensated.hdf5).');
    end
    % Validate output data dimensions
    if isempty(structural_corrected) || isempty(functional_corrected)
        cleanup_temp(temp_file);
        error('Motion correction produced empty results.');
    end
    
    if ~isequal(size(structural_corrected), size(structural_frames)) || ...
       ~isequal(size(functional_corrected), size(functional_frames))
        warning('Output data dimensions differ from input. This may indicate processing issues.');
    end
    % Save consolidated output (mirrors input file name)
    output_file = fullfile(output_folder, [base '_vsd_corrected.h5']);
    if exist(output_file,'file')
        delete(output_file);
    end
    
    try
        h5create(output_file, '/structural', size(structural_corrected), 'Datatype', class(structural_corrected));
        h5write(output_file, '/structural', structural_corrected);
        h5create(output_file, '/functional', size(functional_corrected), 'Datatype', class(functional_corrected));
        h5write(output_file, '/functional', functional_corrected);
        fprintf('Consolidated output saved to: %s\n', output_file);
    catch ME
        cleanup_temp(temp_file);
        error('Failed to save consolidated output: %s', ME.message);
    end
catch ME
    cleanup_temp(temp_file);
    rethrow(ME);
end
%% Optional stats
stats_file = fullfile(output_folder, 'statistics.mat');
if exist(stats_file,'file')
    try
        stats = load(stats_file);
        fprintf('\nMotion statistics:\n');
        if isfield(stats,'mean_disp') && ~isempty(stats.mean_disp)
            fprintf('  Mean displacement: %.2f ± %.2f px\n', mean(stats.mean_disp), std(stats.mean_disp));
        end
        if isfield(stats,'max_disp') && ~isempty(stats.max_disp)
            fprintf('  Max displacement: %.2f px\n', max(stats.max_disp));
        end
        if isfield(stats,'mean_div') && ~isempty(stats.mean_div)
            fprintf('  Mean divergence: %.4f ± %.4f\n', mean(stats.mean_div), std(stats.mean_div));
        end
        if isfield(stats,'mean_translation') && ~isempty(stats.mean_translation)
            fprintf('  Mean translation: %.2f ± %.2f px\n', mean(stats.mean_translation), std(stats.mean_translation));
        end
    catch
        fprintf('Could not load motion statistics.\n');
    end
end
cleanup_temp(temp_file);
fprintf('Done.\n');
% end % function
%% --- helpers ---
function out = getfield_safe(s, name, default)
    if isfield(s, name)
        out = s.(name);
    else
        out = default;
    end
end
function cleanup_temp(temp_file)
    if exist(temp_file,'file')
        try
            delete(temp_file);
            fprintf('Temporary Flow-Registration input removed.\n');
        catch
            warning('Failed to remove temporary file: %s', temp_file);
        end
    end
end
% This helper is no longer used in the main logic but is kept for potential future use.
function r = ternary(cond, a, b)
    if cond
        r = a;
    else
        r = b;
    end
end
fprintf('Run single_trial or trial_averaging script after this\n');
end