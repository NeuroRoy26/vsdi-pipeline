%% pipeline_B_reconstruct.m
% Stage 2: ICA Reconstruction → Post-processing
% Loads saved decomposition from pipeline_A — reproducible every run.
%
% WORKFLOW:
%   1. Run pipeline_A → inspect PDF figures
%   2. Fill in CFG.recon_ICs below
%   3. publish('pipeline_B_reconstruct.m', 'pdf')

clc; clear; close all;

%% =========================================================================
%                        *** CONFIGURATION ***
% =========================================================================

CFG.decomp_file    = 'data/ica_decomposition.mat';
CFG.recon_mode     = 'selected';   % 'all' | 'selected' | 'exclude' | 'single'
CFG.recon_ICs      = [1 2];
CFG.sign_ass       = -1;

CFG.sigma          = 2.0;
CFG.floor_sens     = 0.0;
CFG.sat_pct        = 98.5;
CFG.colormap       = 'jet';
CFG.stimulus_frame = 376;
CFG.baseline_range = 200:370;    % frames used for baseline subtraction
CFG.active_range   = 374:400;    % frames used to compute saturation value
CFG.pre_stim_ms    = 500;
CFG.post_stim_ms   = 900;

CFG.recon_suffix   = 'final';
CFG.trace_suffix   = 'final';

% =========================================================================
%                        END OF CONFIGURATION
% =========================================================================

%% =========================================================================
%  LOAD DECOMPOSITION
% =========================================================================

fprintf('=== PIPELINE B — RECONSTRUCTION & POST-PROCESSING ===\n');
fprintf('Date/Time    : %s\n', datestr(now));
fprintf('Decomp file  : %s\n', CFG.decomp_file);
assert(exist(CFG.decomp_file,'file')==2,'Decomposition file not found. Run pipeline_A first.');

D = load(CFG.decomp_file);
ica_maps        = D.ica_maps;
ica_maps_flat   = D.ica_maps_flat;
ica_timecourses = D.ica_timecourses;
stats           = D.stats;
f               = D.f;
L               = D.L;
H=D.H; W=D.W; T=D.T; Fs=D.Fs; num_ICs=D.num_ICs;
explained_full  = D.explained_full;
src             = D.CFG;

fprintf('Source file  : %s\n', src.output_h5);
fprintf('ICA seed     : %d\n', src.ica_seed);
fprintf('Dimensions   : %d×%d px | %d frames | %.1f Hz\n', H,W,T,Fs);
fprintf('ICs available: %d\n\n', num_ICs);

%% =========================================================================
%  COMPONENT SELECTION & RECONSTRUCTION
% =========================================================================

switch lower(CFG.recon_mode)
    case 'all',      selected_ICs = 1:num_ICs;
    case 'selected', selected_ICs = CFG.recon_ICs;
    case 'exclude',  selected_ICs = setdiff(1:num_ICs, CFG.recon_ICs);
    case 'single',   selected_ICs = CFG.recon_ICs(1);
    otherwise,       error('Unknown recon_mode: ''%s''', CFG.recon_mode);
end
selected_ICs = unique(selected_ICs(:))';
selected_ICs(selected_ICs<1 | selected_ICs>num_ICs) = [];
excluded_ICs = setdiff(1:num_ICs, selected_ICs);
assert(~isempty(selected_ICs),'Component selection is empty.');

sign_ass = CFG.sign_ass;
fprintf('Mode         : %s\n', CFG.recon_mode);
fprintf('Selected ICs : %s\n', mat2str(selected_ICs));
fprintf('Excluded ICs : %s\n', mat2str(excluded_ICs));

