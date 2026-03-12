%% simple_blind_comparison_validation.m
% BLIND CHECK: Raw vs Corrected Structural Averages
% Includes quantitative validation of motion correction
% Auto-load if file exists, otherwise prompt manually.

clear; clc; close all;

%% ------------------------------------------------------------------------
% 0. PREDEFINED FILE PATHS (AUTO CHECK)
% -------------------------------------------------------------------------

raw_path  = "C:\Roy\MSc\Thesis\Scripts\data\figures\led_E0B0.h5";
corr_path = "C:\Roy\MSc\Thesis\Scripts\data\figures\led_E0B0_vsd_corrected.h5";

% ---- RAW FILE CHECK ----
if isfile(raw_path)
    fprintf('RAW file found automatically:\n%s\n', raw_path);
else
    fprintf('RAW file not found. Please select manually.\n');
    [raw_fn, raw_pn] = uigetfile('*.h5', 'Select RAW file');
    if raw_fn==0, return; end
    raw_path = fullfile(raw_pn, raw_fn);
end

% ---- CORRECTED FILE CHECK ----
if isfile(corr_path)
    fprintf('CORRECTED file found automatically:\n%s\n', corr_path);
else
    fprintf('CORRECTED file not found. Please select manually.\n');
    [corr_fn, corr_pn] = uigetfile('*.h5', 'Select CORRECTED file');
    if corr_fn==0, return; end
    corr_path = fullfile(corr_pn, corr_fn);
end

%% ------------------------------------------------------------------------
% 1. LOAD & IDENTIFY STRUCTURAL FRAMES (RAW)
% -------------------------------------------------------------------------

fprintf('\nLoading RAW data...\n');
info_r = h5info(raw_path);
raw_data = double(h5read(raw_path, ['/' info_r.Datasets(1).Name]));

T = size(raw_data, 3);
means = squeeze(mean(mean(raw_data,1),2));
stds  = squeeze(std(std(raw_data,0,1),0,2));
contrast = stds ./ max(means, eps);

struct_idxs = [];
for t = 1:2:T-1
    if contrast(t) > contrast(t+1)
        struct_idxs(end+1) = t;
    else
        struct_idxs(end+1) = t+1;
    end
end

raw_struct = raw_data(:,:,struct_idxs);
fprintf('Identified %d structural frames in RAW.\n', length(struct_idxs));

%% ------------------------------------------------------------------------
% 2. LOAD CORRECTED DATA
% -------------------------------------------------------------------------

fprintf('\nLoading CORRECTED data...\n');
try
    corr_struct = double(h5read(corr_path, '/structural'));
    fprintf('Loaded /structural dataset directly.\n');
catch
    info_c = h5info(corr_path);
    corr_struct = double(h5read(corr_path, ['/' info_c.Datasets(1).Name]));
    fprintf('Loaded dataset: %s\n', info_c.Datasets(1).Name);
end

%% FRAME-TO-FRAME CORRELATION CHECK

n_test = min(200, size(raw_struct,3)-1); % limit for speed
corr_raw_vals  = zeros(n_test,1);
corr_corr_vals = zeros(n_test,1);

for k = 1:n_test
    r1 = raw_struct(:,:,k);
    r2 = raw_struct(:,:,k+1);
    c1 = corr_struct(:,:,k);
    c2 = corr_struct(:,:,k+1);

    corr_raw_vals(k)  = corr(r1(:), r2(:));
    corr_corr_vals(k) = corr(c1(:), c2(:));
end

mean_corr_raw  = mean(corr_raw_vals);
mean_corr_corr = mean(corr_corr_vals);

fprintf('\nFrame-to-Frame Correlation:\n');
fprintf('RAW:       %.5f\n', mean_corr_raw);
fprintf('CORRECTED: %.5f\n', mean_corr_corr);
fprintf('Increase:  %.3f %%\n', ...
    100*(mean_corr_corr - mean_corr_raw)/mean_corr_raw);
%% ------------------------------------------------------------------------
% 3. COMPUTE AVERAGES
% -------------------------------------------------------------------------

fprintf('\nCalculating averages...\n');
avg_raw  = mean(raw_struct, 3);
avg_corr = mean(corr_struct, 3);

%% ------------------------------------------------------------------------
% 4. OPTIONAL MILD SHARPENING (FOR VISUALIZATION ONLY)
% -------------------------------------------------------------------------

apply_sharpening = true;  % <-- set false to disable

if apply_sharpening
    sigma  = 1.0;
    amount = 0.6;

    blurred = imgaussfilt(avg_corr, sigma);
    avg_corr_display = avg_corr + amount * (avg_corr - blurred);
    avg_corr_display(avg_corr_display < 0) = 0;
else
    avg_corr_display = avg_corr;
end

%% ------------------------------------------------------------------------
% 5. QUANTITATIVE VALIDATION
% -------------------------------------------------------------------------

