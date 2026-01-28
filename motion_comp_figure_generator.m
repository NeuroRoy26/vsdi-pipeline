%% generate_flow_figures.m
% Generates Flow-Registration figures:
% (E) displacement vector field
% (F) divergence over time
%
% REQUIREMENTS:
%   - Requires w.h5 file
%   - Requires Image Processing Toolbox (for imgaussfilt)
clear; clc;

%% ---------------- USER SETTINGS ----------------
frameRate     = [];    % set (Hz) if you want time in seconds, else leave empty
frame_frac    = 0.5;   % fraction of sequence for vector field (0–1)
subsample     = 10;    % arrow density
smooth_sigma  = 2;     % spatial smoothing for visualization ONLY

%% ------------------------------------------------
%% Select w.h5 file using file explorer
fprintf('Please select the w.h5 file...\n');
[filename, pathname] = uigetfile({'*.h5;*.hdf5', 'HDF5 Files (*.h5, *.hdf5)'; ...
                                  '*.*', 'All Files (*.*)'}, ...
                                  'Select w.h5 displacement file');

% Check if user cancelled
if isequal(filename, 0)
    fprintf('User cancelled file selection. Exiting.\n');
    return;
end

% Construct full file path
wfile = fullfile(pathname, filename);
fprintf('Selected file: %s\n', wfile);

%% Verify file contains required datasets
try
    info = h5info(wfile);
    datasets = {info.Datasets.Name};
    
    if ~ismember('u', datasets) || ~ismember('v', datasets)
        error('File does not contain required datasets /u and /v');
    end
    
    fprintf('File validated successfully.\n');
catch ME
    error('Error reading HDF5 file: %s', ME.message);
end

%% Load displacement fields
u = h5read(wfile, '/u');   % [H x W x T]
v = h5read(wfile, '/v');
[H,W,T] = size(u);
fprintf('Loaded displacement fields: %dx%dx%d\n', H, W, T);

%% =========================================================
%% FIGURE E — Displacement vector field (quiver)
%% =========================================================

% Ask user to select structural/background image
fprintf('\nPlease select a structural/background image (optional)...\n');
[bg_filename, bg_pathname] = uigetfile({'*.tif;*.tiff;*.png;*.jpg;*.jpeg;*.bmp', 'Image Files (*.tif, *.png, *.jpg, *.bmp)'; ...
                                        '*.h5;*.hdf5', 'HDF5 Files (*.h5, *.hdf5)'; ...
                                        '*.*', 'All Files (*.*)'}, ...
                                        'Select background/structural image (Cancel to skip)');

% Load background image if selected
bg_img = [];
if ~isequal(bg_filename, 0)
    bg_path = fullfile(bg_pathname, bg_filename);
    fprintf('Loading background image: %s\n', bg_filename);
    
    try
        [~,~,ext] = fileparts(bg_filename);
        if strcmpi(ext, '.h5') || strcmpi(ext, '.hdf5')
            % For HDF5 files, show available datasets and let user choose
            info = h5info(bg_path);
            fprintf('Available datasets in %s:\n', bg_filename);
            for i = 1:length(info.Datasets)
                fprintf('  [%d] %s - size: %s\n', i, info.Datasets(i).Name, ...
                        mat2str(info.Datasets(i).Dataspace.Size));
            end
            dataset_idx = input('Enter dataset number to use: ');
            if dataset_idx > 0 && dataset_idx <= length(info.Datasets)
                dataset_name = ['/' info.Datasets(dataset_idx).Name];
                bg_img = h5read(bg_path, dataset_name);
                % If 3D, take mean or first frame
                if ndims(bg_img) == 3
                    fprintf('3D data detected. Using mean projection.\n');
                    bg_img = mean(bg_img, 3);
                end
            end
        else
            % Regular image file
            bg_img = imread(bg_path);
            % Convert to grayscale if RGB
            if size(bg_img, 3) == 3
                bg_img = rgb2gray(bg_img);
            end
        end
        
        % Ensure background image matches displacement field size
        if ~isequal(size(bg_img), [H, W])
            fprintf('Resizing background image from %dx%d to %dx%d\n', ...
                    size(bg_img,1), size(bg_img,2), H, W);
            bg_img = imresize(bg_img, [H, W]);
        end
        
        bg_img = double(bg_img);
        fprintf('Background image loaded successfully.\n');
    catch ME
        warning('Could not load background image: %s', ME.message);
        bg_img = [];
    end
else
    fprintf('No background image selected.\n');
end

t = max(1, round(frame_frac * T));
u_t = u(:,:,t);
v_t = v(:,:,t);

% Smooth for visualization only
u_t = imgaussfilt(u_t, smooth_sigma);
v_t = imgaussfilt(v_t, smooth_sigma);

% Subsample
u_ds = u_t(1:subsample:end, 1:subsample:end);
v_ds = v_t(1:subsample:end, 1:subsample:end);

% Create coordinate grids for quiver
[Y_ds, X_ds] = meshgrid(1:subsample:W, 1:subsample:H);

figure('Color','k', 'Name', 'Displacement Vector Field');

% Display background image if available
if ~isempty(bg_img)
    % Normalize and display background
    bg_norm = (bg_img - min(bg_img(:))) / (max(bg_img(:)) - min(bg_img(:)));
    imagesc(bg_norm);
    colormap gray;
    hold on;
    % Use colored arrows on grayscale background
    quiver(X_ds, Y_ds, u_ds, v_ds, 1.0, 'Color', [1 0.3 0.3], 'LineWidth', 1.5);
else
    % No background - use white arrows on black
    quiver(X_ds, Y_ds, u_ds, v_ds, 1.0, 'w', 'LineWidth', 1.5);
end

axis image ij off; 
title(sprintf('Displacement field (frame %d/%d)', t, T), 'Color','w');
set(gca,'Color','k');

%% =========================================================
%% FIGURE F — Mean divergence over time
%% =========================================================
fprintf('Computing divergence over time...\n');
mean_div = zeros(T,1);
for k = 1:T
    uk = u(:,:,k);
    vk = v(:,:,k);
    [ux, ~] = gradient(uk);
    [~, vy] = gradient(vk);
    div = ux + vy;
    mean_div(k) = mean(abs(div(:)));   % robust metric
end

% Optional smoothing (matches paper style)
mean_div = movmean(mean_div, 5);

% Time axis
if isempty(frameRate)
    x = 1:T;
    xlab = 'Frame';
else
    x = (0:T-1) / frameRate;
    xlab = 'Time (s)';
end

figure('Color','w', 'Name', 'Divergence Over Time');
plot(x, mean_div, 'LineWidth', 2, 'Color', [0 0.4470 0.7410]);
xlabel(xlab, 'FontSize', 12);
ylabel('Mean |divergence|', 'FontSize', 12);
title('Divergence of displacement field over time', 'FontSize', 14);
grid on;
box on;

fprintf('\n===========================================\n');
fprintf('Figures generated successfully!\n');
fprintf('File: %s\n', filename);
fprintf('Frames analyzed: %d\n', T);
fprintf('===========================================\n');