Xrec  = sign_ass * (ica_maps_flat(:,selected_ICs) * ica_timecourses(:,selected_ICs).');
Xfull = sign_ass * (ica_maps_flat                 * ica_timecourses.');
Xnoise= Xfull - Xrec;   % removed signal

reconstructed_movie = reshape(Xrec,   H, W, T);
full_movie          = reshape(Xfull,  H, W, T);
noise_movie         = reshape(Xnoise, H, W, T);

%% Reconstruction quality metrics

var_total = var(Xfull(:));
var_sel   = var(Xrec(:));
var_noise = var(Xnoise(:));
var_pct   = 100 * var_sel   / var_total;
noise_pct = 100 * var_noise / var_total;

% Per-pixel correlation: reconstructed vs full
corr_map = zeros(H,W);
for row = 1:H
    for col = 1:W
        a = squeeze(full_movie(row,col,:));
        b = squeeze(reconstructed_movie(row,col,:));
        r = corrcoef(a,b);
        corr_map(row,col) = r(1,2);
    end
end
mean_corr = mean(corr_map(:),'omitnan');
med_corr  = median(corr_map(:),'omitnan');

% Residual RMS
rms_full  = rms(Xfull(:));
rms_noise = rms(Xnoise(:));
nrmse     = rms_noise / (rms_full + eps);

fprintf('\n=== RECONSTRUCTION QUALITY METRICS ===\n');
fprintf('Variance explained (selected ICs)  : %6.2f%%\n', var_pct);
fprintf('Variance removed   (excluded ICs)  : %6.2f%%\n', noise_pct);
fprintf('Per-pixel correlation (mean/median): %.4f / %.4f\n', mean_corr, med_corr);
fprintf('Normalised RMSE (residual/full)    : %.4f\n', nrmse);
fprintf('RMS full reconstruction            : %.6f\n', rms_full);
fprintf('RMS removed signal                 : %.6f\n', rms_noise);

%% Per-component contribution table

mag = zeros(num_ICs,1);
for k = 1:num_ICs
    c = ica_maps_flat(:,k)*ica_timecourses(:,k).';
    mag(k) = var(c(:));
end
pct = 100*mag/sum(mag);

fprintf('\n=== PER-COMPONENT CONTRIBUTION ===\n');
fprintf('%-5s %-10s %-12s %-10s %-10s %-10s %-10s %-20s\n', ...
    'IC','Var (%)','Dom Freq(Hz)','SpKurt','SpGini','TcMaxZ','TcAC','Decision');
fprintf('%s\n', repmat('-',1,90));
for k = 1:num_ICs
    dec = 'EXCLUDED';
    if ismember(k,selected_ICs), dec = 'KEPT'; end
    fprintf('%-5d %-10.2f %-12.2f %-10.2f %-10.3f %-10.2f %-10.3f %-20s\n', ...
        k, pct(k), stats(k).dom_freq, stats(k).sp_kurt, stats(k).sp_gini, ...
        stats(k).tc_maxz, stats(k).tc_autocorr, dec);
end
fprintf('\nKept  : %.2f%% total variance  (%d ICs)\n', sum(pct(selected_ICs)), numel(selected_ICs));
fprintf('Removed: %.2f%% total variance  (%d ICs)\n', sum(pct(excluded_ICs)),  numel(excluded_ICs));

%% Component overview figures (reproduced from saved decomp)

comps_per_fig = 4;
for fig_idx = 1:ceil(num_ICs/comps_per_fig)
    figure('Name',sprintf('ICA Components (batch %d)',fig_idx),'Color','w','Position',[50 50 1100 850]);
    s = (fig_idx-1)*comps_per_fig+1;
    e = min(s+comps_per_fig-1,num_ICs);
    for ki = 1:(e-s+1)
        k = s+ki-1;
        kept = ismember(k,selected_ICs);
        border_col = [0.1 0.7 0.1]; if ~kept, border_col=[0.8 0.1 0.1]; end

        subplot(comps_per_fig,4,(ki-1)*4+1);
        m = ica_maps(:,:,k);
        imagesc(m,[prctile(m(:),2) prctile(m(:),98)]);
        axis image off; colormap jet;
        title(sprintf('IC #%d | Kurt=%.1f | Gini=%.2f',k,stats(k).sp_kurt,stats(k).sp_gini));
        set(gca,'XColor',border_col,'YColor',border_col,'LineWidth',2);

        subplot(comps_per_fig,4,(ki-1)*4+2);
        plot((1:T)/Fs, ica_timecourses(:,k),'Color',[0.2 0.2 0.2],'LineWidth',0.8);
        axis tight; box off; xlabel('Time (s)');
        title(sprintf('MaxZ=%.1f | AC=%.2f',stats(k).tc_maxz,stats(k).tc_autocorr));

        subplot(comps_per_fig,4,(ki-1)*4+3);
        plot(f,stats(k).P1,'r','LineWidth',1.5); xlim([0 20]); box off;
        xlabel('Freq (Hz)'); xline(5,'--b');
        title(sprintf('%.2f Hz | <5Hz:%.0f%%',stats(k).dom_freq,stats(k).pwr_0_5hz));

        subplot(comps_per_fig,4,(ki-1)*4+4);
        histogram(ica_maps_flat(:,k),50,'FaceColor',[0.4 0.6 0.8],'EdgeColor','none');
        xlabel('Pixel value'); title(sprintf('Skew=%.2f',stats(k).sp_skew)); box off;
    end
    sgtitle(sprintf('ICA Batch %d  |  Green border=KEPT  Red=EXCLUDED  (seed=%d)', ...
        fig_idx, src.ica_seed));
end

%% Contribution bar chart

figure('Name','Component Contributions','Color','w','Position',[100 100 700 350]);
b = bar(1:num_ICs, pct, 'FaceColor','flat');
for k = 1:num_ICs
    if ismember(k,selected_ICs), b.CData(k,:)=[0.2 0.6 0.2];
    else,                         b.CData(k,:)=[0.8 0.2 0.2]; end
end
xlabel('IC #'); ylabel('% variance'); title('Component Variance Contributions');
legend({'Excluded','Kept'},'Location','northeast'); grid on;
text(0.5, max(pct)*0.92, sprintf('Kept: %.1f%%  |  Removed: %.1f%%', ...
    sum(pct(selected_ICs)), sum(pct(excluded_ICs))), ...
    'Units','data','FontSize',9,'Color','k');

%% Pixel-wise correlation map

figure('Name','Per-pixel Reconstruction Correlation','Color','w','Position',[100 100 800 350]);
subplot(1,2,1);
imagesc(corr_map,[0 1]); axis image off; colormap(gca,parula); colorbar;
title(sprintf('Pixel corr (recon vs full)  mean=%.3f', mean_corr));

subplot(1,2,2);
histogram(corr_map(:),50,'FaceColor',[0.3 0.5 0.8],'EdgeColor','none');
xlabel('Pearson r'); ylabel('# pixels');
xline(mean_corr,'--r',sprintf('mean=%.3f',mean_corr),'LineWidth',1.5);
title('Correlation distribution'); box off;
sgtitle('Spatial Reconstruction Fidelity');

%% =========================================================================
%  POST-PROCESSING
% =========================================================================

SIGMA      = CFG.sigma;
FLOOR_SENS = CFG.floor_sens;
SAT_PCT    = CFG.sat_pct;
stim_fr    = CFG.stimulus_frame;
orig_sr    = Fs;
ms_per_fr  = 1000/orig_sr;

M = double(reconstructed_movie);

% Structural background
structural_rgb = [];
if exist(src.output_h5,'file')
    try
        bg = double(mean(h5read(src.output_h5,'/structural'),3));
        bg_min=min(bg(:)); bg_max=max(bg(:));
        if bg_max>bg_min, bg_n=(bg-bg_min)/(bg_max-bg_min); else, bg_n=bg; end
        structural_rgb = cat(3,bg_n,bg_n,bg_n);
        fprintf('\nStructural background loaded.\n');
    catch ME, fprintf('Structural load failed: %s\n',ME.message); end
end

% Baseline subtract + smooth
baseline = mean(M(:,:,CFG.baseline_range),3);
M_smooth = zeros(H,W,T);
for t = 1:T
    M_smooth(:,:,t) = imgaussfilt(sign_ass*(M(:,:,t)-baseline), SIGMA);
end

active_data = M_smooth(:,:,CFG.active_range);
sat_val     = prctile(active_data(:), SAT_PCT);
floor_val   = sat_val * FLOOR_SENS;

%% Post-processing summary

fprintf('\n=== POST-PROCESSING PARAMETERS ===\n');
fprintf('Gaussian sigma       : %.1f px\n', SIGMA);
fprintf('Baseline frames      : %d–%d\n', CFG.baseline_range(1), CFG.baseline_range(end));
fprintf('Active window        : %d–%d\n', CFG.active_range(1), CFG.active_range(end));
fprintf('Saturation pct       : %.1f%%  → sat_val=%.5f\n', SAT_PCT, sat_val);
fprintf('Floor sensitivity    : %.2f  → floor_val=%.5f\n', FLOOR_SENS, floor_val);
fprintf('Sign assignment      : %+d\n', sign_ass);
fprintf('Stimulus frame       : %d  (%.1f ms)\n', stim_fr, stim_fr*ms_per_fr);

%% dF/F response amplitude map (mean over early response window)

resp_start = stim_fr + 1;
resp_end   = min(stim_fr + round(100/ms_per_fr), T);
resp_map   = mean(M_smooth(:,:,resp_start:resp_end), 3);
peak_map   = max(M_smooth(:,:,resp_start:resp_end), [], 3);

fprintf('\n=== RESPONSE AMPLITUDE METRICS ===\n');
fprintf('Response window      : frames %d–%d  (0 to +%.0f ms)\n', ...
    resp_start, resp_end, (resp_end-stim_fr)*ms_per_fr);
fprintf('Mean response dF/F   : %.5f\n', mean(resp_map(:)));
fprintf('Peak response dF/F   : %.5f\n', max(peak_map(:)));
fprintf('Response area (>50%% peak): %.1f px²\n', ...
    sum(resp_map(:) > 0.5*max(resp_map(:))));

figure('Name','Response Amplitude Maps','Color','w','Position',[50 50 1000 350]);
subplot(1,3,1);
imagesc(resp_map,[prctile(resp_map(:),2) prctile(resp_map(:),98)]);
axis image off; colormap jet; colorbar;
title(sprintf('Mean dF/F  (0 to +%.0fms)',(resp_end-stim_fr)*ms_per_fr));

subplot(1,3,2);
imagesc(peak_map,[prctile(peak_map(:),2) prctile(peak_map(:),98)]);
axis image off; colormap jet; colorbar;
title('Peak dF/F');

subplot(1,3,3);
thresh = 0.5*max(resp_map(:));
bw = resp_map > thresh;
imagesc(resp_map,[0 max(resp_map(:))]); axis image off; hold on;
contour(bw,[0.5 0.5],'w','LineWidth',1.5);
colormap(gca,jet); colorbar;
title(sprintf('50%% threshold  (%.0f px)', sum(bw(:))));
sgtitle('Response Amplitude (early window)');

%% Propagation speed estimation (centre-of-mass tracking)

fprintf('\n=== PROPAGATION ANALYSIS ===\n');
n_resp_frames = resp_end - resp_start + 1;
com_x = nan(n_resp_frames,1);
com_y = nan(n_resp_frames,1);

for fi = 1:n_resp_frames
    fr = M_smooth(:,:,resp_start+fi-1);
    fr(fr<0) = 0;
    total = sum(fr(:));
    if total > 0
        [xx,yy] = meshgrid(1:W,1:H);
        com_x(fi) = sum(sum(xx.*fr)) / total;
        com_y(fi) = sum(sum(yy.*fr)) / total;
    end
end

% Displacement in pixels per frame
dCOM = sqrt(diff(com_x).^2 + diff(com_y).^2);
mean_speed_pxfr = mean(dCOM,'omitnan');

fprintf('Centre-of-mass displacement (mean): %.3f px/frame (%.3f px/ms)\n', ...
    mean_speed_pxfr, mean_speed_pxfr/ms_per_fr);

figure('Name','Propagation — CoM Trajectory','Color','w','Position',[100 100 800 400]);
subplot(1,2,1);
plot(com_x, com_y, 'o-k','MarkerFaceColor','r','LineWidth',1.2);
xlabel('X (px)'); ylabel('Y (px)');
title('Centre-of-Mass Trajectory');
axis equal; grid on; set(gca,'YDir','reverse');

subplot(1,2,2);
t_ax = (0:numel(dCOM)-1)*ms_per_fr;
plot(t_ax, dCOM,'b','LineWidth',1.4); hold on;
yline(mean_speed_pxfr,'--r',sprintf('mean=%.2f px/frame',mean_speed_pxfr));
xlabel('Time after stimulus (ms)'); ylabel('CoM displacement (px/frame)');
title('Propagation Speed'); grid on; axis tight;
sgtitle('Wave Propagation (Centre-of-Mass method)');

%% Montage

start_f     = stim_fr - 8;
end_f       = stim_fr + 23;
num_mont_fr = end_f - start_f + 1;

figure('Name','Neural Propagation Montage','Color','w','Position',[10 10 1600 900]);
try, cmap=feval(CFG.colormap,256); catch, cmap=jet(256); end

for k = 1:num_mont_fr
    fi   = start_f+k-1;
    img  = M_smooth(:,:,fi);
    if fi < stim_fr, img = -img; end
    img_d = img; img_d(img<floor_val) = floor_val;

    subplot(4,8,k);
    if ~isempty(structural_rgb)
        image(structural_rgb); hold on;
        h_ov = imagesc(img_d);
        a = ((img_d-floor_val)/(sat_val-floor_val)).^1.5;
        a(a<0)=0; a(a>1)=1;
        set(h_ov,'AlphaData',a);
        colormap(gca,cmap); caxis([floor_val sat_val]); hold off;
    else
        imagesc(img_d); colormap(gca,cmap); caxis([floor_val sat_val]);
    end
    axis image off;
    if fi==stim_fr
        title('STIM','Color','r','FontWeight','bold');
    else
        title(sprintf('%.0f ms',(fi-stim_fr)*ms_per_fr),'Color','k');
    end
end
h=colorbar; h.Position=[0.92 0.1 0.02 0.8];
sgtitle(sprintf('Neural Propagation  |  σ=%.1f  |  ICs: %s  |  sign=%+d', ...
    SIGMA, mat2str(selected_ICs), sign_ass));

%% Global trace with annotations

global_trace = -squeeze(mean(mean(M_smooth,1),2));
time_ms      = (0:T-1)*ms_per_fr;

% Peak detection
[pk_val, pk_fr] = max(global_trace(stim_fr:end));
pk_fr = pk_fr + stim_fr - 1;
pk_ms = (pk_fr - stim_fr)*ms_per_fr;

% Onset (first frame > 10% of peak after stimulus)
onset_thresh = 0.1*pk_val;
post_trace   = global_trace(stim_fr:end);
onset_idx    = find(post_trace > onset_thresh, 1);
onset_ms     = (onset_idx-1)*ms_per_fr;

% Half-width
above_half = post_trace > 0.5*pk_val;
hw_start   = find(above_half,1);
hw_end     = find(above_half,1,'last');
halfwidth_ms = (hw_end - hw_start)*ms_per_fr;

fprintf('\n=== GLOBAL TRACE METRICS ===\n');
fprintf('Baseline mean (pre-stim)  : %.5f\n', mean(global_trace(1:stim_fr-1)));
fprintf('Baseline std  (pre-stim)  : %.5f\n', std(global_trace(1:stim_fr-1)));
fprintf('Peak dF/F                 : %.5f  at %.1f ms post-stimulus\n', pk_val, pk_ms);
fprintf('Response onset (~10%% peak): %.1f ms\n', onset_ms);
fprintf('FWHM of response          : %.1f ms\n', halfwidth_ms);
fprintf('SNR (peak / baseline std) : %.2f  (%.2f dB)\n', ...
    pk_val/std(global_trace(1:stim_fr-1)), ...
    20*log10(pk_val/std(global_trace(1:stim_fr-1))));

figure('Name','Global Trace — Annotated','Color','w','Position',[100 100 900 400]);
plot(time_ms, global_trace,'k','LineWidth',1.3); hold on;
xline(stim_fr*ms_per_fr,'--r','Stim','LabelVerticalAlignment','top','LineWidth',1);
plot(pk_fr*ms_per_fr, pk_val,'rv','MarkerFaceColor','r','MarkerSize',9);
text(pk_fr*ms_per_fr+5, pk_val, sprintf(' Peak\n %.0fms\n %.4f',pk_ms,pk_val),'Color','r','FontSize',8);
yline(onset_thresh,'--b','10% peak');
xlabel('Time (ms)'); ylabel('Mean dF/F');
title(sprintf('Global Trace  |  Peak=%.4f @ %.0fms  |  FWHM=%.0fms  |  SNR=%.1fdB', ...
    pk_val, pk_ms, halfwidth_ms, 20*log10(pk_val/std(global_trace(1:stim_fr-1)))));
grid on; axis tight;

%% Peri-stimulus trace with baseline statistics

fr_pre  = round(CFG.pre_stim_ms  / ms_per_fr);
fr_post = round(CFG.post_stim_ms / ms_per_fr);
idx_s   = stim_fr - fr_pre;
idx_e   = stim_fr + fr_post;

if idx_s>=1 && idx_e<=T
    peri_time  = (-fr_pre:fr_post)*ms_per_fr;
    peri_trace = global_trace(idx_s:idx_e);
    bl_mean    = mean(peri_trace(1:fr_pre));
    bl_std     = std(peri_trace(1:fr_pre));

    figure('Name','Peri-Stimulus Trace','Color','w','Position',[100 100 900 400]);
    fill([peri_time(1) peri_time(fr_pre) peri_time(fr_pre) peri_time(1)], ...
        [min(peri_trace)-0.001 min(peri_trace)-0.001 max(peri_trace)+0.001 max(peri_trace)+0.001], ...
        [0.95 0.95 0.85],'EdgeColor','none');
    hold on;
    plot(peri_time, peri_trace,'b','LineWidth',1.6);
    yline(bl_mean,'--k','Baseline mean','LabelVerticalAlignment','bottom');
    yline(bl_mean+2*bl_std,'--','2σ','Color',[0.5 0.5 0.5]);
    xline(0,'--r','Stimulus','LabelVerticalAlignment','top','LineWidth',1.2);
    xlabel('Time relative to stimulus (ms)'); ylabel('Mean dF/F');
    title(sprintf('Peri-Stimulus  |  BL mean=%.4f  BL std=%.4f  |  ±%d / +%d ms', ...
        bl_mean, bl_std, CFG.pre_stim_ms, CFG.post_stim_ms));
    grid on; axis tight;

    fprintf('\n=== PERI-STIMULUS BASELINE ===\n');
    fprintf('Pre-stimulus baseline mean : %.5f\n', bl_mean);
    fprintf('Pre-stimulus baseline std  : %.5f\n', bl_std);
    fprintf('2σ threshold               : %.5f\n', bl_mean+2*bl_std);
else
    warning('Peri-stimulus window exceeds recording limits.');
end

%% Mean projection comparison: kept vs removed signal

figure('Name','Signal vs Removed','Color','w','Position',[100 100 1100 380]);
subplot(1,4,1);
mf=mean(full_movie,3);
imagesc(mf,[prctile(mf(:),1) prctile(mf(:),99)]); axis image off; colormap jet; colorbar;
title('Full reconstruction');

subplot(1,4,2);
ms2=mean(reconstructed_movie,3);
imagesc(ms2,[prctile(ms2(:),1) prctile(ms2(:),99)]); axis image off; colormap jet; colorbar;
title(sprintf('Kept ICs (%.1f%% var)',var_pct));

subplot(1,4,3);
mn=mean(noise_movie,3);
imagesc(mn,[prctile(mn(:),1) prctile(mn(:),99)]); axis image off; colormap jet; colorbar;
title(sprintf('Removed ICs (%.1f%% var)',noise_pct));

subplot(1,4,4);
imagesc(corr_map,[0 1]); axis image off; colormap(gca,parula); colorbar;
title(sprintf('Pixel corr map\nmean=%.3f',mean_corr));
sgtitle('Reconstruction Decomposition');

%% ROI trace comparison (centre ROI)

roi_r = round(H/2)-10:round(H/2)+10;
roi_c = round(W/2)-10:round(W/2)+10;
tr_full  = squeeze(mean(mean(full_movie(roi_r,roi_c,:),1),2));
tr_recon = squeeze(mean(mean(reconstructed_movie(roi_r,roi_c,:),1),2));
tr_noise = squeeze(mean(mean(noise_movie(roi_r,roi_c,:),1),2));

roi_corr = corrcoef(tr_full, tr_recon); roi_corr = roi_corr(1,2);

figure('Name','Centre ROI Temporal Comparison','Color','w','Position',[100 100 900 500]);
subplot(3,1,1);
plot(time_ms,tr_full,'k','LineWidth',1.2);
xline(stim_fr*ms_per_fr,'--r'); axis tight; box off;
ylabel('dF/F'); title(sprintf('Full reconstruction  (centre ROI %dx%d px)',numel(roi_r),numel(roi_c)));

subplot(3,1,2);
plot(time_ms,tr_recon,'b','LineWidth',1.2);
xline(stim_fr*ms_per_fr,'--r'); axis tight; box off;
ylabel('dF/F'); title(sprintf('Kept ICs  |  r=%.4f vs full',roi_corr));

subplot(3,1,3);
plot(time_ms,tr_noise,'Color',[0.7 0.3 0.3],'LineWidth',1.2);
xline(stim_fr*ms_per_fr,'--r'); axis tight; box off;
xlabel('Time (ms)'); ylabel('dF/F'); title('Removed signal');
sgtitle('ROI Temporal Dynamics');

%% =========================================================================
%  SAVE
% =========================================================================

if ~exist('data','dir'), mkdir('data'); end

outfile = sprintf('data/reconstructed_ICs_%s.mat', CFG.recon_suffix);
save(outfile,'reconstructed_movie','selected_ICs','excluded_ICs', ...
    'H','W','T','Fs','var_pct','noise_pct','mean_corr','nrmse','sign_ass','CFG','src');
fprintf('\nSaved reconstruction → %s\n', outfile);

trace_data.global_trace   = global_trace;
trace_data.time_axis_ms   = time_ms;
trace_data.sampling_rate  = orig_sr;
trace_data.stimulus_frame = stim_fr;
trace_data.selected_ICs   = selected_ICs;
trace_data.excluded_ICs   = excluded_ICs;
trace_data.var_pct        = var_pct;
trace_data.peak_val       = pk_val;
trace_data.peak_ms        = pk_ms;
trace_data.onset_ms       = onset_ms;
trace_data.halfwidth_ms   = halfwidth_ms;
trace_data.mean_corr      = mean_corr;
trace_data.nrmse          = nrmse;
trace_data.processing     = struct('sigma',SIGMA,'floor',FLOOR_SENS, ...
    'sat_pct',SAT_PCT,'sign_ass',sign_ass,'baseline_range',CFG.baseline_range);
trace_data.source_decomp  = CFG.decomp_file;

out_trace = sprintf('data/global_trace_%s.mat', CFG.trace_suffix);
save(out_trace,'trace_data');
fprintf('Saved trace     → %s\n', out_trace);

fprintf('\n==============================================\n');
fprintf(' STAGE B COMPLETE\n');
fprintf(' Selected ICs  : %s\n', mat2str(selected_ICs));
fprintf(' Var explained : %.2f%%\n', var_pct);
fprintf(' Peak dF/F     : %.5f @ %.0f ms\n', pk_val, pk_ms);
fprintf(' Response onset: %.0f ms\n', onset_ms);
fprintf(' FWHM          : %.0f ms\n', halfwidth_ms);
fprintf(' Pixel corr    : %.4f\n', mean_corr);
fprintf(' nRMSE         : %.4f\n', nrmse);
fprintf('==============================================\n');