% post_reconstruction_v3.6.m
clc; close all;
fprintf('=== POST-RECONSTRUCTION PROCESSING (v3.6 - Red Heatmap Return) ===\n\n');

%% =========================================================================
% --- DATA LOADING ---
% =========================================================================
data_found = false;
if exist('reconstructed_movie', 'var')
    M = double(reconstructed_movie); data_found = true;
elseif exist('mov_recon', 'var')
    M = double(mov_recon); data_found = true;
elseif exist('mov', 'var')
    M = double(mov); data_found = true;
end

if data_found
    if exist('Fs', 'var'), sampling_rate = Fs; else, sampling_rate = 250; end
end

if ~data_found
    if ~exist('data', 'dir'), error('Data directory not found!'); end
    files = dir('data/reconstructed_ICs_*.mat');
    if isempty(files), error('No reconstruction files found!'); end
    
    fprintf('Available reconstruction files:\n');
    for i = 1:length(files), fprintf('  %d. %s\n', i, files(i).name); end
    
    if length(files) == 1, file_idx = 1; else, file_idx = input('\nSelect file number: '); end
    
    loaded_data = load(fullfile('data', files(file_idx).name));
    M = double(loaded_data.reconstructed_movie);
    if isfield(loaded_data, 'Fs'), sampling_rate = loaded_data.Fs; else, sampling_rate = 250; end
end

[H, W, T] = size(M);
fprintf('Data: %d x %d pixels, %d frames (%.1f Hz)\n', H, W, T, sampling_rate);

%% =========================================================================
% --- STRUCTURAL BACKGROUND PREP ---
% =========================================================================
input_file = 'data/averaged_movie_E0B0-B3_unbinned.h5';
dataset_name = '/structural';
structural_rgb = [];

if exist(input_file, 'file')
    try
        fprintf('Loading structural movie...\n');
        mov_struct = h5read(input_file, dataset_name);
        bg = mean(mov_struct, 3);
        bg = double(bg);
        bg_norm = (bg - min(bg(:))) / (max(bg(:)) - min(bg(:)));
        structural_rgb = cat(3, bg_norm, bg_norm, bg_norm);
        fprintf('✓ Structural background converted to RGB.\n');
    catch
        fprintf('! Warning: Structural load failed. Using black background.\n');
    end
else
    fprintf('! Warning: Structural file not found. Using black background.\n');
end

%% =========================================================================
% --- SETTINGS & PROCESSING ---
% =========================================================================
SIGMA = 2.0; 
FLOOR_SENSITIVITY = 0.40;
SATURATION_PCT = 98.5;

% CHANGE: Back to 'jet' for that classic Red/Blue look
CHOSEN_CMAP = 'jet'; 

fprintf('\nProcessing (Sigma=%.1f, Floor=%.2f, Sat=%.1f, Cmap=%s)...\n', ...
    SIGMA, FLOOR_SENSITIVITY, SATURATION_PCT, CHOSEN_CMAP);

baseline = mean(M(:,:,350:370), 3);
M_sub = M - baseline;
M_smooth = zeros(H, W, T);
for t = 1:T
    M_smooth(:,:,t) = imgaussfilt(M_sub(:,:,t), SIGMA);
end

active_data = M_smooth(:,:,375:400);
sat_val = prctile(active_data(:), SATURATION_PCT);
floor_val = sat_val * FLOOR_SENSITIVITY;

%% =========================================================================
% 3. GENERATE MONTAGE
% =========================================================================
start_f = 376 - 8; 
end_f = 376 + 23; 
num_frames = end_f - start_f + 1;
rows = 4; cols = 8; 

figure('Name', 'Montage', 'Color', 'w', 'Position', [10 10 1600 900]);

try, cmap = feval(CHOSEN_CMAP, 256); catch, cmap = jet(256); end

for k = 1:num_frames
    frame_idx = start_f + k - 1;
    img = M_smooth(:,:,frame_idx);
    
    img_display = img;
    img_display(img < floor_val) = floor_val;
    
    subplot(rows, cols, k);
    
    if ~isempty(structural_rgb)
        image(structural_rgb); 
        hold on;
        h_ov = imagesc(img_display);
        
        % Transparency Calculation
        alpha_data = (img_display - floor_val) / (sat_val - floor_val);
        alpha_data(alpha_data < 0) = 0;
        alpha_data(alpha_data > 1) = 1;
        alpha_data = alpha_data.^1.5; % Soften edges
        
        set(h_ov, 'AlphaData', alpha_data);
        colormap(gca, cmap);
        caxis([floor_val, sat_val]);
        hold off;
    else
        imagesc(img_display);
        colormap(gca, cmap);
        caxis([floor_val, sat_val]);
    end
    
    axis image off;
    
    if frame_idx == 376
        title('STIMULUS', 'Color', 'r', 'FontWeight', 'bold');
    else
        latency = (frame_idx - 376) * (1000/sampling_rate);
        title(sprintf('%.0f ms', latency), 'Color', 'k');
    end
end

h = colorbar; h.Position = [0.92 0.1 0.02 0.8]; h.Color = 'k'; 
sgtitle(sprintf('Neural Propagation (Sigma=%.1f, Floor=%.2f)', SIGMA, FLOOR_SENSITIVITY), 'Color', 'k');

