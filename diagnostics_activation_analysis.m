% diagnostics_activation_analysis.m
% Comprehensive diagnostics for VSD activation masks (3x and 4x)
% - Loads averaged dF/F movie and activation_mask_3x.h5, activation_mask_4x.h5
% - Computes global mean/std/max per frame, percent-active per frame
% - Running mean (photobleaching/illum drift), frame-to-frame difference (motion proxy)
% - Flags suspicious frames and creates per-frame diagnostics (images + CC stats)
% - Saves figures, MAT, and CSV summary
%
% Usage:
%   Run this from a MATLAB working directory with access to:
%     data/preprocessing/averaged_movie_E0B0-B3.h5
%     data/activation_mask_3x.h5
%     data/activation_mask_4x.h5
%
% Output:
%   - figures/ (PNG files)
%   - results/threshold_sensitivity_diagnostics.mat
%   - results/threshold_sensitivity_frame_summary.csv

clearvars; close all; clc;

%% --------- User parameters ---------
dff_file     = 'data/averaged_movie_E0B0-B3_unbinned.h5';
dff_dataset  = '/functional_dff';
mask3_file   = 'data/activation_mask_3x.h5';
mask4_file   = 'data/activation_mask_4x.h5';
mask_dataset = '/activation_mask';

out_dir_figs = 'data/';
out_dir_res  = 'data/';

% Running mean window (frames) for drift check
running_win = 15;   % ~ (adjustable)

% Suspicious thresholds (robust)
zscore_thresh_global_mean = 6;   % large global mean jump
percent_active_fold = 5;         % percent_active > mean + fold*std (per-mask)
motion_mad_factor = 6;           % frame-diff > median + factor*MAD

% Percentile floor test (informational only)
% (not used to change masks here, only diagnostics)
per_frame_peak_percentiles = [0.10, 0.15, 0.20];

%% create output dirs
if ~exist(out_dir_figs,'dir'), mkdir(out_dir_figs); end
if ~exist(out_dir_res,'dir'), mkdir(out_dir_res); end

%% Load data
fprintf('Loading dF/F movie: %s %s\n', dff_file, dff_dataset);
try
    dff = h5read(dff_file, dff_dataset);   % H x W x T
catch ME
    error('Failed to read dF/F movie: %s', ME.message);
end

fprintf('Loading masks: %s and %s\n', mask3_file, mask4_file);
try
    mask3 = h5read(mask3_file, mask_dataset); mask3 = logical(mask3);
    mask4 = h5read(mask4_file, mask_dataset); mask4 = logical(mask4);
catch ME
    error('Failed to load masks: %s', ME.message);
end

[H,W,T] = size(dff);
total_pixels = H*W;
fprintf('Dimensions: [%d %d %d]  Total pixels: %d\n', H, W, T, total_pixels);

%% Compute global timecourses
% mean, std, max per frame
mean_t = squeeze(mean(mean(dff,1),2));        % T x 1
% robust std across pixels per frame
dff_resh = reshape(dff, [], T);               % (H*W) x T
std_t  = squeeze(std(double(dff_resh),0,1))'; % 1 x T => transpose to Tx1
max_t  = squeeze(max(max(dff,[],1),[],2));

% running mean (photobleaching / illumination drift)
running_mean = movmean(mean_t, running_win);
running_std  = movmean(std_t, running_win);

%% Percent active per frame for each mask
pct3 = squeeze(sum(sum(mask3,1),2)) / total_pixels * 100;  % Tx1
pct4 = squeeze(sum(sum(mask4,1),2)) / total_pixels * 100;

%% Motion proxy: frame-to-frame sum absolute difference
frame_diff = zeros(T-1,1);
for t=2:T
    frame_diff(t-1) = sum(abs(dff_resh(:,t) - dff_resh(:,t-1)), 'all'); 
end
% normalize for plotting
frame_diff_z = (frame_diff - median(frame_diff)) / (1.4826*mad(frame_diff,1)); % robust z

