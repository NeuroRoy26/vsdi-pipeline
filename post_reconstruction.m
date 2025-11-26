% post_reconstruction.m
% clc; close all;

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
fprintf('3. Applying Spatial High-Pass Filter...\n');
sigma_pixels = 20; 
filtered_movie = zeros(H, W, T);

% 3a. Spatial Background Subtraction
for t = 1:T
    frame = reconstructed_movie(:,:,t);
    background = imgaussfilt(frame, sigma_pixels);
    filtered_movie(:,:,t) = frame - background;
end

%% 3b. ADVANCED MODEL-BASED DETRENDING
% Diagnostic tool for finding the right bleaching curve

% fprintf('\n--- 3b. RUNNING MODEL COMPARISON FOR BLEACHING ---\n');
% 
% % 1. Extract Global Signal
% % We average the whole movie to find the "Shape" of the bleaching
% global_trace = squeeze(mean(mean(filtered_movie, 1), 2));
% t_vec = (1:T)';
% 
% % 2. Define "Resting" Frames (The Training Data)
% % CRITICAL: We must hide the brain activity from the math, or the math 
% % will think the brain signal is noise and remove it.
% % Based on your plots: Stimulus is at ~380. 
% % We use frames 1-370 (Pre-stim) and 700-750 (Recovery/End) to anchor the curve.
% fit_mask = [1:370, 700:750]; 
% 
% y_train = global_trace(fit_mask);
% x_train = t_vec(fit_mask);
% 
% fprintf('Training on %d frames (ignoring stimulus period).\n', length(fit_mask));
% 
% % 3. Define Models to Test
% 
% % Model A: Linear (Slope)
% % Equation: y = p1*x + p2
% [fit_lin, gof_lin] = fit(x_train, y_train, 'poly1');
% 
% % Model B: Quadratic (Parabola)
% % Equation: y = p1*x^2 + p2*x + p3
% [fit_quad, gof_quad] = fit(x_train, y_train, 'poly2');
% 
% % Model C: Exponential (Decay) - The Physics Model
% % Equation: y = a*exp(b*x) + c
% % We set start points to help the solver
% fit_exp_type = fittype('a*exp(b*x) + c');
% opts = fitoptions(fit_exp_type);
% opts.StartPoint = [range(y_train), -0.01, mean(y_train)]; 
% [fit_exp, gof_exp] = fit(x_train, y_train, fit_exp_type, opts);
% 
% % 4. Print Metrics Report
% fprintf('\nModel Competition Results:\n');
% fprintf('------------------------------------------------------------\n');
% fprintf('| Model Type    | RMSE (Error) | R-Square (Fit) | Interpretation \n');
% fprintf('------------------------------------------------------------\n');
% fprintf('| 1. Linear     | %.6f     | %.4f         | %s\n', ...
%     gof_lin.rmse, gof_lin.rsquare, 'Simple slope removal');
% fprintf('| 2. Quadratic  | %.6f     | %.4f         | %s\n', ...
%     gof_quad.rmse, gof_quad.rsquare, 'catches simple curvature');
% fprintf('| 3. Exponential| %.6f     | %.4f         | %s\n', ...
%     gof_exp.rmse, gof_exp.rsquare, 'Physically accurate for Dye');
% fprintf('------------------------------------------------------------\n');
% 
% % 5. Auto-Select Best Model (Based on lowest RMSE)
% rmse_values = [gof_lin.rmse, gof_quad.rmse, gof_exp.rmse];
% [~, best_idx] = min(rmse_values);
% 
% switch best_idx
%     case 1
%         final_model = fit_lin;
%         fprintf('>>> WINNER: LINEAR Model selected.\n');
%     case 2
%         final_model = fit_quad;
%         fprintf('>>> WINNER: QUADRATIC Model selected.\n');
%     case 3
%         final_model = fit_exp;
%         fprintf('>>> WINNER: EXPONENTIAL Model selected.\n');
% end
% 
% % 6. Generate the Bleaching Curve for all time points
% bleaching_curve = feval(final_model, t_vec);
% 
% % 7. Visualize the Fit (Sanity Check)
% figure('Name', 'Bleaching Model Fit', 'Color', 'w');
% plot(t_vec, global_trace, 'k', 'LineWidth', 1.2); hold on;
% plot(t_vec, bleaching_curve, 'r-', 'LineWidth', 2);
% xline(370, 'b--', 'Stimulus Start');
% legend('Global Data', 'Modeled Bleaching', 'Mask Boundary');
% title(['Selected Model Fit (R^2 = ' num2str(max([gof_lin.rsquare, gof_quad.rsquare, gof_exp.rsquare])) ')']);
% grid on;
% 
% % 8. Subtract the Curve from the Data
% fprintf('Subtracting modeled bleaching from all pixels...\n');
% movie_2d = reshape(filtered_movie, H*W, T);
% detrended_2d = movie_2d - bleaching_curve'; 
% detrended_movie = reshape(detrended_2d, H, W, T);
% 
% fprintf('--- DETRENDING COMPLETE ---\n\n');


