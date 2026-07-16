clc; clear; close all;

%% 1. Select Files
fprintf('--- 1. Select BEFORE File (Raw) ---\n');
[fName1, fPath1] = uigetfile('*.h5', 'Select BEFORE File');
if isequal(fName1, 0), return; end
file_before = fullfile(fPath1, fName1);

fprintf('--- 2. Select AFTER File (Processed) ---\n');
[fName2, fPath2] = uigetfile(fullfile(fPath1, '*.h5'), 'Select AFTER File');
if isequal(fName2, 0), return; end
file_after = fullfile(fPath2, fName2);

%% 2. Identify Datasets (Simplest Approach)
% We just assume the largest dataset in each file is the movie.
info1 = h5info(file_before);

% Calculate total size (product of dimensions) for each dataset
sizes1 = zeros(1, length(info1.Datasets));
for i = 1:length(info1.Datasets)
    sizes1(i) = prod(info1.Datasets(i).Dataspace.Size);
end
[~, idx1] = max(sizes1); % Find largest dataset by total elements

ds_name1 = ['/' info1.Datasets(idx1).Name];
dims1 = info1.Datasets(idx1).Dataspace.Size;

info2 = h5info(file_after);

% Calculate total size for AFTER file
sizes2 = zeros(1, length(info2.Datasets));
for i = 1:length(info2.Datasets)
    sizes2(i) = prod(info2.Datasets(i).Dataspace.Size);
end
[~, idx2] = max(sizes2);

ds_name2 = ['/' info2.Datasets(idx2).Name];
dims2 = info2.Datasets(idx2).Dataspace.Size;

fprintf('\nFiles Selected:\n');
fprintf('  1. BEFORE: %s (Dataset: %s)\n', fName1, ds_name1);
fprintf('  2. AFTER:  %s (Dataset: %s)\n', fName2, ds_name2);

%% 3. Determine Frame Range
max_frame = min(dims1(3), dims2(3));
fprintf('\nTotal frames available: %d\n', max_frame);
fprintf('Use the slider to browse through frames...\n');

%% 4. Create Interactive Figure with Slider
fig = figure('Name', 'Frame Browser', 'NumberTitle', 'off', ...
             'Position', [100, 100, 1200, 500]);

% Create axes for BEFORE image
ax1 = subplot(1, 2, 1);
img1 = imagesc(zeros(dims1(1), dims1(2)));
axis image; colormap gray; colorbar;
title_before = title(sprintf('BEFORE: %s\nFrame: 1', fName1), 'Interpreter', 'none');

% Create axes for AFTER image
ax2 = subplot(1, 2, 2);
img2 = imagesc(zeros(dims2(1), dims2(2)));
axis image; colormap gray; colorbar;
title_after = title(sprintf('AFTER: %s\nFrame: 1', fName2), 'Interpreter', 'none');

% Create slider
slider = uicontrol('Style', 'slider', ...
                   'Min', 1, 'Max', max_frame, ...
                   'Value', 1, ...
                   'SliderStep', [1/(max_frame-1), 10/(max_frame-1)], ...
                   'Position', [100, 20, 1000, 20], ...
                   'Callback', @(src, evt) updateFrame(src, evt));

% Create frame number label
frame_label = uicontrol('Style', 'text', ...
                        'Position', [500, 45, 200, 20], ...
                        'String', 'Frame: 1', ...
                        'FontSize', 10, ...
                        'FontWeight', 'bold');

% Store data in figure's UserData
data_struct.file_before = file_before;
data_struct.file_after = file_after;
data_struct.ds_name1 = ds_name1;
data_struct.ds_name2 = ds_name2;
data_struct.dims1 = dims1;
data_struct.dims2 = dims2;
data_struct.img1 = img1;
data_struct.img2 = img2;
data_struct.title_before = title_before;
data_struct.title_after = title_after;
data_struct.frame_label = frame_label;
data_struct.fName1 = fName1;
data_struct.fName2 = fName2;
fig.UserData = data_struct;

% Load and display initial frame
updateFrame(slider, []);

%% Callback Function
function updateFrame(src, ~)
    fig = src.Parent;
    data = fig.UserData;
    
    % Get current frame index from slider
    frame_idx = round(src.Value);
    
    % Load BEFORE frame
    frame_before = h5read(data.file_before, data.ds_name1, ...
                          [1, 1, frame_idx], [data.dims1(1), data.dims1(2), 1]);
    frame_before = double(frame_before);
    
    % Load AFTER frame
    frame_after = h5read(data.file_after, data.ds_name2, ...
                         [1, 1, frame_idx], [data.dims2(1), data.dims2(2), 1]);
    frame_after = double(frame_after);
    
    % Update images
    set(data.img1, 'CData', frame_before);
    set(data.img2, 'CData', frame_after);
    
    % Update titles
    set(data.title_before, 'String', sprintf('BEFORE: %s\nFrame: %d', data.fName1, frame_idx));
    set(data.title_after, 'String', sprintf('AFTER: %s\nFrame: %d', data.fName2, frame_idx));
    
    % Update frame label
    set(data.frame_label, 'String', sprintf('Frame: %d / %d', frame_idx, data.dims1(3)));
end