%% =========================================================================
% 4. FULL MOVIE SLIDER
% =========================================================================
fprintf('\nGenerating slider figure...\n');
f_slider = figure('Name', 'Full Movie Slider', 'Color', 'w', 'Position', [100 100 800 600]);

h_ax = axes('Parent', f_slider, 'Position', [0.05 0.15 0.8 0.75], 'Color', 'w');

idx = 376;
img = M_smooth(:,:,idx);
img_display = img; 
img_display(img < floor_val) = floor_val;

if ~isempty(structural_rgb)
    image(structural_rgb, 'Parent', h_ax);
    hold(h_ax, 'on');
    h_img = imagesc(img_display, 'Parent', h_ax);
    
    alpha_data = (img_display - floor_val) / (sat_val - floor_val);
    alpha_data(alpha_data < 0) = 0;
    alpha_data(alpha_data > 1) = 1;
    alpha_data = alpha_data.^1.5; 
    
    set(h_img, 'AlphaData', alpha_data);
    colormap(h_ax, cmap);
    caxis(h_ax, [floor_val, sat_val]);
    hold(h_ax, 'off');
else
    h_img = imagesc(img_display, 'Parent', h_ax);
    colormap(h_ax, cmap);
    caxis(h_ax, [floor_val, sat_val]);
end

axis(h_ax, 'image', 'off');
latency = (idx - 376) * (1000/sampling_rate);
h_title = title(h_ax, sprintf('Frame %d (%.0f ms)', idx, latency), 'Color', 'k', 'FontSize', 14);

h_cb = colorbar(h_ax);
h_cb.Position = [0.88 0.15 0.02 0.75];
h_cb.Color = 'k';

h_slider = uicontrol('Parent', f_slider, 'Style', 'slider', ...
    'Units', 'normalized', ...
    'Position', [0.05 0.05 0.8 0.05], ...
    'Min', 1, 'Max', T, 'Value', idx, ...
    'SliderStep', [1/(T-1), 10/(T-1)], ...
    'BackgroundColor', [0.9 0.9 0.9]); 

h_text = uicontrol('Parent', f_slider, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.86 0.05 0.1 0.05], ...
    'String', sprintf('%d / %d', idx, T), ...
    'BackgroundColor', 'w', 'ForegroundColor', 'k', 'FontSize', 12);

set(h_slider, 'Callback', @(s,e) update_frame(s, h_img, h_title, h_text, M_smooth, floor_val, sat_val, sampling_rate, structural_rgb));

fprintf('\n=== COMPLETE ===\n');

function update_frame(slider, h_img, h_title, h_text, data, floor_val, sat_val, fs, struc_rgb)
    idx = round(slider.Value);
    img = data(:,:,idx);
    img_disp = img;
    img_disp(img < floor_val) = floor_val;
    
    set(h_img, 'CData', img_disp);
    
    if ~isempty(struc_rgb)
        a_data = (img_disp - floor_val) / (sat_val - floor_val);
        a_data(a_data < 0) = 0;
        a_data(a_data > 1) = 1;
        a_data = a_data.^1.5;
        set(h_img, 'AlphaData', a_data);
    end
    
    lat = (idx - 376) * (1000/fs);
    set(h_title, 'String', sprintf('Frame %d (%.0f ms)', idx, lat));
    set(h_text, 'String', sprintf('%d / %d', idx, size(data,3)));
end

%% ===== DEBUG: PRINT RAW VALUES ACROSS FRAMES =====

test_frames = 370:385;   % spans your stimulus window
num_test = length(test_frames);

% Pick a few meaningful pixels manually
pix_list = [
    round(H/2), round(W/2);        % center
    round(H/2)+10, round(W/2);     % below center
    round(H/2), round(W/2)+10      % right of center
];

fprintf('\n=== RAW VALUE DEBUG (M_smooth) ===\n');
fprintf('Sampling Rate: %.1f Hz  |  Frame step: %.2f ms\n\n', ...
        sampling_rate, 1000/sampling_rate);

for p = 1:size(pix_list,1)
    r = pix_list(p,1);
    c = pix_list(p,2);
    
    fprintf('Pixel (%d, %d):\n', r, c);
    fprintf('Frame\tTime(ms)\tValue\n');
    
    base_f = 376;
    
    for k = 1:num_test
        f = test_frames(k);
        t_ms = (f - base_f) * (1000/sampling_rate);
        val = M_smooth(r, c, f);
        fprintf('%d\t%+.1f\t\t%.6f\n', f, t_ms, val);
    end
    
    fprintf('\n');
end

%% ===== DEBUG: PRINT A SMALL PATCH ACROSS FRAMES =====

r0 = round(H/2);
c0 = round(W/2);
patch_radius = 2;

test_frames = 374:380;

for f = test_frames
    fprintf('\nFrame %d (%.1f ms):\n', ...
        f, (f-376)*(1000/sampling_rate));
    
    patch = M_smooth(r0-patch_radius:r0+patch_radius, ...
                     c0-patch_radius:c0+patch_radius, f);
    
    disp(patch);
end