%% 3b. PIXEL-WISE DETRENDING (The "Nuclear Option")
fprintf('\n--- 3b. RUNNING PIXEL-WISE DETRENDING ---\n');
fprintf('This fits a unique curve to EVERY pixel. Please wait...\n');

% 1. Setup
[H, W, T] = size(filtered_movie);
movie_2d = reshape(filtered_movie, H*W, T); % Reshape to (Pixels x Time)
detrended_2d = zeros(size(movie_2d));

t_vec = (1:T)';
% Mask: We use Pre-stim (1-370) and End (700-750) to fit the noise
fit_mask = [1:370, 700:750]; 
x_train = t_vec(fit_mask);

% 2. The Loop (Vectorized for speed where possible)
% We iterate through pixels in chunks to keep it fast/manageable
num_pixels = H * W;
chunk_size = 10000; % Process 10k pixels at a time

fprintf('Progress: ');
for i = 1:chunk_size:num_pixels
    % Define chunk range
    idx_end = min(i + chunk_size - 1, num_pixels);
    chunk_indices = i:idx_end;
    
    % Extract data for this chunk
    % chunk_data is (N_pixels x Time)
    chunk_data = movie_2d(chunk_indices, :);
    
    % Extract only the "Resting" frames for training
    y_train_chunk = chunk_data(:, fit_mask);
    
    % --- MATHEMATICAL TRICK FOR SPEED ---
    % Instead of running a loop 278,000 times, we use Matrix Algebra.
    % We fit a parabola (y = ax^2 + bx + c) to all pixels in the chunk at once.
    % Solves: Y = X * Beta
    
    % Design Matrix (Time^2, Time, Constant) for the TRAINING frames
    X_train = [x_train.^2, x_train, ones(length(x_train), 1)];
    
    % Design Matrix for ALL frames (to generate the full curve)
    X_full = [t_vec.^2, t_vec, ones(T, 1)];
    
    % Calculate Betas (Coefficients) for this chunk
    % Beta = (X'X)^-1 X' Y'
    % We use the slash operator for stability: Beta = X \ Y'
    betas = X_train \ y_train_chunk'; 
    
    % Generate the drift curves for all time points
    % Curves = X_full * Betas
    drift_curves = (X_full * betas)';
    
    % Subtract drift from the original data
    detrended_2d(chunk_indices, :) = chunk_data - drift_curves;
    
    % Print a dot every 10%
    if mod(i, round(num_pixels/10)) < chunk_size
        fprintf('.');
    end
end
fprintf(' Done!\n');

% 3. Reshape back to Movie
detrended_movie = reshape(detrended_2d, H, W, T);
fprintf('--- PIXEL-WISE DETRENDING COMPLETE ---\n\n');

%% 4. ROBUST Z-SCORE NORMALIZATION
fprintf('4. Applying Robust Z-Score...\n');
baseline_frames = 100:300; 

% Recalculate baseline stats on the DETRENDED data
baseline_mean = mean(detrended_movie(:,:,baseline_frames), 3);
baseline_std = std(detrended_movie(:,:,baseline_frames), 0, 3);

median_noise = median(baseline_std(:));
baseline_std(baseline_std < (0.1 * median_noise)) = median_noise; 

zscore_movie = zeros(H, W, T);
for t = 1:T
    % Subtract baseline_mean (which should be near 0 now) and divide by std
    zscore_movie(:,:,t) = (detrended_movie(:,:,t) - baseline_mean) ./ baseline_std;
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