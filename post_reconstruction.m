% post_reconstruction.m
clc; close all;

% =========================================================================
% 0. BRIDGE: MAP VARIABLES FROM PREVIOUS STEPS
% =========================================================================
% We try to find the variables from your previous workspace automatically.
if exist('mov_recon', 'var')
    reconstructed_movie = mov_recon;
elseif ~exist('reconstructed_movie', 'var')
    error('Cannot find "mov_recon" or "reconstructed_movie". Run the reconstruction step first.');
end

if exist('mov', 'var')
    original_raw_movie = double(mov); % Ensure double precision
elseif ~exist('original_raw_movie', 'var')
    error('Cannot find "mov" or "original_raw_movie". Load your data first.');
end

[H, W, T] = size(reconstructed_movie);
fprintf('=== POST-PROCESSING START ===\n');
fprintf('Data Dimensions: %d x %d pixels, %d frames\n', H, W, T);

%% 1. POLARITY CHECK (The "Sign Flip")
% ICA is sign-blind. We check if the reconstruction correlates positively 
% with the raw data.
fprintf('1. Checking Polarity...\n');

% Calculate global time courses
global_raw = squeeze(mean(mean(original_raw_movie, 1), 2));
global_recon = squeeze(mean(mean(reconstructed_movie, 1), 2));

% Calculate correlation
r = corr(global_raw, global_recon);

if r < 0
    fprintf('   -> Polarity Inversion Detected (Corr = %.2f). FLIPPING signal.\n', r);
    reconstructed_movie = reconstructed_movie * -1;
    global_recon = global_recon * -1;
else
    fprintf('   -> Polarity correct (Corr = %.2f). No flip needed.\n', r);
end

%% 2. RESIDUAL CHECK (The "Bleed" Check)
% Did we leave any biology behind in the noise?
fprintf('2. Calculating Residuals...\n');

% Scale recon to match raw magnitude for fair subtraction
scale_factor = std(global_raw) / std(global_recon); 
residual_movie = original_raw_movie - (reconstructed_movie * scale_factor);

%% 3. SPATIAL FILTERING (High-Pass)
% Removes uneven background illumination ("The Fog")
fprintf('3. Applying Spatial High-Pass Filter...\n');
sigma_pixels = 20; % Size of the background "fog" to remove
filtered_movie = zeros(H, W, T);

% Using a loop (imgaussfilt is fast)
for t = 1:T
    frame = reconstructed_movie(:,:,t);
    % 1. Estimate background (low freq)
    background = imgaussfilt(frame, sigma_pixels);
    % 2. Subtract background
    filtered_movie(:,:,t) = frame - background;
end

%% 4. ROBUST Z-SCORE NORMALIZATION
% Since you have a jump at 1.5s (Frame 376), we must decide where baseline is.
fprintf('4. Applying Robust Z-Score...\n');

baseline_frames = 100:300; 

fprintf('   Using baseline frames: %d to %d\n', min(baseline_frames), max(baseline_frames));

% Calculate baseline statistics per pixel
baseline_mean = mean(filtered_movie(:,:,baseline_frames), 3);
baseline_std = std(filtered_movie(:,:,baseline_frames), 0, 3);

% Avoid divide-by-zero artifacts (Dead pixels having 0 std)
median_noise = median(baseline_std(:));
% If a pixel has 0 noise, replace it with the median noise to prevent NaN
baseline_std(baseline_std < (0.1 * median_noise)) = median_noise; 

zscore_movie = zeros(H, W, T);
for t = 1:T
    % Z = (Signal - BaselineMean) / BaselineStd
    zscore_movie(:,:,t) = (filtered_movie(:,:,t) - baseline_mean) ./ baseline_std;
end
fprintf('   Normalization complete.\n');

%% 5. VISUALIZATION & CHECKS
fprintf('5. Generating Report...\n');
figure('Name', 'VSD Post-Process Report', 'Color', 'w', 'Position', [50 50 1400 800]);

% Find frame with max activity to plot maps
global_z = squeeze(mean(mean(zscore_movie,1),2));
% Ignore the first/last 10 frames to avoid edge artifacts finding the peak
search_range = 10:(T-10); 
[~, local_idx] = max(abs(global_z(search_range)));
t_peak = search_range(local_idx);

% A. Polarity Check Plot
subplot(2,4,1);
plot(global_raw, 'k', 'LineWidth', 1); hold on;
% Scale recon for visual overlap
plot(global_recon * (range(global_raw)/range(global_recon)) + mean(global_raw), 'r', 'LineWidth', 1); 
title('1. Global Signals');
legend('Raw', 'Recon');
grid on; axis tight;

% B. Residual Map
subplot(2,4,2);
res_frame = residual_movie(:,:,t_peak);
clim_res = [prctile(res_frame(:), 1) prctile(res_frame(:), 99)];
imagesc(res_frame, clim_res);
title('2. Residuals (Raw - Recon)');
axis image off; colormap(gca, 'gray'); 

% C. Spatial Filter Effect
subplot(2,4,3);
imagesc(reconstructed_movie(:,:,t_peak));
title('3. Raw Reconstruction');
axis image off; colormap(gca, 'jet');

subplot(2,4,4);
imagesc(filtered_movie(:,:,t_peak));
title('4. Spatially Filtered');
axis image off; colormap(gca, 'jet');

% D. Final Z-Score Map
subplot(2,2,3); % Large plot
z_frame = zscore_movie(:,:,t_peak);
% Clip display at -2 and +10 SD (Biology is usually bright)
imagesc(z_frame, [-2 10]); 
title(sprintf('5. Z-Score Map (Frame %d)', t_peak));
subtitle('Units: Std Devs above Baseline');
axis image off; colormap(gca, 'jet'); colorbar;

% E. Pixel Trace (AUTO ROI)
subplot(2,2,4);
% Find the brightest pixel in the Z-score map
[roi_h, roi_w] = find(z_frame == max(z_frame(:)), 1);
trace_final = squeeze(zscore_movie(roi_h, roi_w, :));

plot(trace_final, 'b', 'LineWidth', 1.5);
yline(3, 'r--', '3\sigma Significance'); % Significance threshold
title(sprintf('Trace at Peak Pixel (%d, %d)', roi_h, roi_w));
ylabel('Z-Score'); xlabel('Time (frames)');
grid on; axis tight;

fprintf('=== PROCESSING COMPLETE ===\n');