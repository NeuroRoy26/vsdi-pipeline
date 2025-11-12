function config = hdf5_parser(input_path, dataset_name, varargin)
    % Usage:
    % config = hdf5_parser('data/led_E1B1.h5','image_stack', ...
    %     'frame_rate',500.67,'memory_gb',8,'output_folder','data/parsed', ...
    %     'num_preview_frames',10,'make_plots',true);

    % -------------------- Inputs --------------------
    p = inputParser;
    addRequired(p, 'input_path', @ischar);
    addRequired(p, 'dataset_name', @ischar);
    addParameter(p, 'frame_rate', 500.67, @isnumeric);
    addParameter(p, 'memory_gb', 8, @isnumeric);
    addParameter(p, 'ref_start_pct', 0.1, @isnumeric);     % start reference ~10% in
    addParameter(p, 'stable_duration', 10, @isnumeric);    % seconds
    addParameter(p, 'output_folder', 'motion_corrected', @ischar);
    addParameter(p, 'num_preview_frames', 10, @isnumeric);
    addParameter(p, 'make_plots', true, @(x)islogical(x)||ismember(x,[0,1]));
    parse(p, input_path, dataset_name, varargin{:});
    R = p.Results;

    % -------------------- File / dataset info --------------------
    assert(exist(R.input_path,'file')==2, 'File not found: %s', R.input_path);
    dset = ['/' R.dataset_name];
    info = h5info(R.input_path, dset);
    sz = info.Dataspace.Size;

    % Determine dimensions and if we need permutation so that data is [H W T]
    if numel(sz)==3 && sz(3) > sz(1)
        dims = struct('height', sz(1), 'width', sz(2), 'frames', sz(3));
        needs_permute = false;
    elseif numel(sz)==3 && sz(1) > sz(3)
        % data is [T H W] -> will permute to [H W T] on read
        dims = struct('height', sz(2), 'width', sz(3), 'frames', sz(1));
        needs_permute = true;
    else
        error('Cannot determine frame dimension from size: %s', mat2str(sz));
    end
    T = dims.frames; H = dims.height; W = dims.width;

    if ~exist(R.output_folder,'dir'); mkdir(R.output_folder); end

    % -------------------- Sampling for interleave contrast --------------------
    sample_T = min(20, T);
    sample = read_block(R.input_path, dset, needs_permute, [1,1,1], [H,W,sample_T]);

    % Treat the interleaves generically as A/B (no channel assumptions)
    A = sample(:,:,1:2:end);
    B = sample(:,:,2:2:end);
    contrastA = std(double(A), [], 'all');
    contrastB = std(double(B), [], 'all');
    [higher_contrast, hi_is_A] = max([contrastA, contrastB]); 
    lower_contrast = min(contrastA, contrastB);
    contrast_ratio = higher_contrast / max(lower_contrast, eps);

    % -------------------- Reference frame range (structural stream = higher contrast) --------------------
    % We do not hardcode which interleave is "structural"; we use the higher-contrast stream.
    structural_fps = R.frame_rate / 2;
    ref_frame_count = floor(min(T/2, R.stable_duration * structural_fps));
    ref_start = max(1, round((T * R.ref_start_pct) / 2));  % in interleave units
    ref_end = max(ref_start, ref_start + ref_frame_count - 1);

    % -------------------- Auto tuning --------------------
    if contrast_ratio > 3
        alpha = 1.0; sigma = [1.0, 1.0, 0.1];
    elseif contrast_ratio > 2
        alpha = 1.5; sigma = [1.5, 1.5, 0.1];
    else
        alpha = 2.5; sigma = [2.0, 2.0, 0.2];
    end

    % -------------------- Buffer size for streaming --------------------
    % Approx 16-bit pixels assumed; adjust if needed.
    bytes_per_pixel = 2;
    frame_mb = H * W * bytes_per_pixel / (1024^2);
    % leave headroom for MATLAB + figures, target ~200% of memory_gb usable for I/O overlap
    buffer_size = max(1, min(100, floor(R.memory_gb * 200 / frame_mb)));
    buffer_size = min(buffer_size, T); % can't exceed total frames

    % -------------------- Intensity trace across all frames --------------------
    mean_intensity = nan(T,1);
    idx = 1;
    while idx <= T
        n = min(buffer_size, T - idx + 1);
        block = read_block(R.input_path, dset, needs_permute, [1,1,idx], [H,W,n]);
        % mean over H and W for each frame
        mean_intensity(idx:idx+n-1) = squeeze(mean(mean(double(block),1,'omitnan'),2,'omitnan'));
        idx = idx + n;
    end

    % -------------------- Preview frames (10 by default) --------------------
    num_preview = min(R.num_preview_frames, T);
    if num_preview > 0
        % evenly spaced indices, inclusive of first/last if possible
        preview_idx = unique(round(linspace(1, T, num_preview)));
        % read in minimal contiguous chunks if possible; simplest is per frame for clarity
        previews = cell(1, numel(preview_idx));
        for k = 1:numel(preview_idx)
            f = preview_idx(k);
            img = read_block(R.input_path, dset, needs_permute, [1,1,f], [H,W,1]);
            previews{k} = img;
        end
    else
        preview_idx = [];
        previews = {};
    end

    % -------------------- Build config --------------------
    interleave_labels = struct( ...
        'A_is_higher_contrast', logical(hi_is_A==1), ...
        'contrastA', contrastA, ...
        'contrastB', contrastB);

    config = struct( ...
        'input_path', R.input_path, ...
        'dataset_name', R.dataset_name, ...
        'output_folder', R.output_folder, ...
        'dimensions', dims, ...
        'needs_permute', needs_permute, ...
        'reference_frames_interleave_space', [ref_start, ref_end], ...
        'alpha', alpha, ...
        'sigma', sigma, ...
        'buffer_size', buffer_size, ...
        'contrast_ratio', contrast_ratio, ...
        'interleave', interleave_labels, ...
        'frame_rate', R.frame_rate, ...
        'mean_intensity', mean_intensity, ...
        'preview_indices', preview_idx);

    % -------------------- Print summary --------------------
    fprintf('Dataset: %s [%dx%dx%d]\n', R.dataset_name, H, W, T);
    fprintf('Interleave contrast A/B: %.3f / %.3f (ratio %.2f). Higher=%s\n', ...
        contrastA, contrastB, contrast_ratio, ternary(hi_is_A==1,'A','B'));
    fprintf('Reference (interleave space): %d-%d, alpha=%.2f, sigma=[%.1f %.1f %.1f]\n', ...
        ref_start, ref_end, alpha, sigma);

    if contrast_ratio < 1.5
        warning('Low contrast ratio (%.2f) - verify interleaved pattern.', contrast_ratio);
    end

    % -------------------- Plots --------------------
    if R.make_plots
        % Intensity trace
        f1 = figure('Color','w','Name','Mean intensity across frames');
        plot(1:T, mean_intensity, 'LineWidth', 1); grid on;
        xlabel('Frame'); ylabel('Mean intensity'); title('Mean intensity across all frames');
        saveas(f1, fullfile(R.output_folder,'mean_intensity.png'));

        % 10-frame (or fewer) preview
        if ~isempty(preview_idx)
            f2 = figure('Color','w','Name','Preview frames');
            t = tiledlayout(2, ceil(num_preview/2), 'Padding','compact','TileSpacing','compact');
            title(t, sprintf('Preview of %d frames (indices shown)', num_preview));
            for k = 1:numel(previews)
                nexttile;
                imagesc(previews{k}); axis image off;
                colormap(gray); title(sprintf('f=%d', preview_idx(k)));
            end
            saveas(f2, fullfile(R.output_folder,'preview_frames.png'));
        end
    end
end

% -------------------- Helpers --------------------
function block = read_block(h5path, dset, needs_permute, startHW1, countHW1)
    % startHW1: [Hstart Wstart Tstart] when already in [H W T] convention
    % If file is [T H W], adjust to [T H W] start/count and permute after read.
    H = countHW1(1); W = countHW1(2); Tcount = countHW1(3);
    Tstart = startHW1(3);

    if ~needs_permute
        % file is [H W T]
        start = [startHW1(1), startHW1(2), Tstart];
        count = [H, W, Tcount];
        block = h5read(h5path, dset, start, count);
    else
        % file is [T H W]
        start = [Tstart, startHW1(1), startHW1(2)];
        count = [Tcount, H, W];
        block = h5read(h5path, dset, start, count);
        block = permute(block, [2 3 1]); % -> [H W T]
    end
end

function out = ternary(cond, a, b), if cond, out=a; else, out=b; end
end
