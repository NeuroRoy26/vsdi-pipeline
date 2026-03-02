% VSD_Filmstrip_Montage_Batch.m
% Modified: Publication Quality (Interpolated, Smoothed, Clean UI)
% run this after nmf_decomp.m script on the individual components

% need to combine this with the trigger detection logic from
% analysis_Step1_contanate.m script which has smart trigger detection, my
% guess is adapting that automatically calculated trigger in this, would
% give a better idea on the start and stop of the stimulus and activity

clear; clc; close all;

%% 1. Configuration Settings
window_pre_ms = 20;    
window_post_ms = 100;  
frame_step = 1;        

% --- VISUAL SETTINGS ---
alpha_threshold = 0.55; 

% --- NEW: PUBLICATION SMOOTHING SETTINGS ---
spatial_smoothing = 3.5;  % Gentle Gaussian blur to merge noisy pixels (Adjust 0.5 to 2.0)
upsample_factor = 1;      % Interpolates pixels for a fluid, continuous look

bg_path = 'C:\Roy\MSc\Thesis\Scripts\frame_1.png'; 

%% 2. Load Custom Background
if exist(bg_path, 'file')
    custom_bg = imread(bg_path);
    if size(custom_bg, 3) == 1
        bg_rgb_base = repmat(mat2gray(custom_bg), [1, 1, 3]);
    else
        bg_rgb_base = im2double(custom_bg);
    end
else
    error('Background image not found at: %s', bg_path);
end

%% 3. Select Files
fprintf('=== VSD Filmstrip Generator (Publication Quality) ===\n');
[files, path_name] = uigetfile('*.mat', 'Select Reconstructed NMF .mat files', 'MultiSelect', 'on');
if isequal(files, 0), return; end
if ischar(files), files = {files}; end

%% 4. Batch Processing Loop
for k = 1:length(files)
    fName = files{k};
    D = load(fullfile(path_name, fName));
    if ~isfield(D, 'reconstructed_movie'), continue; end
    
    mov = D.reconstructed_movie;
    Fs = D.Fs;
    [orig_h, orig_w, num_frames] = size(mov);
    
    bg_rgb = imresize(bg_rgb_base, [orig_h, orig_w]);

    global_trace = squeeze(mean(mean(mov, 1), 2));
    [~, global_peak_idx] = max(global_trace);
    
    frames_pre = round((window_pre_ms / 1000) * Fs);
    frames_post = round((window_post_ms / 1000) * Fs);
    plot_frames = max(1, global_peak_idx - frames_pre) : frame_step : min(num_frames, global_peak_idx + frames_post);
    
    num_subplots = length(plot_frames);
    fprintf('Processing %s: Plotting %d sequential frames.\n', fName, num_subplots);

    %% 5. Generate Figure with Tiled Layout
    cols = ceil(sqrt(num_subplots * 1.2)); 
    rows = ceil(num_subplots / cols);
    
    figure('Name', fName, 'Color', 'w', 'Position', [50, 50, 1600, 900]);
    t = tiledlayout(rows, cols, 'TileSpacing', 'none', 'Padding', 'compact');
    cmap = turbo(256);
    
    window_data = mov(:, :, plot_frames);
    min_val = min(window_data(:));
    max_val = max(window_data(:));

    for i = 1:num_subplots
        curr_idx = plot_frames(i);
        curr_frame = mov(:, :, curr_idx);
        
        % 1. Denoisng: Smooth the raw frame
        smooth_frame = imgaussfilt(curr_frame, spatial_smoothing);
        
        % 2. Normalize
        norm_img = (smooth_frame - min_val) / (max_val - min_val);
        
        % 3. Interpolation: Upsample the image to remove blocky pixels
        % We use bicubic interpolation for the smoothest gradients
        smooth_norm_img = imresize(norm_img, upsample_factor, 'bicubic');
        
        % Clamping values to ensure interpolation didn't overshoot
        smooth_norm_img(smooth_norm_img < 0) = 0;
        smooth_norm_img(smooth_norm_img > 1) = 1;
        
        % 4. Create Transparency Mask (Soft Edges)
        alpha_mask = double(smooth_norm_img >= alpha_threshold) * 0.85; % Max opacity 85%
        alpha_mask = imgaussfilt(alpha_mask, 2.0); % Softens the hard edge of the mask
        
        nexttile;
        imshow(bg_rgb); 
        hold on;
        
        % Plot the upsampled signal, mapped to the original coordinates
        h = imagesc('XData', [1 orig_w], 'YData', [1 orig_h], 'CData', smooth_norm_img);
        colormap(gca, cmap);
        caxis([alpha_threshold, 1]); 
        set(h, 'AlphaData', alpha_mask);
        
        axis image off;
        
        % 5. Cleaned up text (Removed background box, added shadow effect for readability)
        time_ms = ((curr_idx - (global_peak_idx - frames_pre)) / Fs) * 1000;
        text_str = sprintf('%.1f ms', time_ms);
        
        % Draw black text slightly offset as a "drop shadow" for readability
        text(4, orig_h-4, text_str, 'Color', 'k', 'FontSize', 8, 'FontWeight', 'bold');
        % Draw white text on top
        text(3, orig_h-5, text_str, 'Color', 'w', 'FontSize', 8, 'FontWeight', 'bold');
    end
    
    cb = colorbar;
    cb.Layout.Tile = 'east'; 
    ylabel(cb, '\DeltaF/F_0 (Norm)', 'FontSize', 12, 'FontWeight', 'bold');
end