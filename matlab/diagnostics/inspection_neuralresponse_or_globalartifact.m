%% Visual Inspection: Raw dF/F + Activation Masks
% % Run this and manually inspect frames to see:
% % Does the signal look real neuronal response or artifact?
% % Are activated pixels clustered in HL cortex or scattered everywhere?
% % Does the dF/F value progression make sense?
% % Red Flags to Look For:
% %  Global increase in dF/F across entire image (suggests stray light or photobleaching)
% %  **Activation spread too uniformly (should have regional focus in HL area)
% %  **Peak response too late (>50ms post-stimulus, but neural response should be ~13-18ms)
% %  **Activation percentage too high (27% of entire imaging field seems excessive)

clc; clear; close all;
dff_movie = h5read('data/preprocessing/averaged_movie_E0B0-B3.h5', '/functional_dff');
mask_3x = h5read('data/activation_mask_3x.h5', '/activation_mask');
[H, W, T] = size(dff_movie);
fprintf('  ✓ Loaded: dF/F [%d, %d, %d] and Mask\n\n', H, W, T);

% Create figure with slider to inspect frame by frame
fig = figure('Name', 'Frame-by-Frame Inspection', 'NumberTitle', 'off', 'Position', [100, 100, 1400, 600]);

% Slider for frame selection
slider_handle = uicontrol('Style', 'slider', 'Min', 1, 'Max', T, 'Value', 25, ...
    'Position', [50, 20, 1300, 20], ...
    'Callback', {@updateDisplay, dff_movie, mask_3x, H, W});

% Initial display
updateDisplay(slider_handle, [], dff_movie, mask_3x, H, W);

fprintf('========================================\n');
fprintf('FRAME INSPECTION TOOL\n');
fprintf('========================================\n\n');
fprintf('Instructions:\n');
fprintf('  • Drag slider to inspect frames 1-%d\n', T);
fprintf('  • Look at LEFT: raw dF/F signal\n');
fprintf('  • Look at MIDDLE: activation mask (3×)\n');
fprintf('  • Look at RIGHT: overlay (red=signal, green=active)\n\n');
fprintf('Key frames to inspect:\n');
fprintf('  - Frame 20-30: Early response onset\n');
fprintf('  - Frame 50-75: Mid-response\n');
fprintf('  - Frame 125: Peak response\n\n');
fprintf('Questions to answer:\n');
fprintf('  ✓ Is activation LOCALIZED to one region (HL area)?\n');
fprintf('  ✓ Or is it SCATTERED/GLOBAL across entire image?\n');
fprintf('  ✓ Do dF/F values look realistic (±0.01 range)?\n');
fprintf('  ✓ Does timing match your MEA (P13-N18 ~13-18ms)?\n\n');

function updateDisplay(hObject, eventdata, dff_movie, mask_3x, H, W)
    frame_num = round(get(hObject, 'Value'));
    
    % Raw dF/F
    subplot(1, 3, 1);
    dff_frame = dff_movie(:, :, frame_num);
    imagesc(dff_frame);
    cbar1 = colorbar;
    cbar1.Label.String = 'dF/F';
    title(sprintf('Raw dF/F - Frame %d\nMin: %.6f, Max: %.6f, Mean: %.6f', ...
        frame_num, min(dff_frame(:)), max(dff_frame(:)), mean(dff_frame(:))));
    axis image;
    colormap(gca, 'jet');
    
    % Activation mask
    subplot(1, 3, 2);
    mask_frame = logical(mask_3x(:, :, frame_num));
    imagesc(mask_frame);
    colormap(gca, 'gray');
    n_active = sum(sum(mask_frame));
    title(sprintf('3× Mask - Frame %d\n%d pixels active (%.2f%%)', ...
        frame_num, n_active, n_active/(H*W)*100));
    axis image;
    
    % Overlay
    subplot(1, 3, 3);
    dff_normalized = (dff_frame - min(dff_frame(:))) / (max(dff_frame(:)) - min(dff_frame(:)));
    overlay = cat(3, dff_normalized, dff_normalized, zeros(H, W));  % dF/F in red channel
    overlay(repmat(mask_frame, [1, 1, 3])) = repmat([0, 1, 0], sum(mask_frame(:)), 1);  % Mask in green
    imagesc(overlay);
    title(sprintf('Overlay - Frame %d\nGreen = Activated pixels', frame_num));
    axis image;
end