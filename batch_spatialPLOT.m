%% COMPARE_SPATIAL_WATERFALLS.m
% Select multiple reconstructed_ICs files.
% Plots their Spatial Waterfalls side-by-side in ONE figure for comparison.

clear; clc; close all;

%% 1. SETTINGS
sign_ass        = -1;    % Set -1 if signals are inverted
keep_percentile = 85;    % Keep top 15% active pixels
stimulus_frame  = 376;   % Frame of stimulus (0ms)
sort_method     = 'latency'; % 'latency' or 'intensity'
c_range_percent = 98;    % Contrast clipping

%% 2. SELECT FILES
if exist('data', 'dir'), start_path = 'data/'; else, start_path = pwd; end

fprintf('Select MULTIPLE reconstruction files (Ctrl+Click)...\n');
[file_names, file_path] = uigetfile(fullfile(start_path, '*.mat'), ...
                                    'Select Files', 'MultiSelect', 'on');

if isequal(file_names, 0), error('Canceled.'); end
if ischar(file_names), file_names = {file_names}; end

num_files = length(file_names);
fprintf('Selected %d files.\n', num_files);

%% 3. PREPARE BIG FIGURE
f = figure('Name', 'Spatial Comparison', 'Position', [50 50 1400 900]);
t = tiledlayout('flow', 'TileSpacing', 'compact', 'Padding', 'compact'); 

%% 4. PROCESS LOOP
for i = 1:num_files
    full_path = fullfile(file_path, file_names{i});
    loaded_data = load(full_path);
    
    % --- Load Movie ---
    if isfield(loaded_data, 'reconstructed_movie'), M = double(loaded_data.reconstructed_movie);
    elseif isfield(loaded_data, 'mov_recon'), M = double(loaded_data.mov_recon);
    elseif isfield(loaded_data, 'mov'), M = double(loaded_data.mov);
    else, continue; end
    
    if isfield(loaded_data, 'Fs'), Fs = loaded_data.Fs; else, Fs = 250; end
    [H, W, T] = size(M);
    
    % --- Process (Baseline & Sign) ---
    base_idx = max(1, stimulus_frame-76) : max(1, stimulus_frame-1);
    M_sub = sign_ass * (M - mean(M(:,:,base_idx), 3));
    
    % Light smoothing to de-noise pixels
    M_smooth = zeros(H, W, T);
    for fr = 1:T, M_smooth(:,:,fr) = imgaussfilt(M_sub(:,:,fr), 1.0); end
    
    % --- Flatten & Sort ---
    pixels = reshape(M_smooth, H*W, T);
    variance = var(pixels, 0, 2);
    thresh = prctile(variance, keep_percentile);
    active_pix = pixels(variance > thresh, :);
    
    if size(active_pix, 1) < 10
        warning('File %d has <10 active pixels. Skipping.', i);
        nexttile; title(sprintf('%s (Empty)', file_names{i}), 'Interpreter', 'none');
        continue;
    end
    
    % SORT
    if strcmp(sort_method, 'latency')
        [~, max_idx] = max(active_pix, [], 2);
        [~, order] = sort(max_idx);
    else
        [~, order] = sort(max(active_pix, [], 2), 'descend');
    end
    sorted_pix = active_pix(order, :);
    
    % --- PLOT IN SUBPLOT ---
    nexttile;
    time_axis = ((1:T) - stimulus_frame) * (1000/Fs);
    imagesc(time_axis, 1:size(sorted_pix,1), sorted_pix);
    
    colormap('jet'); 
    % Local contrast stretch for each plot
    caxis(prctile(sorted_pix(:), [100-c_range_percent, c_range_percent]));
    
    % Clean Title
    short_name = strrep(file_names{i}, 'reconstructed_ICs_', '');
    short_name = strrep(short_name, '.mat', '');
    title(short_name, 'Interpreter', 'none', 'FontSize', 10);
    
    if i == 1
        ylabel('Sorted Pixels'); % Only label Y on first plot to save space
    else
        set(gca, 'YTick', []);
    end
    xlabel('Time (ms)');
    xline(0, '--w');
end

cb = colorbar; 
cb.Layout.Tile = 'east';
cb.Label.String = '\DeltaF/F';

sgtitle(sprintf('Comparison of Spatial Dynamics (n=%d)', num_files));
fprintf('Comparison plot generated.\n');