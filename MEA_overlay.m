% MEA_Overlay_FlexMEA72_Corrected.m
clear; clc; close all;

%% ========================================================================
%  USER CALIBRATION SETTINGS (ADJUST THESE TO ALIGN!)
% ========================================================================
% 1. SCALING: Controls the size of the MEA grid relative to the image.
%    If the grid is GIANT, INCREASE this number.
%    (Example: If your FOV is 10mm wide and image is 500px, res is 20 um/px)
MICRONS_PER_PIXEL = 14.3; % Try increasing this if grid is too big (e.g. 15, 20, 50)

% 2. ROTATION: Rotates the MEA grid clockwise (in degrees)
ROTATION_DEG = -30;         

% 3. POSITIONING: Fine tune the center position (in pixels)
NUDGE_X_PX = 0;           % + moves grid Right, - moves Left
NUDGE_Y_PX = 6;           % + moves grid Down,  - moves Up

% 4. VISUALS
SIGMA = 2.0;              % Gaussian smoothing for the VSD image
SATURATION_PCT = 99.0;    % Contrast setting

%% ========================================================================
%  1. DATA LOADING (Preserved from your script)
% ========================================================================
fprintf('Loading data...\n');
data_found = false;

% Check workspace variables
if exist('reconstructed_movie', 'var'), M = double(reconstructed_movie); data_found = true;
elseif exist('mov_recon', 'var'), M = double(mov_recon); data_found = true;
elseif exist('mov', 'var'), M = double(mov); data_found = true;
end

% Check files if variable not found
if ~data_found
    if ~exist('data', 'dir')
         % Fallback for direct run without data folder, creates dummy noise data
         fprintf('! No data found. Generating DUMMY DATA for demonstration.\n');
         M = rand(400, 400, 50); 
         sampling_rate = 250;
    else
        files = dir('data/reconstructed_ICs_*.mat');
        if isempty(files), error('No reconstruction files found in /data!'); end
        
        if length(files) == 1, file_idx = 1;
        else, file_idx = 1; 
        end % Default to first
        loaded_data = load(fullfile('data', files(file_idx).name));
        
        if isfield(loaded_data, 'reconstructed_movie')
            M = double(loaded_data.reconstructed_movie);
        elseif isfield(loaded_data, 'mov')
            M = double(loaded_data.mov);
        else
            error('Could not find movie variable in .mat file.');
        end
        
        if isfield(loaded_data, 'Fs'), sampling_rate = loaded_data.Fs; else, sampling_rate = 250; end
    end
end

[H, W, T] = size(M);
fprintf('Data Loaded: %d x %d pixels, %d frames.\n', H, W, T);

% Calculate Image Center
img_center_x = W / 2;
img_center_y = H / 2;

%% ========================================================================
%  2. GENERATE FLEXMEA72 GEOMETRY
% ========================================================================
% Specs from FlexMEA72 Datasheet
pitch_x_um = 625; 
pitch_y_um = 750;
rows = 9; % A, B, C, D, E, F, G, H, J
cols = 8; % 1 - 8

% Create Grid (Cols 1-8, Rows 1-9)
[gx_idx, gy_idx] = meshgrid(1:cols, 1:rows);

% Define Exclusion Mask (GND and REF electrodes)
% Based on FlexMEA72 Layout Page 2 (Blue pads are GND/REF)
% Row Indices: A=1, B=2, ... G=7, H=8, J=9.
valid_mask = true(rows, cols);

% Exclude Row A (1): A4, A5 (GND)
valid_mask(1, 4:5) = false; 

% Exclude Row B (2): B4, B5 (REF)
valid_mask(2, 4:5) = false;

% Exclude Row G (7): G1, G8 (REF)
valid_mask(7, 1) = false;
valid_mask(7, 8) = false;

% Exclude Row J (9): J1, J8 (GND)
valid_mask(9, 1) = false;
valid_mask(9, 8) = false;

