%% REVERSE ENGINEERED PIPELINE: 0503 MEA DATA
% Check SEP_Project_ReadMe.md for documentations of this standalone script.
close all; clear; clc;

%% 1. CONFIGURATION
filePath = 'data//ID0503//0503_MEA72_01_ref_ground_512Hz.mat';
FS = 512;               
cutSecs = 0.5;          
trigDelaySecs = 0.01;   
notchFlag = 1; 
bpFlag = 1;
bpRange = [4 150];
trialNum = 1;

% EPOCH SETTINGS
erpPreSecs = 0.125;  
erpPostSecs = 0.125;
baseRange = [0.01, 0.05]; 
roiRange = [-0.02, 0.16]; 

%% 2. LOAD DATA
disp(['Loading: ', filePath]);
if exist(filePath, 'file')
    rawFile = load(filePath);
    Y = rawFile.Y; 
else
    error('File not found.');
end

idx_trig = 70;      
idx_data = 2:65;     

trigger_raw = Y(idx_trig, :);
data = Y(idx_data, :);

%% 3. TRIGGER RECOVERY (The "Sawtooth" Fix)
disp('Analyzing Trigger Channel...');

% A. Calculate Derivative and ROUND it
triggerDiff = round(diff(trigger_raw)); 

% B. Debug Output
unique_steps = unique(triggerDiff);
disp('Unique step sizes found:');
disp(unique_steps(1:min(10, length(unique_steps)))'); 

% C. Apply "0503" Logic
triggerConditionedDiff = zeros(size(triggerDiff));
count_odds = 0;

% FIX: Removed the transpose (') so it iterates elements, not columns
for k = unique_steps 
    if mod(k, 2) ~= 0 && k ~= 0 
        % Found an ODD step (Trigger Event)
        idx = find(triggerDiff == k);
        triggerConditionedDiff(idx) = k / abs(k); % Store as +1 (Onset) or -1 (Offset)
        count_odds = count_odds + length(idx);
    end
end
fprintf('Found %d "Odd" events (Potential Triggers).\n', count_odds);

% D. Hardcoded Fixes (From original code)
if trialNum == 1
    if 30157 <= length(triggerConditionedDiff)
        triggerConditionedDiff(30157) = 1;
    end
elseif trialNum == 2
    triggerConditionedDiff(32945) =  1;
    triggerConditionedDiff(39389) = -1;
end

% E. Reconstruct Pulses
onsetIdx_temp  = find(triggerConditionedDiff ==  1) + 1;
offsetIdx_temp = find(triggerConditionedDiff == -1);

% Match pairs
min_len = min(length(onsetIdx_temp), length(offsetIdx_temp));
triggerConditioned = zeros(size(trigger_raw));
for i = 1:min_len
    triggerConditioned(onsetIdx_temp(i):offsetIdx_temp(i)) = 1;
end

%% 4. CUT ARTIFACTS
cutSamples = ceil(cutSecs * FS);
data(:, 1:cutSamples) = [];
triggerConditioned(:, 1:cutSamples) = [];

%% 5. FILTERING
disp('Filtering Data...');
if notchFlag
    fNotch = (50:50:min(FS/2, 550)).';
    fAdd = [-12, 0, 12, 24];
    fCenter = fNotch + repmat(fAdd, length(fNotch), 1);
    fCenter = sort(fCenter(:), 1, 'ascend');
    fCenter(fCenter > FS/2) = [];
    
    qFac = 35;
    for i = 1:length(fCenter)
        wo = fCenter(i) / (FS/2);
        bw = wo / qFac;
        [b, a] = iirnotch(wo, bw);
        data = filtfilt(b, a, data.').'; 
    end
end

if bpFlag
    [b, a] = butter(3, 2*bpRange / FS, 'bandpass');
    data = filtfilt(b, a, data.').';
end

%% 6. FINAL TRIGGER PROCESSING
trigDiffFinal = diff(triggerConditioned, 1, 2);
onsetIdx = find(trigDiffFinal == 1) + 1;

% Apply Delay
delaySamples = floor(trigDelaySecs * FS);
onsetIdx = onsetIdx + delaySamples;

fprintf('Final Valid Triggers: %d (Expected ~25)\n', length(onsetIdx));

%% 7. EPOCHING
disp('Epoching...');
tERP_raw = (-erpPreSecs : 1/FS : erpPostSecs);
erp_stack = NaN(size(data, 1), length(tERP_raw), length(onsetIdx));

for i = 1:length(onsetIdx)
    idx_relative = onsetIdx(i) + (tERP_raw * FS);
    idx_relative = round(idx_relative); 
    
    if idx_relative(1) >= 1 && idx_relative(end) <= size(data, 2)
        erp_stack(:, :, i) = data(:, idx_relative);
    end
end

% Baseline Correction
baseIdx = (baseRange(1) <= tERP_raw) & (tERP_raw < baseRange(2));
baseline_vals = mean(erp_stack(:, baseIdx, :), 2);
erp_stack = erp_stack - baseline_vals;

% Average
erpAvg = mean(erp_stack, 3, 'omitnan');

%% 8. FINAL VISUALIZATION (Butterfly + Grid Layout)

% --- A. RE-CALCULATE TIME VECTOR ---
% Ensure we have the correct time axis for the ROI
roiIdx = (roiRange(1) <= tERP_raw) & (tERP_raw <= roiRange(2));
tFinal = tERP_raw(roiIdx) * 1000; % Convert to milliseconds
erpFinal = erpAvg(:, roiIdx);

% --- B. FIGURE 1: BUTTERFLY PLOT (All Channels Superimposed) ---
figure('Name', 'Butterfly Plot (All 60+ Channels)', 'Color', 'w');
hold on;

% 1. Plot every single channel in faint gray
plot(tFinal, erpFinal', 'Color', [0.7, 0.7, 0.7, 0.5]); 

% 2. Plot the Grand Average (Mean of all channels) in Thick Black
grandAvg = mean(erpFinal, 1, 'omitnan');
plot(tFinal, grandAvg, 'k', 'LineWidth', 2);

hold off;
grid on;
xlim([-20 160]); % Match GUI Window
xlabel('Time (ms)');
ylabel('Amplitude (µV)');
title(['Grand Average + All Traces (n=' num2str(length(onsetIdx)) ')']);
legend('Individual Channels', 'Grand Average');


% --- C. FIGURE 2: 8x8 GRID LAYOUT (Matches Original GUI) ---
figure('Name', '8x8 MEA Grid Layout', 'Color', 'w');

% Create a mapping for an 8x8 grid (Row 1=A, Row 8=H)
% Note: This assumes standard column-major filling (A1, B1... A2, B2...)
% If the map looks rotated, we just transpose the index.
plot_counter = 0;
for col = 1:8
    for row = 1:8
        plot_counter = plot_counter + 1;
        
        % Safety check: don't crash if we have fewer than 64 channels
        if plot_counter <= size(erpFinal, 1)
            subplot(8, 8, (row-1)*8 + col); % Fill row by row
            
            % Plot the individual channel
            plot(tFinal, erpFinal(plot_counter, :), 'b', 'LineWidth', 1);
            
            % Formatting to look like the GUI
            axis off; % Hide axes for cleaner look
            xlim([-20 160]);
            
            % Optional: Add label (e.g., A1, B1)
            % rowChar = char(64 + row); % 1='A', 2='B'
            % text(-15, max(erpFinal(plot_counter,:)), [rowChar num2str(col)], 'FontSize', 6);
        end
    end
end
sgtitle('Reconstructed 8x8 Grid');

%% TRIGGER DIAGNOSTIC TOOL
% close all; clear; clc;
% 
% % CONFIGURATION
% filePath = 'ID0503//0503_MEA72_01_ref_ground_512Hz.mat';
% idx_expected_trig = 70;
% 
% % LOAD
% disp(['Loading: ', filePath]);
% rawFile = load(filePath);
% Y = rawFile.Y;
% [numRows, numCols] = size(Y);
% disp(['Total Rows in Y: ', num2str(numRows)]);
% 
% % CANDIDATE SCANNING
% % We will look at the expected channel + usually hidden "padding" channels
% candidates = [65, 66, 67, 68, 69, 70]; 
% candidates = candidates(candidates <= numRows); % Safety check
% 
% figure('Name', 'Trigger Channel Inspector', 'Color', 'w');
% 
% for i = 1:length(candidates)
%     chIdx = candidates(i);
%     chData = Y(chIdx, :);
% 
%     subplot(length(candidates), 1, i);
%     plot(chData);
%     title(['Row ' num2str(chIdx) ' - Min: ' num2str(min(chData)) ' Max: ' num2str(max(chData))]);
%     grid on;
% 
%     % Check for pulses
%     binary_pulses = sum(diff(chData) > 0.5); % simple check
%     ylabel(['~' num2str(binary_pulses) ' Ups']);
% end
% 
% disp('Inspect the figure. Which Row number looks like a square wave (pulses)?');

%% PART 2: DASHBOARD RECREATION (Run after Part 1)
% This script generates the 4 standard validation figures.

% --- CONFIGURATION ---
channelLabels = cell(64, 1);
% Generate labels A1..A8, B1..B8, etc.
rows = 'ABCDEFGH';
idx = 0;
for r = 1:8
    for c = 1:8
        idx = idx + 1;
        channelLabels{idx} = [rows(r) num2str(c)];
    end
end

%% FIGURE 1: AVERAGED ERPs (Standard 8x8 Grid)
figure('Name', '1. Averaged ERPs (n=25)', 'Color', 'w', 'Position', [100, 100, 1200, 900]);
sgtitle(['Subject 0503 - Averaged ERPs']);

for i = 1:64
    subplot(8, 8, i);
    plot(tFinal, erpAvg(i, roiIdx), 'b', 'LineWidth', 1);
    
    % Styling to match original
    grid off; box off; axis tight;
    ylim([-150 150]); % Fixed scale for comparison
    title(channelLabels{i}, 'FontSize', 8, 'FontWeight', 'normal');
    
    % Only show axis labels on edges to reduce clutter
    if mod(i, 8) == 1; ylabel('µV'); else; set(gca, 'YTickLabel', []); end
    if i > 56; xlabel('ms'); else; set(gca, 'XTickLabel', []); end
end


%% FIGURE 2: SINGLE SWEEPS (Overlaid Trials)
figure('Name', '2. Single Sweeps', 'Color', 'w', 'Position', [150, 150, 1200, 900]);
sgtitle('Subject 0503 - Single Sweeps (All Trials)');

t_roi = tFinal;
for i = 1:64
    subplot(8, 8, i);
    hold on;
    % Plot all trials for this channel
    % erp_stack dimensions: (Channel, Time, Trial)
    single_channel_data = squeeze(erp_stack(i, roiIdx, :)); 
    plot(t_roi, single_channel_data, 'Color', [0.5 0.5 0.5 0.5]); % Faint gray
    
    % Plot Average on top in Red
    plot(t_roi, erpAvg(i, roiIdx), 'r', 'LineWidth', 1);
    
    hold off;
    axis tight; box off;
    title(channelLabels{i}, 'FontSize', 8);
    
    % Hide axes for clean look (like original)
    set(gca, 'XTick', [], 'YTick', []);
end


%% FIGURE 3: COLOR CODED SWEEPS (Image Matrix)
figure('Name', '3. Color Coded Sweeps', 'Color', 'w', 'Position', [200, 200, 1200, 900]);
sgtitle('Subject 0503 - Color Coded Amplitude');

% Setup colors
colormap('parula'); 

for i = 1:64
    subplot(8, 8, i);
    
    % Get data: Time x Trial
    % Transpose so X=Time, Y=Trial Number
    imgData = squeeze(erp_stack(i, roiIdx, :))'; 
    
    imagesc(tFinal, 1:size(imgData,1), imgData);
    
    % Styling
    caxis([-100 100]); % Set color limits to highlight contrast
    axis xy; % Normal axis direction
    title(channelLabels{i}, 'FontSize', 8);
    set(gca, 'XTick', [], 'YTick', []);
end


%% FIGURE 4: POWER SPECTRA (Continuous Data)
figure('Name', '4. Power Spectra (Continuous)', 'Color', 'w', 'Position', [250, 250, 1200, 900]);
sgtitle('Subject 0503 - Power Spectra (0-200 Hz)');

% Parameters for Welch's Method
nfft = 1024;
window = hanning(512);
noverlap = 256;

for i = 1:64
    subplot(8, 8, i);
    
    % Calculate PSD
    [pxx, f] = pwelch(data(i, :), window, noverlap, nfft, FS);
    
    plot(f, 10*log10(pxx), 'b'); % Plot in dB
    
    xlim([0 200]); % Match original range
    title(channelLabels{i}, 'FontSize', 8);
    box off;
    
    % Minimal Axes
    if i > 56; xlabel('Hz'); else; set(gca, 'XTickLabel', []); end
    set(gca, 'YTickLabel', []);
end

disp('All 4 Dashboards Generated.');
%% PART 3: EXACT VISUALIZATION REPRODUCTION
% This script recreates the original layout and scaling behavior.

% --- 1. DEFINE SPATIAL MAPPING (From Gen_Info Metadata) ---
% Rows: 1=A, 2=B, 3=C, 4=D, 5=E, 6=F, 7=G, 8=H, 9=J (Skips I)
row_map = [1 1 1 1 1 1 2 2 2 2 2 2 3 3 3 3 3 3 3 3 4 4 4 4 4 4 4 4 5 5 5 5 5 5 5 5 6 6 6 6 6 6 6 6 7 7 7 7 7 7 7 7 8 8 8 8 8 8 9 9 9 9 9 9];
col_map = [1 2 3 6 7 8 1 2 3 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 2 3 4 5 6 7 2 3 4 5 6 7];
row_chars = 'ABCDEFGHJ'; % Note: "I" is skipped in standard MEA

% --- 2. CONFIGURATION ---
% Toggle this to match the checkbox in the screenshot
NORMALIZE_CHECKBOX = true;  % TRUE = Fixed Scale (-500 to 500), FALSE = Dynamic

% --- 3. GENERATE FIGURE ---
f = figure('Name', 'Reconstructed Dashboard', 'Color', 'w', 'Position', [100, 50, 1400, 900]);

% Create a grid of 9 Rows x 8 Columns
for i = 1:64
    r = row_map(i);
    c = col_map(i);
    
    % Calculate subplot index (1 to 72)
    plot_idx = (r-1)*8 + c;
    
    subplot(9, 8, plot_idx);
    hold on;
    
    % A. Draw the Vertical Line at 0ms (The "Trigger" line)
    xline(0, 'Color', [0.4 0.4 0.4], 'LineWidth', 1.5);
    
    % B. Plot the Data
    plot(tFinal, erpAvg(i, roiIdx), 'b', 'LineWidth', 1);
    
    % C. Generate Label (e.g., A1, J7)
    label = [row_chars(r) num2str(c)];
    title(label, 'FontSize', 8, 'FontWeight', 'bold');
    
    % D. SCALING LOGIC (The "Normalize" behavior)
    xlim([-20 120]); % Matches the X-axis in your screenshot
    
    if NORMALIZE_CHECKBOX
        % Checked: Everything fixed to -500 to +500
        ylim([-500 500]);
        % Only show Y-ticks on the left-most plots to reduce clutter?
        % The original shows ticks on all, so we keep them.
        set(gca, 'YTick', [-500 0 500]); 
    else
        % Unchecked: Dynamic Auto-Scaling (Fit to data)
        axis tight;
        % Add a little padding so peaks don't touch the roof
        yl = ylim;
        range = yl(2) - yl(1);
        ylim([yl(1)-0.1*range, yl(2)+0.1*range]);
    end
    
    % E. STYLING
    grid off; box on;
    set(gca, 'FontSize', 7);
    
    % Remove X-Tick labels for inner plots (keep bottom row J)
    if r < 9
        set(gca, 'XTickLabel', []);
    end
    
    hold off;
end

sgtitle(['Subject 0503 - Averaged ERPs (Normalize = ' num2str(NORMALIZE_CHECKBOX) ')']);

%% PART 4: ADVANCED SPATIAL ANALYSIS (CSD & BIPOLAR)
% Paste this at the end of your existing script.
% It uses 'erpAvg', 'tFinal', 'roiIdx', and the mapping variables.

disp('Calculating Spatial Transforms...');

% --- 1. SETUP: RECONSTRUCT THE 2D GRID ---
% We must convert the linear 64-channel array back into a 9x8 matrix (Voltage Grid)
% Dimensions: [Rows (9) x Cols (8) x TimePoints]
[nChannels, nTime] = size(erpAvg(:, roiIdx));
V_grid = NaN(9, 8, nTime); 

% Re-define maps just in case they aren't in workspace
row_map = [1 1 1 1 1 1 2 2 2 2 2 2 3 3 3 3 3 3 3 3 4 4 4 4 4 4 4 4 5 5 5 5 5 5 5 5 6 6 6 6 6 6 6 6 7 7 7 7 7 7 7 7 8 8 8 8 8 8 9 9 9 9 9 9];
col_map = [1 2 3 6 7 8 1 2 3 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 2 3 4 5 6 7 2 3 4 5 6 7];

for i = 1:64
    r = row_map(i); 
    c = col_map(i);
    V_grid(r, c, :) = erpAvg(i, roiIdx);
end

% --- 2. CALCULATION: BIPOLAR MONTAGE (Row-wise) ---
% Formula: Bipolar(col) = Voltage(col) - Voltage(col+1)
% This creates a "longitudinal" chain along the rows.
Bipolar_grid = diff(V_grid, 1, 2); % Diff along dimension 2 (Columns)

% --- 3. CALCULATION: CURRENT SOURCE DENSITY (CSD) ---
% Formula: CSD = -Laplacian(Voltage)
% Approximation: 4*V_center - (V_up + V_down + V_left + V_right)
CSD_grid = NaN(size(V_grid));

% Laplacian Kernel (Standard 5-point stencil)
% Note: We use negative kernel because CSD is proportional to -Laplacian
kern = [0 -1 0; -1 4 -1; 0 -1 0]; 

for t = 1:nTime
    % Extract one time slice (2D image of voltage)
    frame = squeeze(V_grid(:, :, t));
    
    % Apply 2D convolution (valid region only to avoid edge artifacts)
    % 'same' returns central part, but edges are inaccurate so we mask them later
    csd_frame = conv2(frame, kern, 'same');
    
    CSD_grid(:, :, t) = csd_frame;
end

% --- 4. VISUALIZATION A: BIPOLAR TRACES ---
figure('Name', 'Bipolar Montage (Row-wise Differences)', 'Color', 'w');
sgtitle('Bipolar Montage (Local Contrast)');
time_axis = tFinal;

plot_count = 0;
% We iterate up to 7 columns because Bipolar reduces width by 1
for r = 1:9
    for c = 1:7
        plot_count = plot_count + 1;
        
        % Data is effectively (Col) - (Col+1)
        trace = squeeze(Bipolar_grid(r, c, :));
        
        % Skip if data is NaN (gaps in the chip)
        if all(isnan(trace)), continue; end
        
        subplot(9, 8, (r-1)*8 + c);
        plot(time_axis, trace, 'k', 'LineWidth', 0.5);
        
        axis tight; box off; 
        set(gca, 'XTick', [], 'YTick', [], 'Visible', 'on');
        
        % Add Zero Line
        yline(0, 'Color', [0.8 0.8 0.8]);
    end
end


% --- 5. VISUALIZATION B: CSD SNAPSHOT (Source Localization) ---
% Instead of squiggly lines, CSD is best viewed as a HEATMAP.
% We will find the time point with the strongest activity and map it.

% Find the Global Field Power (GFP) peak to pick the best time
gfp = std(erpAvg(:, roiIdx), 0, 1); 
[~, peakIdx] = max(gfp); 
peakTimeMs = tFinal(peakIdx);

figure('Name', 'Source Localization (CSD vs Voltage)', 'Color', 'w', 'Position', [100, 100, 1000, 500]);

% Subplot 1: Voltage Map (Monopolar)
subplot(1, 2, 1);
imagesc(squeeze(V_grid(:, :, peakIdx))); 
colormap(gca, 'parula'); colorbar;
title(['Voltage Potential at ' num2str(peakTimeMs, '%.1f') 'ms']);
xlabel('Column'); ylabel('Row');
axis square; 

% Subplot 2: CSD Map (Source/Sink)
subplot(1, 2, 2);
% We ignore the outer rim (edges) because CSD calculation is invalid there
csd_snapshot = squeeze(CSD_grid(:, :, peakIdx));
csd_snapshot(1,:) = NaN; csd_snapshot(end,:) = NaN; % Mask Rows
csd_snapshot(:,1) = NaN; csd_snapshot(:,end) = NaN; % Mask Cols

imagesc(csd_snapshot);
colormap(gca, 'jet'); % Jet is standard for CSD (Blue=Source, Red=Sink)
colorbar;
title(['Current Source Density at ' num2str(peakTimeMs, '%.1f') 'ms']);
xlabel('Column'); ylabel('Row');
axis square;

sgtitle('Comparison: Blurry Potential vs. Localized Source');