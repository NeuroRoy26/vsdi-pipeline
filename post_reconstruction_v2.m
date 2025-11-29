% post_reconstruction_v2.32.m
clc; close all;

%% =========================================================================
% --- SETTINGS ---
% =========================================================================

% 1. SMOOTHING (Creaminess)
% Range: 0.5 (Grainy) to 3.0 (Cloud-like)
SIGMA = 2.0; 

% 2. NOISE FLOOR (Background Cutoff)
% Range: 0.10 (Show everything) to 0.50 (Show only strong core)
% 0.25 means "Hide the bottom 25% of the signal"
FLOOR_SENSITIVITY = 0.40;

% 3. SATURATION (Heat Intensity)
% Range: 95 (Hot/Red) to 99.9 (Cool/Blue)
% 99.5 means "Only the top 0.5% of pixels get max red color"
SATURATION_PCT = 98.5;

% 4. COLORMAP (Visual Style)
% Options: 'jet', 'parula', 'hot', 'inferno'
CHOSEN_CMAP = 'jet'; 

if exist('mov_recon', 'var'), M = double(mov_recon);
elseif exist('reconstructed_movie', 'var'), M = double(reconstructed_movie);
elseif exist('mov', 'var'), M = double(mov);
elseif exist('ans', 'var') && ndims(ans) == 3, M = double(ans);
else, error('No data found.'); end

[H, W, T] = size(M);

%% =========================================================================
% 1. PROCESSING
% =========================================================================
fprintf('Processing with Sigma=%.1f, Floor=%.2f, Sat=%.1f...\n', ...
    SIGMA, FLOOR_SENSITIVITY, SATURATION_PCT);

% Baseline Subtraction (Frames 350-370)
baseline = mean(M(:,:,350:370), 3);
M_sub = M - baseline;

% Apply Smoothing
M_smooth = zeros(H, W, T);
for t = 1:T
    M_smooth(:,:,t) = imgaussfilt(M_sub(:,:,t), SIGMA);
end

%% =========================================================================
% 2. CALCULATE THRESHOLDS
% =========================================================================
% We analyze the active window (375-400) to find the dynamic range
active_data = M_smooth(:,:,375:400);

% Calculate the "Red Line" (Saturation)
sat_val = prctile(active_data(:), SATURATION_PCT);

% Calculate the "Black Line" (Noise Floor)
% We base this on the saturation value to keep it relative
floor_val = sat_val * FLOOR_SENSITIVITY;

fprintf('   -> Noise Cutoff: %.2e\n', floor_val);
fprintf('   -> Max Redness:  %.2e\n', sat_val);

%% =========================================================================
% 3. GENERATE MONTAGE
% =========================================================================
start_f = 370;
end_f = 401;
num_frames = end_f - start_f + 1;
rows = 4; cols = 8; 

figure('Name', 'Montage', 'Color', 'k', 'Position', [10 10 1600 900]);

% Prepare Colormap (Force background color to black)
try
    cmap = feval(CHOSEN_CMAP, 256);
catch
    cmap = jet(256); % Fallback
end
cmap(1,:) = [0 0 0]; % Black Background

for k = 1:num_frames
    frame_idx = start_f + k - 1;
    img = M_smooth(:,:,frame_idx);
    
    % Soft Masking: Force values below floor to minimum
    img_display = img;
    img_display(img < floor_val) = -inf;
    
    subplot(rows, cols, k);
    imagesc(img_display);
    axis image off;
    colormap(gca, cmap);
    
    % Apply the calculated limits
    caxis([floor_val, sat_val]);
    
    % Titles
    if frame_idx == 376
        title('STIMULUS', 'Color', 'r', 'FontWeight', 'bold');
        box on; ax=gca; ax.XColor='r'; ax.YColor='r'; ax.LineWidth=2;
    else
        latency = (frame_idx - 376) * 4;
        title(sprintf('%d ms', latency), 'Color', 'w');
    end
end

% Master Colorbar
h = colorbar;
h.Position = [0.92 0.1 0.02 0.8];
h.Color = 'w';
h.Label.String = sprintf('Neural Intensity (Robust Scale: %.0f%%)', FLOOR_SENSITIVITY*100);

sgtitle(sprintf('Neural Propagation: Sigma=%.1f | Floor=%.2f | Sat=%.1f%%', ...
    SIGMA, FLOOR_SENSITIVITY, SATURATION_PCT), 'Color', 'w');

%% =========================================================================
% 4. VERIFICATION PLOT
% =========================================================================
% Show the user exactly what the thresholds look like on a trace
% figure('Name', 'Threshold Check', 'Color', 'w');
% peak_map = mean(M_smooth(:,:,380:390),3);
% [~,idx] = max(peak_map(:));
% [py, px] = ind2sub([H,W], idx);
% trace = squeeze(M_smooth(py,px,350:450));
% 
% plot(350:450, trace, 'k', 'LineWidth', 1.5); hold on;
% yline(noise_floor, 'b--', 'Noise Floor (Black below)');
% yline(saturation_point, 'r--', 'Saturation (Red above)');
% xline(375, 'r-', 'Stim');
% title('Trace with Thresholds'); legend('Signal', 'Floor', 'Sat');
% grid on;

fprintf('=== DONE ===\n');