%% Basic plots: global timecourses + percent active
f1 = figure('Name','Global Timecourses and Percent Active','Position',[100 100 1400 800]);
subplot(3,1,1);
plot(1:T, mean_t, '-k','LineWidth',1.4); hold on;
plot(1:T, running_mean, '-r','LineWidth',1.4);
ylabel('Global mean dF/F'); legend('mean','running mean');
title('Global mean dF/F (black) and running mean (red)');

subplot(3,1,2);
plot(1:T, std_t, '-k','LineWidth',1.2); hold on;
plot(1:T, running_std, '-r','LineWidth',1.2);
ylabel('Global std dF/F'); legend('std','running std');

subplot(3,1,3);
yyaxis left
plot(1:T, pct3, '-','LineWidth',1.6,'Color',[0.85 0.33 0.10]); hold on;
plot(1:T, pct4, '-','LineWidth',1.6,'Color',[0 0.5 0]);
ylabel('Percent active (%)');
yyaxis right
plot(1:T-1, frame_diff_z, '-','LineWidth',1.2,'Color',[0.2 0.6 0.9]);
ylabel('Frame diff (robust z)');
xlabel('Frame');
legend('3x pct','4x pct','frame-diff z','Location','northwest');

saveas(f1, fullfile(out_dir_figs,'global_timecourses_pct_active.png'));

%% Correlation check: percent active vs global mean
r3 = corr(pct3, mean_t, 'Type','Spearman');
r4 = corr(pct4, mean_t, 'Type','Spearman');
fprintf('Spearman corr(mean_t, pct3) = %.3f\n', r3);
fprintf('Spearman corr(mean_t, pct4) = %.3f\n', r4);

%% Detect suspicious frames
sus_frames = false(T,1);
% 1) large percent_active spikes (per-mask)
p3_mean = mean(pct3); p3_std = std(pct3);
p4_mean = mean(pct4); p4_std = std(pct4);
sus3 = pct3 > (p3_mean + percent_active_fold * p3_std);
sus4 = pct4 > (p4_mean + percent_active_fold * p4_std);

% 2) global mean zscore
gm_z = (mean_t - median(mean_t)) / (1.4826*mad(mean_t,1));
sus_global = abs(gm_z) > zscore_thresh_global_mean;

% 3) motion proxy
frame_diff_thresh = median(frame_diff) + motion_mad_factor * mad(frame_diff,1);
sus_motion = [false; frame_diff > frame_diff_thresh]; % align to frame t index

sus_frames = sus3 | sus4 | sus_global | sus_motion;

% Also always include the peak frames for inspection (top percent active)
[~, idx_peak3] = max(pct3);
[~, idx_peak4] = max(pct4);
sus_frames(idx_peak3) = true;
sus_frames(idx_peak4) = true;

