clc; clear; close all;

% =========================================================================
% CONFIGURATION  –  edit only this block
% =========================================================================
cfg(1).file        = 'C:\Roy\MSc\Thesis\Scripts\data\batch_output500\led_E0B0_vsd_corrected_dff.h5';
cfg(1).dataset     = '/functional_dff';
cfg(1).label       = 'Pre-processed \DeltaF/F_0';
cfg(1).is_raw      = false;

cfg(2).file        = 'C:\Roy\MSc\Thesis\Scripts\converted__500\led_E0B0.h5';
cfg(2).dataset     = '/image_stack';
cfg(2).label       = 'Raw \rightarrow \DeltaF/F_0';
cfg(2).is_raw      = true;

% Shared index / ROI settings
baseline_idx = 8:740;
response_idx = 370:380;
roi_x        = 200:250;
roi_y        = 200:250;

% =========================================================================
% EXPORT SETTINGS
% =========================================================================
export.folder  = 'C:\Roy\MSc\Thesis\Figures';   % output folder
export.dpi     = 300;                             % 300 dpi for print/poster
export.width   = 20;                              % cm
export.height  = 11;                              % cm
export.format  = '-dpng';

% =========================================================================
% PRESENTATION THEME
% =========================================================================
th.bg          = [0.10 0.10 0.14];   % figure background
th.ax          = [0.10 0.10 0.14];   % axes (flush with figure)
th.trace       = [0.30 0.85 0.72];   % teal trace
th.baseline_c  = [0.98 0.78 0.25];   % amber  – baseline
th.response_c  = [0.95 0.38 0.38];   % coral  – response
th.zero        = [0.55 0.55 0.65];   % zero-line
th.text        = [0.95 0.95 0.97];
th.subtext     = [0.65 0.65 0.72];
th.grid        = [0.22 0.22 0.30];
th.font        = 'Helvetica';         % clean sans-serif for slides
th.fsize_title = 16;
th.fsize_ax    = 13;
th.fsize_annot = 13;
th.fsize_leg   = 11;

% =========================================================================
% PROCESS & PLOT
% =========================================================================
if ~exist(export.folder, 'dir'), mkdir(export.folder); end

for k = 1:numel(cfg)

    % --- load & normalise -------------------------------------------
    data  = double(h5read(cfg(k).file, cfg(k).dataset));
    trace = squeeze(mean(mean(data(roi_x, roi_y, :), 1), 2));

    if cfg(k).is_raw
        baseline_mean = mean(trace(baseline_idx));
        trace = (trace - baseline_mean) / baseline_mean;
    end

    % --- SNR --------------------------------------------------------
    noise_std  = std(trace(baseline_idx));
    signal_amp = max(trace(response_idx)) - mean(trace(baseline_idx));
    snr        = signal_amp / noise_std;
    fprintf('[%d] %s  →  SNR = %.2f\n', k, cfg(k).label, snr);

    % --- figure sizing (presentation) --------------------------------
    fig = figure('Name',        sprintf('Figure %d', k), ...
                 'Color',       th.bg, ...
                 'Units',       'centimeters', ...
                 'Position',    [5 + (k-1)*22, 8, export.width, export.height], ...
                 'NumberTitle', 'off', ...
                 'Renderer',    'painters');   % vector-quality render

    ax = axes('Parent',     fig, ...
              'Color',      th.ax, ...
              'XColor',     th.text, ...
              'YColor',     th.text, ...
              'GridColor',  th.grid, ...
              'GridAlpha',  0.7, ...
              'FontName',   th.font, ...
              'FontSize',   th.fsize_ax, ...
              'LineWidth',  1.0, ...
              'TickDir',    'out', ...
              'TickLength', [0.008 0.008], ...
              'Box',        'off');

    % tight inset so trace uses full canvas
    ax.Position = [0.09 0.13 0.88 0.78];
    hold(ax, 'on');

    % y limits first (needed for patches)
    ydata = trace;
    ypad  = 0.03 * range(ydata);
    yl    = [min(ydata)-ypad, max(ydata)+ypad];
    xlim(ax, [1 numel(trace)]);
    ylim(ax, yl);

    % --- shaded regions ---------------------------------------------
    bx = [baseline_idx(1)  baseline_idx(end) baseline_idx(end) baseline_idx(1)];
    rx = [response_idx(1)  response_idx(end) response_idx(end) response_idx(1)];
    py = [yl(1) yl(1) yl(2) yl(2)];

    patch(ax, bx, py, th.baseline_c, 'FaceAlpha', 0.10, ...
          'EdgeColor', 'none', 'DisplayName', 'Baseline');
    patch(ax, rx, py, th.response_c, 'FaceAlpha', 0.22, ...
          'EdgeColor', 'none', 'DisplayName', 'Response');

    % --- zero line --------------------------------------------------
    yline(ax, 0, '-', 'Color', [th.zero, 0.7], 'LineWidth', 0.8, ...
          'HandleVisibility', 'off');

    % --- trace ------------------------------------------------------
    plot(ax, trace, 'Color', th.trace, 'LineWidth', 2.0, ...
         'DisplayName', 'Mean ROI trace');

    % --- baseline boundary ticks ------------------------------------
    xline(ax, baseline_idx(1),   '--', 'Color', [th.baseline_c, 0.85], ...
          'LineWidth', 1.2, 'HandleVisibility', 'off');
    xline(ax, baseline_idx(end), '--', 'Color', [th.baseline_c, 0.85], ...
          'LineWidth', 1.2, 'HandleVisibility', 'off');

    % --- SNR badge (top-right) --------------------------------------
    text(ax, 0.985, 0.95, sprintf('SNR = %.2f', snr), ...
         'Units', 'normalized', 'HorizontalAlignment', 'right', ...
         'VerticalAlignment', 'top', ...
         'Color', [0 0 0], 'BackgroundColor', [0.95 0.95 0.95], ...
         'Margin', 4, 'EdgeColor', [0.7 0.7 0.7], ...
         'FontName', th.font, 'FontSize', th.fsize_annot, 'FontWeight', 'bold');

    % --- labels & title ---------------------------------------------
    title(ax, cfg(k).label, ...
          'Color', th.text, 'FontName', th.font, ...
          'FontSize', th.fsize_title, 'FontWeight', 'bold');
    xlabel(ax, 'Frame  #', ...
          'Color', th.text, 'FontName', th.font, 'FontSize', th.fsize_ax);
    ylabel(ax, '\DeltaF / F_0', ...
          'Color', th.text, 'FontName', th.font, 'FontSize', th.fsize_ax);

    % --- grid & legend ----------------------------------------------
    grid(ax, 'on');
    leg = legend(ax, {'Baseline','Response','Mean ROI trace'}, ...
                 'TextColor',  th.text, ...
                 'Color',      [0.16 0.16 0.21], ...
                 'EdgeColor',  th.grid, ...
                 'FontName',   th.font, ...
                 'FontSize',   th.fsize_leg, ...
                 'Location',   'southwest');

    % =========================================================================
    % EXPORT
    % =========================================================================
    safe_label = regexprep(cfg(k).label, '[\\/:*?"<>| ]', '_');
    safe_label = regexprep(safe_label, '_+', '_');          % collapse repeats
    fname      = fullfile(export.folder, sprintf('fig%d_%s.png', k, safe_label));

    % Match print size to figure size at target DPI
    fig.PaperUnits    = 'centimeters';
    fig.PaperSize     = [export.width, export.height];
    fig.PaperPosition = [0, 0, export.width, export.height];

    print(fig, fname, export.format, sprintf('-r%d', export.dpi));
    fprintf('  Saved → %s\n', fname);
end