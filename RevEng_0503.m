%% REVERSE ENGINEERED PIPELINE: 0503 MEA DATA
% Check SEP_Project_ReadMe.md for documentations of this standalone script.
% tried adding bipolar montages and current source localization, very buggy
% need to fix it to be able to correlate with the VSD data
% but the reverse engineer of the SEP project works though, the data is
% saved in the filePath variable, see below, the data is already
% rereferenced and only 1 animal 0503 was viable as per the records given
% to me

close all; clear; clc;

%% 1. CONFIGURATION
filePath = 'data//ID0503//0503_MEA72_03_ref_ground_512Hz.mat';
FS = 10000;               
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
plot(tFinal, erpFinal', 'Color', [0.7, 0.7, 0.7, 0.5]); 
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
plot_counter = 0;
for col = 1:8
    for row = 1:8
        plot_counter = plot_counter + 1;
        if plot_counter <= size(erpFinal, 1)
            subplot(8, 8, (row-1)*8 + col); 
            plot(tFinal, erpFinal(plot_counter, :), 'b', 'LineWidth', 1);
            axis off; 
            xlim([-20 160]);
        end
    end
end
sgtitle('Reconstructed 8x8 Grid');

%% PART 2: DASHBOARD RECREATION 
% --- CONFIGURATION ---
channelLabels = cell(64, 1);
rows = 'ABCDEFGH';
idx = 0;
for r = 1:8
    for c = 1:8
        idx = idx + 1;
        channelLabels{idx} = [rows(r) num2str(c)];
    end
end

%% FIGURE 1: AVERAGED ERPs 
figure('Name', '1. Averaged ERPs (n=25)', 'Color', 'w', 'Position', [100, 100, 1200, 900]);
sgtitle(['Subject 0503 - Averaged ERPs']);
for i = 1:64
    subplot(8, 8, i);
    plot(tFinal, erpAvg(i, roiIdx), 'b', 'LineWidth', 1);
    grid off; box off; axis tight;
    ylim([-150 150]); 
    title(channelLabels{i}, 'FontSize', 8, 'FontWeight', 'normal');
    if mod(i, 8) == 1; ylabel('µV'); else; set(gca, 'YTickLabel', []); end
    if i > 56; xlabel('ms'); else; set(gca, 'XTickLabel', []); end
end

%% FIGURE 2: SINGLE SWEEPS 
figure('Name', '2. Single Sweeps', 'Color', 'w', 'Position', [150, 150, 1200, 900]);
sgtitle('Subject 0503 - Single Sweeps (All Trials)');
t_roi = tFinal;
for i = 1:64
    subplot(8, 8, i);
    hold on;
    single_channel_data = squeeze(erp_stack(i, roiIdx, :)); 
    plot(t_roi, single_channel_data, 'Color', [0.5 0.5 0.5 0.5]); 
    plot(t_roi, erpAvg(i, roiIdx), 'r', 'LineWidth', 1);
    hold off;
    axis tight; box off;
    title(channelLabels{i}, 'FontSize', 8);
    set(gca, 'XTick', [], 'YTick', []);
end

%% FIGURE 3: COLOR CODED SWEEPS 
figure('Name', '3. Color Coded Sweeps', 'Color', 'w', 'Position', [200, 200, 1200, 900]);
sgtitle('Subject 0503 - Color Coded Amplitude');
colormap('parula'); 
for i = 1:64
    subplot(8, 8, i);
    imgData = squeeze(erp_stack(i, roiIdx, :))'; 
    imagesc(tFinal, 1:size(imgData,1), imgData);
    caxis([-100 100]); 
    axis xy; 
    title(channelLabels{i}, 'FontSize', 8);
    set(gca, 'XTick', [], 'YTick', []);
end

%% FIGURE 4: POWER SPECTRA 
figure('Name', '4. Power Spectra (Continuous)', 'Color', 'w', 'Position', [250, 250, 1200, 900]);
sgtitle('Subject 0503 - Power Spectra (0-200 Hz)');
nfft = 1024;
window = hanning(512);
noverlap = 256;
for i = 1:64
    subplot(8, 8, i);
    [pxx, f] = pwelch(data(i, :), window, noverlap, nfft, FS);
    plot(f, 10*log10(pxx), 'b'); 
    xlim([0 200]); 
    title(channelLabels{i}, 'FontSize', 8);
    box off;
    if i > 56; xlabel('Hz'); else; set(gca, 'XTickLabel', []); end
    set(gca, 'YTickLabel', []);
end

%% PART 3: EXACT VISUALIZATION REPRODUCTION
% --- 1. DEFINE SPATIAL MAPPING (From Gen_Info Metadata) ---
row_map = [1 1 1 1 1 1 2 2 2 2 2 2 3 3 3 3 3 3 3 3 4 4 4 4 4 4 4 4 5 5 5 5 5 5 5 5 6 6 6 6 6 6 6 6 7 7 7 7 7 7 7 7 8 8 8 8 8 8 9 9 9 9 9 9];
col_map = [1 2 3 6 7 8 1 2 3 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 2 3 4 5 6 7 2 3 4 5 6 7];
row_chars = 'ABCDEFGHJ'; 

% LEFT-RIGHT FLIP: Mirror column indices so col 1<->8, 2<->7, etc.
% This corrects the spatial orientation of the electrode layout display.
col_map_flipped = (max(col_map) + 1) - col_map;

% --- 2. CONFIGURATION ---
NORMALIZE_CHECKBOX = true;  

% --- 3. GENERATE FIGURE ---
f = figure('Name', 'Reconstructed Dashboard', 'Color', 'w', 'Position', [100, 50, 1400, 900]);
for i = 1:64
    r = row_map(i);
    c = col_map_flipped(i);   % Use flipped column for correct L/R orientation
    plot_idx = (r-1)*8 + c;
    
    subplot(9, 8, plot_idx);
    hold on;
    xline(0, 'Color', [0.4 0.4 0.4], 'LineWidth', 1.5);
    plot(tFinal, erpAvg(i, roiIdx), 'b', 'LineWidth', 1);
    label = [row_chars(r) num2str(c)];
    title(label, 'FontSize', 8, 'FontWeight', 'bold');
    xlim([-20 120]); 
    
    if NORMALIZE_CHECKBOX
        ylim([-500 500]);
        set(gca, 'YTick', [-500 0 500]); 
    else
        axis tight;
        yl = ylim;
        range = yl(2) - yl(1);
        ylim([yl(1)-0.1*range, yl(2)+0.1*range]);
    end
    
    grid off; box on;
    set(gca, 'FontSize', 7);
    if r < 9
        set(gca, 'XTickLabel', []);
    end
    hold off;
end
sgtitle(['Subject 0503 - Averaged ERPs (Normalize = ' num2str(NORMALIZE_CHECKBOX) ')']);

%% PART 4: ADVANCED SPATIAL ANALYSIS (CSD & BIPOLAR) - UPDATED
disp('Calculating Spatial Transforms (FlexMEA72 Configuration)...');

% --- 1. SETUP: RECONSTRUCT THE 2D GRID ---
[nChannels, nTime] = size(erpAvg(:, roiIdx));
V_grid = NaN(9, 8, nTime); 

for i = 1:64
    r = row_map(i); 
    c = col_map_flipped(i);   % Use flipped column for correct L/R orientation
    V_grid(r, c, :) = erpAvg(i, roiIdx);
end

% --- 2. CALCULATION: BIPOLAR MONTAGE (Row-wise) ---
Bipolar_grid = diff(V_grid, 1, 2); 

% --- 3. CALCULATION: CURRENT SOURCE DENSITY (CSD) ---
% FlexMEA72 specific spacing (in mm)
dx = 0.625; % Column spacing
dy = 0.750; % Row spacing

% Weights for rectangular Laplacian
wx = 1 / (dx^2);
wy = 1 / (dy^2);

% CSD is proportional to the negative Laplacian (-Laplacian)
% We calculate the spatial 2nd derivative accounting for rectangular geometry
CSD_kernel = [ 0,         -wy,          0; 
              -wx,   2*(wx + wy),      -wx; 
               0,         -wy,          0 ];

CSD_grid = NaN(size(V_grid));
[X, Y_grid] = meshgrid(1:8, 1:9); % For spatial interpolation

for t = 1:nTime
    frame = squeeze(V_grid(:, :, t));
    
    % --- NaN INFECTION HANDLING ---
    % Find valid recording nodes
    valid_mask = ~isnan(frame);
    
    % Temporarily fill missing electrodes (REF/GND gaps) via interpolation
    % This prevents conv2 from turning the whole array into NaNs
    if any(~valid_mask(:))
        frame_filled = griddata(X(valid_mask), Y_grid(valid_mask), frame(valid_mask), X, Y_grid, 'cubic');
        
        % Fallback for extreme edges where cubic might output NaN
        nan_still = isnan(frame_filled);
        if any(nan_still(:))
            frame_fallback = griddata(X(valid_mask), Y_grid(valid_mask), frame(valid_mask), X, Y_grid, 'nearest');
            frame_filled(nan_still) = frame_fallback(nan_still);
        end
        frame_to_process = frame_filled;
    else
        frame_to_process = frame;
    end
    
    % Apply the weighted 2D Laplacian Convolution
    csd_frame = conv2(frame_to_process, CSD_kernel, 'same');
    
    % Re-apply the original NaN mask so REF/GND stay invisible!
    csd_frame(~valid_mask) = NaN;
    
    CSD_grid(:, :, t) = csd_frame;
end

% --- 4. VISUALIZATION A: BIPOLAR TRACES ---
figure('Name', 'Bipolar Montage (Row-wise Differences)', 'Color', 'w');
sgtitle('Bipolar Montage (Local Contrast)');
time_axis = tFinal;
plot_count = 0;

for r = 1:9
    for c = 1:7
        plot_count = plot_count + 1;
        trace = squeeze(Bipolar_grid(r, c, :));
        if all(isnan(trace)), continue; end
        
        subplot(9, 8, (r-1)*8 + c);
        plot(time_axis, trace, 'k', 'LineWidth', 0.5);
        axis tight; box off; 
        set(gca, 'XTick', [], 'YTick', [], 'Visible', 'on');
        yline(0, 'Color', [0.8 0.8 0.8]);
    end
end

% --- 5. VISUALIZATION B: CSD SNAPSHOT (Source Localization) ---
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
csd_snapshot = squeeze(CSD_grid(:, :, peakIdx));

% Mask the outer rim (Laplacian is mathematically invalid at the edges)
csd_snapshot(1,:) = NaN; csd_snapshot(end,:) = NaN; 
csd_snapshot(:,1) = NaN; csd_snapshot(:,end) = NaN; 

imagesc(csd_snapshot);
colormap(gca, 'jet'); % Blue = Source, Red = Sink
colorbar;
title(['Current Source Density at ' num2str(peakTimeMs, '%.1f') 'ms']);
xlabel('Column'); ylabel('Row');
axis square;
sgtitle('Comparison: Blurry Potential vs. Localized Source');

%% PART 5: ANIMATE AND EXPORT CSD PROPAGATION
disp('Generating CSD Animation Video...');

% --- 1. SETUP VIDEO WRITER ---
videoFilename = 'Subject_0503_CSD_Propagation.mp4';
v = VideoWriter(videoFilename, 'MPEG-4');
v.FrameRate = 30; % 30 frames per second gives a nice slow-motion view
open(v);

% --- 2. SETUP FIGURE ---
% Create a dedicated figure for the animation
figAnim = figure('Name', 'CSD Animation', 'Color', 'w', 'Position', [200, 200, 800, 700]);

% Determine fixed color limits so the scale doesn't jump around
% We use the peak we found earlier to set a symmetric color scale
max_c = max(abs(CSD_grid(:)), [], 'omitnan'); 
c_limits = [-max_c * 0.8, max_c * 0.8]; % Cap at 80% of absolute max for better contrast

% --- 3. ANIMATION LOOP ---
nFrames = length(tFinal);

for i = 1:nFrames
    % Extract the current time frame
    csd_frame = squeeze(CSD_grid(:, :, i));
    
    % Mask the outer rim (Laplacian is mathematically invalid at the edges)
    csd_frame(1,:) = NaN; csd_frame(end,:) = NaN; 
    csd_frame(:,1) = NaN; csd_frame(:,end) = NaN; 
    
    % Plot
    imagesc(csd_frame);
    colormap(gca, 'jet');
    caxis(c_limits); % Lock the color scale
    colorbar;
    
    % Formatting
    axis square;
    xlabel('Column'); 
    ylabel('Row');
    
    % Add dynamic title with current time
    title(sprintf('Cortical Current Source Density\nTime: %.1f ms', tFinal(i)), ...
        'FontSize', 14, 'FontWeight', 'bold');
    
    % Force MATLAB to draw the frame immediately
    drawnow;
    
    % Capture the frame and write to video
    frame = getframe(figAnim);
    writeVideo(v, frame);
end

% --- 4. CLEANUP ---
close(v);
disp(['Animation saved successfully as: ', videoFilename]);

%% PART 6: VIRTUAL TRACE ANALYSIS (Correlating Voltage vs CSD at a specific electrode)
disp('Extracting Virtual Traces for specific electrodes...');

% We want to look at electrode D1. 
% Looking at the FlexMEA72 layout: D = Row 4, 1 = Column 1.
% NOTE: Because of the L/R flip, the physical column 1 is now at
% col_map_flipped position 8. Use the original col_map for data indexing.
target_row = 4;
target_col = 1;  % This refers to the original (unflipped) col_map value

% Find which channel index (1-64) corresponds to D1
target_channel_idx = find(row_map == target_row & col_map == target_col);

% 1. Extract the Raw Voltage Trace for D1
voltage_trace_D1 = erpAvg(target_channel_idx, roiIdx);

% 2. Extract the CSD Trace for D1 (from the 3D CSD_grid)
% Use the flipped column to index into V_grid/CSD_grid correctly
target_col_flipped = (max(col_map) + 1) - target_col;
csd_trace_D1 = squeeze(CSD_grid(target_row, target_col_flipped, :))';

% --- PLOT THE COMPARISON ---
figure('Name', 'Electrode D1: Voltage vs. CSD', 'Color', 'w', 'Position', [300, 300, 800, 400]);

% Left Y-Axis: Raw Voltage
yyaxis left
plot(tFinal, voltage_trace_D1, 'b-', 'LineWidth', 1.5);
ylabel('Voltage Potential (\muV)', 'Color', 'b');
set(gca, 'YColor', 'b');
ylim([-max(abs(voltage_trace_D1))*1.2, max(abs(voltage_trace_D1))*1.2]); % Symmetrical limits

% Right Y-Axis: Current Source Density
yyaxis right
plot(tFinal, csd_trace_D1, 'r-', 'LineWidth', 1.5);
ylabel('Current Source Density', 'Color', 'r');
set(gca, 'YColor', 'r');
ylim([-max(abs(csd_trace_D1))*1.2, max(abs(csd_trace_D1))*1.2]);

% Formatting
xline(0, 'k--', 'LineWidth', 1); % Mark the stimulus trigger
xlim([-20 120]);
xlabel('Time (ms)');
title('Electrode D1: Voltage vs. Localized CSD');
grid on;
legend('Raw Voltage (Volume Conducted)', 'CSD (Localized Source)', 'Stimulus', 'Location', 'best');

%% PART 7: INTERACTIVE CSD GUI
% Requires: CSD_grid, V_grid, erpAvg, erp_stack, tFinal, roiIdx,
%           row_map, col_map, col_map_flipped, row_chars
% Compatible with Live Editor (.mlx) — uses appdata instead of nested scope.

disp('Launching Interactive CSD GUI...');

% --- 1. PRECOMPUTE CLEAN CSD FRAMES ---
CSD_display = CSD_grid;
CSD_display(1,:,:)   = NaN;
CSD_display(end,:,:) = NaN;
CSD_display(:,1,:)   = NaN;
CSD_display(:,end,:) = NaN;

nFrames  = length(tFinal);
max_c    = max(abs(CSD_display(:)), [], 'omitnan');
c_limits = [-max_c * 0.8, max_c * 0.8];

% --- 2. ELECTRODE LOOKUP: (row, col) -> channel index ---
electrode_map = NaN(9, 8);
for i = 1:64
    electrode_map(row_map(i), col_map_flipped(i)) = i;
end

% --- 3. CREATE FIGURE ---
hFig = figure('Name', 'Interactive CSD Viewer', 'Color', 'k', ...
    'Position', [50, 50, 1300, 700], ...
    'CloseRequestFcn', @guiCloseReq);

% CSD axes (left)
axCSD = axes('Parent', hFig, ...
    'Position', [0.03, 0.12, 0.50, 0.80], ...
    'Color', 'k', 'XColor', 'w', 'YColor', 'w');

% Waveform axes (right) — independent, just shows clicked electrode
axWave = axes('Parent', hFig, ...
    'Position', [0.58, 0.15, 0.38, 0.70], ...
    'Color', 'k', 'XColor', 'w', 'YColor', 'w');
title(axWave,  'Click an electrode on the map to view its waveform', 'Color', 'w', 'FontSize', 10);
xlabel(axWave, 'Time (ms)', 'Color', 'w');
ylabel(axWave, 'Amplitude (\muV)  /  CSD (a.u.)', 'Color', 'w');
grid(axWave, 'on');
set(axWave, 'GridColor', [0.3 0.3 0.3]);
xlim(axWave, [tFinal(1) tFinal(end)]);

% --- 4. INITIAL FRAME ---
frameData = squeeze(CSD_display(:, :, 1));
axes(axCSD);
hImg = imagesc(axCSD, frameData, c_limits);
set(hImg, 'AlphaData', double(~isnan(frameData)));
colormap(axCSD, jet(256));
colorbar(axCSD, 'Color', 'w');
axis(axCSD, 'square');
xlabel(axCSD, 'Column', 'Color', 'w');
ylabel(axCSD, 'Row',    'Color', 'w');
hTitle = title(axCSD, ...
    sprintf('CSD  |  %.1f ms  |  [SPACE] Play/Pause  |  [R] Replay  |  ← → Scrub', tFinal(1)), ...
    'Color', 'w', 'FontSize', 9);

hold(axCSD, 'on');
hMarker = plot(axCSD, NaN, NaN, 'w+', 'MarkerSize', 14, 'LineWidth', 2);
hold(axCSD, 'off');

% --- 5. UI CONTROLS ---
btnPlay = uicontrol('Style', 'pushbutton', 'String', '▶  Play', ...
    'Position', [60, 20, 110, 35], ...
    'BackgroundColor', [0.2 0.6 0.2], 'ForegroundColor', 'w', ...
    'FontSize', 11, 'FontWeight', 'bold', ...
    'Callback', @onPlay);

uicontrol('Style', 'pushbutton', 'String', '↺  Replay', ...
    'Position', [185, 20, 110, 35], ...
    'BackgroundColor', [0.2 0.4 0.7], 'ForegroundColor', 'w', ...
    'FontSize', 11, 'FontWeight', 'bold', ...
    'Callback', @onReplay);

sldFrame = uicontrol('Style', 'slider', ...
    'Min', 1, 'Max', nFrames, 'Value', 1, ...
    'SliderStep', [1/(nFrames-1), 10/(nFrames-1)], ...
    'Position', [315, 22, 300, 22], ...
    'Callback', @onSlider);

lblTime = uicontrol('Style', 'text', 'String', sprintf('%.1f ms', tFinal(1)), ...
    'Position', [625, 20, 80, 25], ...
    'BackgroundColor', 'k', 'ForegroundColor', 'w', 'FontSize', 10);

% --- 6. STORE ALL SHARED DATA IN APPDATA (Live Editor safe) ---
setappdata(hFig, 'CSD_display',   CSD_display);
setappdata(hFig, 'erpAvg',        erpAvg);
setappdata(hFig, 'erp_stack',     erp_stack);
setappdata(hFig, 'tFinal',        tFinal);
setappdata(hFig, 'roiIdx',        roiIdx);
setappdata(hFig, 'row_map',       row_map);
setappdata(hFig, 'col_map_flipped', col_map_flipped);
setappdata(hFig, 'row_chars',     row_chars);
setappdata(hFig, 'electrode_map', electrode_map);
setappdata(hFig, 'nFrames',       nFrames);
setappdata(hFig, 'c_limits',      c_limits);
setappdata(hFig, 'frame',         1);
setappdata(hFig, 'playing',       false);
setappdata(hFig, 'timerObj',      []);

% Store handles
setappdata(hFig, 'hImg',    hImg);
setappdata(hFig, 'hTitle',  hTitle);
setappdata(hFig, 'hMarker', hMarker);
setappdata(hFig, 'btnPlay', btnPlay);
setappdata(hFig, 'sldFrame',sldFrame);
setappdata(hFig, 'lblTime', lblTime);
setappdata(hFig, 'axWave',  axWave);
setappdata(hFig, 'axCSD',   axCSD);

% --- 7. CALLBACKS ---
set(hImg,  'ButtonDownFcn', @onImageClick);
set(hFig,  'KeyPressFcn',   @onKeyPress);

% =========================================================================

function updateFrame(hFig, f)
    nF       = getappdata(hFig, 'nFrames');
    f        = max(1, min(nF, round(f)));
    setappdata(hFig, 'frame', f);

    CSD_d    = getappdata(hFig, 'CSD_display');
    tF       = getappdata(hFig, 'tFinal');
    c_lim    = getappdata(hFig, 'c_limits');
    hImg     = getappdata(hFig, 'hImg');
    hTitle   = getappdata(hFig, 'hTitle');
    sldFrame = getappdata(hFig, 'sldFrame');
    lblTime  = getappdata(hFig, 'lblTime');

    fd = squeeze(CSD_d(:, :, f));
    set(hImg,    'CData', fd, 'AlphaData', double(~isnan(fd)));
    clim(getappdata(hFig,'axCSD'), c_lim);
    set(hTitle,  'String', sprintf('CSD  |  %.1f ms  |  [SPACE] Play/Pause  |  [R] Replay  |  ← → Scrub', tF(f)));
    set(sldFrame,'Value',  f);
    set(lblTime, 'String', sprintf('%.1f ms', tF(f)));
    drawnow limitrate;
end

function onPlay(src, ~)
    hFig    = ancestor(src, 'figure');
    playing = getappdata(hFig, 'playing');
    btnPlay = getappdata(hFig, 'btnPlay');
    tF      = getappdata(hFig, 'tFinal');
    nF      = getappdata(hFig, 'nFrames');

    if playing
        % --- PAUSE ---
        t = getappdata(hFig, 'timerObj');
        if ~isempty(t) && isvalid(t), stop(t); delete(t); end
        setappdata(hFig, 'playing',  false);
        setappdata(hFig, 'timerObj', []);
        set(btnPlay, 'String', '▶  Play', 'BackgroundColor', [0.2 0.6 0.2]);
    else
        % --- PLAY ---
        f = getappdata(hFig, 'frame');
        if f >= nF, setappdata(hFig, 'frame', 1); end
        setappdata(hFig, 'playing', true);
        set(btnPlay, 'String', '⏸  Pause', 'BackgroundColor', [0.7 0.4 0.1]);

        dt_ms  = tF(2) - tF(1);          % neural ms per frame
        period = max(dt_ms / 10, 0.05);    % real seconds per frame (~10x slower, adjust divisor to taste)

        t = timer('ExecutionMode', 'fixedRate', 'Period', period, ...
            'TimerFcn',  {@timerStep, hFig}, ...
            'StopFcn',   {@timerStopped, hFig});
        setappdata(hFig, 'timerObj', t);
        start(t);
    end
end

function timerStep(~, ~, hFig)
    if ~isvalid(hFig), return; end
    nF = getappdata(hFig, 'nFrames');
    f  = getappdata(hFig, 'frame');
    if f >= nF
        t = getappdata(hFig, 'timerObj');
        if ~isempty(t) && isvalid(t), stop(t); end
        return;
    end
    setappdata(hFig, 'frame', f + 1);
    updateFrame(hFig, f + 1);
end

function timerStopped(~, ~, hFig)
    if ~isvalid(hFig), return; end
    btnPlay = getappdata(hFig, 'btnPlay');
    t       = getappdata(hFig, 'timerObj');
    if ~isempty(t) && isvalid(t), delete(t); end
    setappdata(hFig, 'playing',  false);
    setappdata(hFig, 'timerObj', []);
    if isvalid(btnPlay)
        set(btnPlay, 'String', '▶  Play', 'BackgroundColor', [0.2 0.6 0.2]);
    end
end

function onReplay(src, ~)
    hFig = ancestor(src, 'figure');
    % Stop timer if running
    playing = getappdata(hFig, 'playing');
    if playing
        t = getappdata(hFig, 'timerObj');
        if ~isempty(t) && isvalid(t), stop(t); delete(t); end
        setappdata(hFig, 'playing',  false);
        setappdata(hFig, 'timerObj', []);
        btnPlay = getappdata(hFig, 'btnPlay');
        set(btnPlay, 'String', '▶  Play', 'BackgroundColor', [0.2 0.6 0.2]);
    end
    setappdata(hFig, 'frame', 1);
    updateFrame(hFig, 1);
    onPlay(getappdata(hFig, 'btnPlay'), []);
end

function onSlider(src, ~)
    hFig = ancestor(src, 'figure');
    % Slider scrubs independently — pauses playback if running
    playing = getappdata(hFig, 'playing');
    if playing
        t = getappdata(hFig, 'timerObj');
        if ~isempty(t) && isvalid(t), stop(t); delete(t); end
        setappdata(hFig, 'playing',  false);
        setappdata(hFig, 'timerObj', []);
        btnPlay = getappdata(hFig, 'btnPlay');
        set(btnPlay, 'String', '▶  Play', 'BackgroundColor', [0.2 0.6 0.2]);
    end
    updateFrame(hFig, round(src.Value));
end

function onKeyPress(src, evt)
    hFig = src;
    f    = getappdata(hFig, 'frame');
    switch evt.Key
        case 'space'
            onPlay(getappdata(hFig, 'btnPlay'), []);
        case 'r'
            onReplay(getappdata(hFig, 'btnPlay'), []);
        case 'rightarrow'
            updateFrame(hFig, f + 1);
        case 'leftarrow'
            updateFrame(hFig, f - 1);
    end
end

function onImageClick(src, evt)
    hFig = ancestor(src, 'figure');

    pt  = evt.IntersectionPoint;
    col = round(pt(1));
    row = round(pt(2));

    electrode_map   = getappdata(hFig, 'electrode_map');
    axWave          = getappdata(hFig, 'axWave');
    hMarker         = getappdata(hFig, 'hMarker');
    erpAvg          = getappdata(hFig, 'erpAvg');
    erp_stack       = getappdata(hFig, 'erp_stack');
    tFinal          = getappdata(hFig, 'tFinal');
    roiIdx          = getappdata(hFig, 'roiIdx');
    row_map         = getappdata(hFig, 'row_map');
    col_map_flipped = getappdata(hFig, 'col_map_flipped');
    row_chars       = getappdata(hFig, 'row_chars');
    CSD_display     = getappdata(hFig, 'CSD_display');

    if row < 1 || row > 9 || col < 1 || col > 8
        return;
    end

    ch = electrode_map(row, col);
    if isnan(ch)
        title(axWave, 'No electrode at this location', 'Color', 'w', 'FontSize', 11);
        return;
    end

    % Update crosshair marker on CSD map
    set(hMarker, 'XData', col, 'YData', row);

    % Electrode label
    label = [row_chars(row_map(ch)) num2str(col_map_flipped(ch))];

    % --- WAVEFORM PLOT (independent of CSD playback) ---
    % Clear all previous traces and reset dual y-axes before plotting
    cla(axWave);
    yyaxis(axWave, 'left');  cla(axWave);
    yyaxis(axWave, 'right'); cla(axWave);
    yyaxis(axWave, 'left');
    hold(axWave, 'on');

    % Single sweeps (grey)
    sweeps = squeeze(erp_stack(ch, roiIdx, :));
    plot(axWave, tFinal, sweeps, 'Color', [0.4 0.4 0.4 0.45]);

    % Average voltage (white)
    plot(axWave, tFinal, erpAvg(ch, roiIdx), 'w', 'LineWidth', 2);

    % CSD trace (red)
    csd_tr = squeeze(CSD_display(row_map(ch), col_map_flipped(ch), :))';
    yyaxis(axWave, 'right');
    plot(axWave, tFinal, csd_tr, 'r-', 'LineWidth', 1.5);
    ylabel(axWave, 'CSD (a.u.)', 'Color', 'r');
    set(axWave, 'YColor', 'r');
    yyaxis(axWave, 'left');
    ylabel(axWave, 'Amplitude (\muV)', 'Color', 'w');
    set(axWave, 'YColor', 'w');

    % Stimulus line
    xline(axWave, 0, '--', 'Color', [0.9 0.85 0.2], 'LineWidth', 1.2, 'Label', 'Stim');

    hold(axWave, 'off');
    title(axWave, ['Electrode ' label '   |   Grey: single sweeps   |   White: avg voltage   |   Red: CSD'], ...
        'Color', 'w', 'FontSize', 9);
    xlabel(axWave, 'Time (ms)', 'Color', 'w');
    xlim(axWave,  [tFinal(1) tFinal(end)]);
    grid(axWave,  'on');
    set(axWave, 'GridColor', [0.3 0.3 0.3], 'Color', 'k', ...
        'XColor', 'w', 'FontSize', 8);
end

function guiCloseReq(src, ~)
    % Clean up timer before closing
    t = getappdata(src, 'timerObj');
    if ~isempty(t) && isvalid(t), stop(t); delete(t); end
    delete(src);
end

disp('GUI ready.  SPACE = play/pause  |  R = replay  |  ← → = scrub  |  Click electrode = waveform');