sus_list = find(sus_frames);
fprintf('Flagged suspicious frames: %s\n', mat2str(sus_list'));

% Save per-frame summary table
frame_table = table((1:T)', mean_t, std_t, max_t, ...
    [pct3, pct4], [double([sus3,sus4])], [double(sus_global), double([false;frame_diff>frame_diff_thresh])], ...
    'VariableNames', {'Frame','GlobalMean','GlobalStd','GlobalMax','Pct3_Pct4','SusPctMask','SusGlobal_Motion'});
writetable(frame_table, fullfile(out_dir_res,'frame_summary_table.csv'));

%% For each suspicious frame: create spatial diagnostics
fprintf('Creating per-frame diagnostics for flagged frames...\n');
per_frame_stats = struct('frame',{},'n_active3',{},'n_active4',{},'n_diff3minus4',{},'largest_cc_size',{},'num_cc',{},'cc_centroids',{});

for ii = 1:numel(sus_list)
    tframe = sus_list(ii);
    fprintf('  Inspect frame %d\n', tframe);
    
    dff_frame = dff(:,:,tframe);
    mask3_frame = logical(mask3(:,:,tframe));
    mask4_frame = logical(mask4(:,:,tframe));
    diff34 = mask3_frame & ~mask4_frame;
    
    % connected components on 3x mask and diff
    CC3 = bwconncomp(mask3_frame);
    stats3 = regionprops(CC3,'Area','Centroid');
    areas3 = [stats3.Area];
    centroids3 = reshape([stats3.Centroid],2,[])';
    if isempty(areas3)
        largest_cc = 0;
    else
        largest_cc = max(areas3);
    end
    
    % connected components on diff mask
    CCd = bwconncomp(diff34);
    statsd = regionprops(CCd,'Area','Centroid');
    areasd = [statsd.Area];
    
    % store stats
    per_frame_stats(end+1).frame = tframe;
    per_frame_stats(end).n_active3 = sum(mask3_frame(:));
    per_frame_stats(end).n_active4 = sum(mask4_frame(:));
    per_frame_stats(end).n_diff3minus4 = sum(diff34(:));
    per_frame_stats(end).largest_cc_size = largest_cc;
    per_frame_stats(end).num_cc = CC3.NumObjects;
    per_frame_stats(end).cc_centroids = centroids3;
    
    % Create figure
    fh = figure('Visible','off','Position',[200 200 1600 900]);
    % dF/F left
    subplot(2,3,1);
    imagesc(dff_frame); axis image; colormap(gca,'jet'); colorbar;
    title(sprintf('dF/F - Frame %d\nMin %.5f Max %.5f', tframe, min(dff_frame(:)), max(dff_frame(:))));
    
    subplot(2,3,2);
    imagesc(mask3_frame); axis image; colormap(gca,'gray');
    title(sprintf('3x mask - %d active (%.2f%%)', per_frame_stats(end).n_active3, per_frame_stats(end).n_active3/total_pixels*100));
    
    subplot(2,3,3);
    imagesc(mask4_frame); axis image; colormap(gca,'gray');
    title(sprintf('4x mask - %d active (%.2f%%)', per_frame_stats(end).n_active4, per_frame_stats(end).n_active4/total_pixels*100));
    
    subplot(2,3,4);
    imagesc(diff34); axis image; colormap(gca,'gray');
    title(sprintf('3x only (3x & ~4x) - %d pixels', per_frame_stats(end).n_diff3minus4));
    
    subplot(2,3,5);
    % scatter centroid overlay on dff
    imagesc(dff_frame); axis image; colormap(gca,'jet'); hold on;
    if ~isempty(centroids3)
        plot(centroids3(:,1), centroids3(:,2), 'wo','MarkerSize',6,'LineWidth',1.2);
    end
    title('3x CC centroids over dF/F');
    
    subplot(2,3,6);
    histogram(areas3, 30);
    xlabel('CC area (pixels)');
    ylabel('Count');
    title('Connected component area distribution (3x)');
    
    sgtitle(sprintf('Diagnostics Frame %d', tframe));
    out_fn = fullfile(out_dir_figs, sprintf('diagnostic_frame_%03d.png', tframe));
    saveas(fh, out_fn);
    close(fh);
end

% Save per-frame stats struct
save(fullfile(out_dir_res,'per_frame_diagnostics.mat'),'per_frame_stats','frame_table','sus_list');

%% Photobleaching / illumination drift check
% compute linear trend of global mean across experiment
p = polyfit((1:T)', mean_t, 1);
trend_line = polyval(p, (1:T)');
drift_percent = 100*(trend_line(end)-trend_line(1))/abs(trend_line(1)+eps);
fprintf('Global mean trend slope = %.3e (drift %.2f%% over recording)\n', p(1), drift_percent);

% Save summary MAT
summary.mult_correlations = struct('r3',r3,'r4',r4);
summary.global_trend = p;
summary.sus_list = sus_list;
summary.running_win = running_win;

save(fullfile(out_dir_res,'threshold_sensitivity_diagnostics.mat'), 'summary', 'frame_table', 'per_frame_stats');

%% Quick text summary
fprintf('\nSUMMARY\n');
fprintf('  Frames flagged: %s\n', mat2str(sus_list'));
fprintf('  Spearman corr mean vs pct3: %.3f, mean vs pct4: %.3f\n', r3, r4);
fprintf('  Global mean drift: slope=%.3e, drift=%.2f%%\n', p(1), drift_percent);
fprintf('  Figures saved to: %s\n', out_dir_figs);
fprintf('  Results saved to: %s\n', out_dir_res);

fprintf('\nDiagnostic run complete. Review images in %s, inspect per_frame_diagnostics.mat for component stats.\n', out_dir_figs);