% --- Calculate Physical Coordinates (microns) centered at (0,0) ---
% We center the grid so (0,0) is the geometric center of the array
phys_x = (gx_idx - 4.5) * pitch_x_um; % 4.5 is center of 1..8
phys_y = (gy_idx - 5.0) * pitch_y_um; % 5.0 is center of 1..9

% --- Apply Calibration (Microns -> Pixels) ---
mea_px_x = phys_x / MICRONS_PER_PIXEL;
mea_px_y = phys_y / MICRONS_PER_PIXEL;

% --- Apply Rotation ---
theta = deg2rad(ROTATION_DEG);
R = [cos(theta), -sin(theta); sin(theta), cos(theta)];

rot_x = zeros(size(mea_px_x));
rot_y = zeros(size(mea_px_y));

for i = 1:numel(mea_px_x)
    pt = R * [mea_px_x(i); mea_px_y(i)];
    rot_x(i) = pt(1);
    rot_y(i) = pt(2);
end

% --- Apply Translation (Center on image + Nudge) ---
final_x = rot_x + img_center_x + NUDGE_X_PX;
final_y = rot_y + img_center_y + NUDGE_Y_PX;

% Filter for only recording electrodes
rec_x = final_x(valid_mask);
rec_y = final_y(valid_mask);
ref_x = final_x(~valid_mask); % If you ever want to see the excluded ones
ref_y = final_y(~valid_mask);

%% ========================================================================
%  3. VISUALIZATION
% ========================================================================
fprintf('Generating Overlay...\n');

% Prepare a background frame (e.g., mean of first few frames or frame 376)
frame_idx = min(376, T); 
bg_img = M(:,:,frame_idx);

% Simple contrast stretch for display
bg_img = imgaussfilt(bg_img, SIGMA);
clim_low = prctile(bg_img(:), 5);
clim_high = prctile(bg_img(:), SATURATION_PCT);

figure('Name', 'FlexMEA72 Alignment Check', 'Color', 'w', 'Position', [100 100 1000 800]);

% 1. Plot Image
imagesc(bg_img);
colormap('gray');
caxis([clim_low, clim_high]);
axis image off;
hold on;

% 2. Plot Recording Electrodes (The "Diamond/Arrow" shape)
% We plot them as clear circles with black edges
scatter(rec_x, rec_y, 100, 'o', ...
    'MarkerEdgeColor', 'k', ...
    'MarkerFaceColor', 'none', ...
    'LineWidth', 1.5, ...
    'DisplayName', 'Recording Channels');

% 3. Plot Center Crosshair (Helper to see alignment center)
plot(img_center_x + NUDGE_X_PX, img_center_y + NUDGE_Y_PX, 'r+', 'MarkerSize', 15, 'LineWidth', 2);

% Label a few corners to help orientation (Optional)
% Find specific corners in the transformed coordinates
idx_A1 = sub2ind(size(final_x), 1, 1); % Row 1, Col 1
idx_J8 = sub2ind(size(final_x), 9, 8); % Row 9, Col 8 (Excluded, but useful for bounds)
idx_A8 = sub2ind(size(final_x), 1, 8);

text(final_x(idx_A1), final_y(idx_A1), ' A1', 'Color', 'y', 'FontWeight', 'bold', 'FontSize', 12);
text(final_x(idx_A8), final_y(idx_A8), ' A8', 'Color', 'y', 'FontWeight', 'bold', 'FontSize', 12);

title(sprintf('FlexMEA72 Overlay\nScale: %.1f um/px | Rot: %.0f deg', ...
    MICRONS_PER_PIXEL, ROTATION_DEG), 'FontSize', 14);

legend({'Rec Electrodes', 'MEA Center'}, 'Location', 'northeast', 'TextColor', 'w', 'Color', 'k');
hold off;

fprintf('Done! If the grid is too big, increase "MICRONS_PER_PIXEL" at the top of the script.\n');