% ---- Sharpness Metric (Variance of Laplacian) ----
lap_raw  = del2(avg_raw);
lap_corr = del2(avg_corr);

sharp_raw  = var(lap_raw(:));
sharp_corr = var(lap_corr(:));

% ---- Temporal Stability ----
raw_std_map  = std(raw_struct, 0, 3);
corr_std_map = std(corr_struct, 0, 3);

mean_raw_std  = mean(raw_std_map(:));
mean_corr_std = mean(corr_std_map(:));

fprintf('\n=== MOTION CORRECTION VALIDATION ===\n');
fprintf('Sharpness (Variance of Laplacian)\n');
fprintf('RAW:        %.4f\n', sharp_raw);
fprintf('CORRECTED:  %.4f\n', sharp_corr);
fprintf('Improvement: %.2f %%\n', ...
    100*(sharp_corr - sharp_raw)/sharp_raw);

fprintf('\nTemporal Pixel STD\n');
fprintf('RAW:        %.4f\n', mean_raw_std);
fprintf('CORRECTED:  %.4f\n', mean_corr_std);
fprintf('Reduction:  %.2f %%\n', ...
    100*(mean_raw_std - mean_corr_std)/mean_raw_std);

%% ------------------------------------------------------------------------
% 6. DISPLAY (3 PANEL)
% -------------------------------------------------------------------------

vals = avg_corr(:);
vals = vals(vals > mean(vals)*0.1);
clims = [prctile(vals,1), prctile(vals,99)];

figure('Color','w', 'Position', [50, 50, 1500, 600]);

subplot(1,2,1);
imagesc(avg_raw, clims);
colormap(gray); axis image off;
title('Avg. RAW Frames', 'FontSize', 14);

% figure('Color','w', 'Position', [50, 50, 1500, 600]);
subplot(1,2,2);
imagesc(avg_corr_display, clims);
colormap(gray); axis image off;
title('Avg. Motion Compensated Frames', 'FontSize', 14);

% subplot(1,3,3);
% imagesc(avg_corr - avg_raw);
% axis image off;
% colormap(gca, 'jet');
% colorbar;
% title('Difference (Corrected - Raw)', 'FontSize', 14);

linkaxes(findall(gcf,'type','axes'));

fprintf('\nVisualization complete.\n');

%% ---------------- 7. FIGURE 3: MOTION STATS ----------------
% Plot global shift magnitude over time
[w_fn, w_pn] = uigetfile('*.hdf;*.h5', 'Select FLOW (w.h5)');
if w_fn==0, return; end
w_file = fullfile(w_pn, w_fn);

u = h5read(w_file, '/u');
v = h5read(w_file, '/v');
[H, W, T] = size(u);
mid_t = round(T/2);

fprintf('Calculating Motion Statistics...\n');
shifts = zeros(T, 1);
for t = 1:T
    % Mean magnitude of displacement vectors per frame
    mag = sqrt(u(:,:,t).^2 + v(:,:,t).^2);
    shifts(t) = mean(mag(:));
end

time_axis = (0:T-1) / 30; % Assume 30 Hz

fig3 = figure('Color','w', 'Position', [200, 200, 600, 300]);
plot(time_axis, shifts, 'Color', [0.2 0.2 0.2], 'LineWidth', 1); % Raw data
hold on;
% Add a smoothed trend line
plot(time_axis, smoothdata(shifts, 'gaussian', 20), 'Color', [0.85 0.32 0.1], 'LineWidth', 2.5);

grid on; box off;
ylabel('Avg. Displacement (pixels)', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('Time (s)', 'FontSize', 12, 'FontWeight', 'bold');
title('Global Motion Magnitude', 'FontSize', 14);
legend({'Raw Motion', 'Smoothed Trend'}, 'Location', 'northwest');
xlim([0 max(time_axis)]);

%% ------------------------------------------------------------------------
% 7. HIGH-QUALITY TIFF EXPORT (COMMENT OUT IF NOT NEEDED)
% ------------------------------------------------------------------------
% 
% Exports 16-bit TIFF files (full dynamic range)

% export_folder = "C:\Roy\MSc\Thesis\Scripts\data\figures";
% 
% if ~isfolder(export_folder)
%     mkdir(export_folder);
% end
% 
% raw_uint16  = uint16(mat2gray(avg_raw)  * 65535);
% corr_uint16 = uint16(mat2gray(avg_corr_display) * 65535);
% 
% imwrite(raw_uint16,  fullfile(export_folder, ...
%     "RAW_structural_average.tif"),  'tif', 'Compression', 'none');
% 
% imwrite(corr_uint16, fullfile(export_folder, ...
%     "CORRECTED_structural_average.tif"), 'tif', 'Compression', 'none');
% 
% exportgraphics(fig3, 'Fig3_Stats_Fixed.png', 'Resolution', 300, 'BackgroundColor', 'none');
% 
% fprintf('16-bit TIFFs exported to:\n%s\n', export_folder);
