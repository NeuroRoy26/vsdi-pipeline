%% Multi-File Comparison - Stacked Filmstrip with Time Axis
clc; clear all;
fprintf('\n--- Multi-File Comparison (Aligned & Timed) ---\n');

%% USER SETTINGS
FPS = 500;                  % Sampling Frequency (Hz)
FRAMES_TO_SHOW = 150;        % Number of frames to extract
NORMALIZE_EACH_FILE = true; % Z-score normalization
GAP_HEIGHT = 0;             % Gap between rows (pixels)
NUM_TIME_TICKS = 10;        % Number of time axis labels

%% 1. FILE SELECTION
fprintf('Select MULTIPLE processed files (Ctrl/Shift + Click)...\n');
[file_list, path_name] = uigetfile('*_dff.h5', 'Select Multiple Files', 'MultiSelect', 'on');

if isequal(file_list, 0)
    disp('Comparison canceled.');
    return;
end

% Ensure cell array
if ischar(file_list)
    file_list = {file_list};
end
num_files = length(file_list);

hWait = waitbar(0, 'Scanning dimensions...', 'Name', 'Generating Summary');

try
    %% 2. FIND MAX DIMENSIONS
    max_H = 0;
    max_W = 0;
    max_T = 0;
    
    for k = 1:num_files
        try
            info = h5info(fullfile(path_name, file_list{k}));
            dset_names = {info.Datasets.Name};
            
            % Find dataset
            if any(strcmp(dset_names, 'functional_dff'))
                dn = 'functional_dff';
            else
                dn = dset_names{1};
            end
            
            % Get dimensions
            idx = strcmp(dset_names, dn);
            dims = info.Datasets(idx).Dataspace.Size;
            
            max_H = max(max_H, dims(1));
            max_W = max(max_W, dims(2));
            max_T = max(max_T, dims(end));
        catch
            % Skip errors during scan
        end
    end
    
    fprintf('  Target Size: %dx%d pixels\n', max_H, max_W);
    fprintf('  Longest Recording: %d frames (%.2f sec)\n', max_T, max_T/FPS);
    
    %% 3. LOAD, RESIZE & PROCESS FILES
    stack_strips = cell(num_files, 1);
    file_labels = cell(num_files, 1);
    total_height = 0;
    
    for k = 1:num_files
        waitbar(k/num_files, hWait, sprintf('Processing %d/%d...', k, num_files));
        fname = file_list{k};
        fpath = fullfile(path_name, fname);
        
        try
            % Load dataset
            info = h5info(fpath);
            dset_names = {info.Datasets.Name};
            
            if any(strcmp(dset_names, 'functional_dff'))
                dn = '/functional_dff';
            else
                dn = ['/' dset_names{1}];
            end
            
            raw = h5read(fpath, dn);
            [H, W, T] = size(raw);
            
            % Subsample frames
            idx = round(linspace(1, T, FRAMES_TO_SHOW));
            sub_data = raw(:, :, idx);
            
            % Resize to match max dimensions
            if H ~= max_H || W ~= max_W
                sub_data = imresize(sub_data, [max_H, max_W]);
            end
            
            % Flatten to filmstrip
            strip = reshape(sub_data, max_H, []);
            
            % Normalize
            if NORMALIZE_EACH_FILE
                mu = mean(strip, 2, 'omitnan');
                sig = std(strip, 0, 2, 'omitnan');
                sig(sig == 0) = 1;
                strip = (strip - mu) ./ sig;
            end
            
            stack_strips{k} = strip;
            
            % Create clean label
            short_name = fname;
            short_name = strrep(short_name, '_vsd_corrected_dff', '');
            short_name = strrep(short_name, '_cropped_contrast', '');
            short_name = strrep(short_name, '.h5', '');
            short_name = strrep(short_name, '_', ' ');
            
            if length(short_name) > 25
                short_name = [short_name(1:22) '...'];
            end
            
            file_labels{k} = sprintf('#%d %s', k, short_name);
            total_height = total_height + max_H + GAP_HEIGHT;
            
        catch ME
            warning('Skipping %s: %s', fname, ME.message);
            stack_strips{k} = [];
        end
    end
    
    %% 4. STITCH FILES VERTICALLY
    waitbar(0.9, hWait, 'Stitching...');
    
    full_width = max_W * FRAMES_TO_SHOW;
    master_stack = nan(total_height, full_width);
    y_tick_pos = zeros(num_files, 1);
    curr_row = 1;
    
    for k = 1:num_files
        strip = stack_strips{k};
        if isempty(strip)
            continue;
        end
        
        [h_s, w_s] = size(strip);
        copy_w = min(w_s, full_width);
        master_stack(curr_row : curr_row + h_s - 1, 1:copy_w) = strip(:, 1:copy_w);
        
        y_tick_pos(k) = curr_row + h_s / 2;
        curr_row = curr_row + h_s + GAP_HEIGHT;
    end
    
    %% 5. PLOT WITH PROPER TIME AXIS
    figure('Name', 'Multi-File Comparison', 'Color', 'w', ...
           'Position', [50 100 1200 800]);
    
    % Set color limits
    vals = master_stack(~isnan(master_stack));
    if isempty(vals)
        vals = 0;
    end
    clim = [prctile(vals, 1), prctile(vals, 99)];
    
    % Display image
    hImg = imagesc(master_stack, clim);
    set(hImg, 'AlphaData', ~isnan(master_stack));
    
    colormap(jet);
    colorbar;
    axis normal;
    axis tight;
    
    % Configure time axis (X-axis)
    tick_frame_indices = round(linspace(1, FRAMES_TO_SHOW, NUM_TIME_TICKS));
    tick_pixel_pos = (tick_frame_indices - 0.5) * max_W;
    
    % Map to actual frames in longest recording
    actual_frames = round(linspace(1, max_T, FRAMES_TO_SHOW));
    time_labels_ms = round((actual_frames(tick_frame_indices) / FPS) * 1000);
    
    % Add T/2 midpoint label
    mid_frame_idx = round(FRAMES_TO_SHOW / 2);
    mid_pixel_pos = (mid_frame_idx - 0.5) * max_W;
    mid_time_ms = round((max_T / 2 / FPS) * 1000);
    
    % Combine all tick positions and labels
    all_tick_pos = [tick_pixel_pos, mid_pixel_pos];
    all_labels = arrayfun(@(x) sprintf('%d ms', x), time_labels_ms, 'UniformOutput', false);
    all_labels{end+1} = sprintf('%d ms', mid_time_ms);
    
    % Sort by position to keep labels in order
    [all_tick_pos, sort_idx] = sort(all_tick_pos);
    all_labels = all_labels(sort_idx);
    
    set(gca, 'XTick', all_tick_pos);
    set(gca, 'XTickLabel', all_labels);
    xlabel('Time (ms)', 'FontSize', 11, 'FontWeight', 'bold');
    
    % Configure file labels (Y-axis)
    set(gca, 'YTick', y_tick_pos, 'YTickLabel', file_labels, ...
        'TickLabelInterpreter', 'none', 'FontSize', 9);
    
    % Title
    title(sprintf('Multi-File Comparison | %d Frames @ %d Hz | Duration: %.2f sec', ...
          FRAMES_TO_SHOW, FPS, max_T/FPS), 'FontSize', 12);
    
    fprintf('\n✓ Done. Time axis calculated at %d Hz.\n', FPS);
    fprintf('  Total duration: %.2f seconds\n', max_T/FPS);
    
catch ME
    errordlg(ME.message, 'Error');
    rethrow(ME);
end

% Clean up
if exist('hWait', 'var') && isvalid(hWait)
    close(hWait);
end