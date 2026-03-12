%% pipeline_A_decomposition.m
% Stage 1: Trial Averaging → PCA → ICA
% Produces detailed metrics and figures for thesis documentation.
% Publishable to PDF — no interactive prompts.
%
%   publish('pipeline_A_decomposition.m', 'pdf')

clc; clear; close all;

%% =========================================================================
%                        *** CONFIGURATION ***
% =========================================================================

CFG.h5_files = {
    'data/motion_compensated/led_E0B0_vsd_corrected.h5',
    'data/motion_compensated/led_E0B1_vsd_corrected.h5',
};
CFG.output_h5      = 'data/preprocessing/led_averaged.h5';
CFG.dataset_in     = '/functional';
CFG.dataset_out    = '/functional_dff';

CFG.p.Bin         = 1;
CFG.p.Sigma       = 1;
CFG.p.MedianWin   = 3;
CFG.p.BaselineIdx = 38:100;

CFG.sampling_rate  = 500;   % raw acquisition rate (Hz)
CFG.num_components = 7;
CFG.ica_seed       = 42;

CFG.decomp_save    = 'data/ica_decomposition.mat';

% =========================================================================
%                        END OF CONFIGURATION
% =========================================================================

%% =========================================================================
%  PIPELINE PARAMETERS SUMMARY
%  (printed into PDF for methods section reference)
% =========================================================================

fprintf('=== PIPELINE A — PARAMETER SUMMARY ===\n');
fprintf('Date/Time         : %s\n', datestr(now));
fprintf('Number of trials  : %d\n', numel(CFG.h5_files));
fprintf('Binning factor    : %d\n', CFG.p.Bin);
fprintf('Spatial sigma (avg): %.1f px\n', CFG.p.Sigma);
fprintf('Median filter win : %d px\n', CFG.p.MedianWin);
fprintf('Baseline frames   : %d–%d\n', CFG.p.BaselineIdx(1), CFG.p.BaselineIdx(end));
fprintf('Acquisition rate  : %d Hz  →  effective %.1f Hz (interleaved)\n', ...
    CFG.sampling_rate, CFG.sampling_rate/2);
fprintf('ICA components    : %d\n', CFG.num_components);
fprintf('ICA random seed   : %d\n', CFG.ica_seed);
fprintf('Output H5         : %s\n', CFG.output_h5);
fprintf('Decomp save       : %s\n', CFG.decomp_save);
fprintf('\nInput files:\n');
for i = 1:numel(CFG.h5_files)
    [~,n,e] = fileparts(CFG.h5_files{i});
    fprintf('  %d. %s%s\n', i, n, e);
end

%% =========================================================================
%  STAGE 1 — Trial Averaging
% =========================================================================

p    = CFG.p;
Fs   = CFG.sampling_rate / 2;
n_ok = 0;
sum_dff = 0;

% Per-trial metrics storage
trial_metrics = struct();

for i = 1:numel(CFG.h5_files)
    fname = CFG.h5_files{i};
    fprintf('\n--- Trial %d/%d: %s ---\n', i, numel(CFG.h5_files), fname);
    try
        F = double(h5read(fname, CFG.dataset_in));
        [H, W, T] = size(F);

        pre = p.BaselineIdx(p.BaselineIdx >= 1 & p.BaselineIdx <= T);
        F0  = mean(F(:,:,pre), 3);
        F0(F0 == 0) = eps;
        dff = (F - F0) ./ F0;

        nOut = floor(T / p.Bin);
        dff  = squeeze(mean(reshape(dff(:,:,1:nOut*p.Bin), H, W, p.Bin, nOut), 3));

        if p.MedianWin >= 3 && mod(p.MedianWin,2)==1
            for t = 1:nOut
                fr = dff(:,:,t); nm = isnan(fr); fr(nm)=0;
                fr = medfilt2(fr,[p.MedianWin p.MedianWin],'symmetric');
                fr(nm) = NaN; dff(:,:,t) = fr;
            end
        end
        if p.Sigma > 0
            fsz = max(3, 2*ceil(3*p.Sigma)+1);
            for t = 1:nOut
                dff(:,:,t) = imgaussfilt(dff(:,:,t), p.Sigma, 'FilterSize', fsz);
            end
        end

        % --- Per-trial metrics ---
        trial_metrics(i).filename   = fname;
        trial_metrics(i).status     = 'OK';
        trial_metrics(i).H          = H;
        trial_metrics(i).W          = W;
        trial_metrics(i).T_raw      = T;
        trial_metrics(i).T_binned   = nOut;
        trial_metrics(i).F0_mean    = mean(F0(:));
        trial_metrics(i).F0_std     = std(F0(:));
        trial_metrics(i).F0_cv      = std(F0(:)) / mean(F0(:)); % coefficient of variation
        trial_metrics(i).dff_mean   = mean(dff(:), 'omitnan');
        trial_metrics(i).dff_std    = std(dff(:), 'omitnan');
        trial_metrics(i).dff_max    = max(dff(:));
        trial_metrics(i).dff_min    = min(dff(:));
        trial_metrics(i).snr_db     = 20*log10(max(abs(dff(:))) / std(dff(:),'omitnan'));

        fprintf('  Dimensions : %d × %d px, %d raw frames → %d binned\n', H,W,T,nOut);
        fprintf('  F0 mean/std: %.4f / %.4f  (CV=%.3f)\n', ...
            trial_metrics(i).F0_mean, trial_metrics(i).F0_std, trial_metrics(i).F0_cv);
        fprintf('  dF/F range : [%.4f, %.4f]  std=%.4f\n', ...
            trial_metrics(i).dff_min, trial_metrics(i).dff_max, trial_metrics(i).dff_std);
        fprintf('  SNR        : %.2f dB\n', trial_metrics(i).snr_db);

        if n_ok == 0, sum_dff = zeros(size(dff),'double'); end
        sum_dff = sum_dff + dff;
        n_ok    = n_ok + 1;
    catch ME
        warning('Skipping trial %d: %s', i, ME.message);
        trial_metrics(i).filename = fname;
        trial_metrics(i).status   = ['FAILED: ' ME.message];
    end
end

assert(n_ok > 0, 'No trials processed successfully.');
avg_dff = sum_dff / n_ok;
[H, W, T] = size(avg_dff);

%% Trial averaging summary table

fprintf('\n=== TRIAL AVERAGING SUMMARY ===\n');
fprintf('%-5s %-40s %-8s %-8s %-8s %-8s\n', ...
    'Trial','File','F0 mean','dF/F std','SNR(dB)','Status');
fprintf('%s\n', repmat('-',1,80));
for i = 1:numel(CFG.h5_files)
    [~,n,e] = fileparts(trial_metrics(i).filename);
    if strcmp(trial_metrics(i).status,'OK')
        fprintf('%-5d %-40s %-8.4f %-8.4f %-8.2f %-8s\n', i, [n e], ...
            trial_metrics(i).F0_mean, trial_metrics(i).dff_std, ...
            trial_metrics(i).snr_db, trial_metrics(i).status);
    else
        fprintf('%-5d %-40s %-8s %-8s %-8s %-8s\n', i, [n e], ...
            '—','—','—', trial_metrics(i).status);
    end
end
fprintf('\nTrials included in average: %d / %d\n', n_ok, numel(CFG.h5_files));
fprintf('Averaged movie size       : %d × %d px × %d frames\n', H, W, T);
fprintf('Recording duration        : %.3f s @ %.1f Hz\n', T/Fs, Fs);

%% Trial-to-trial variability figure

if n_ok > 1
    figure('Name','Trial-to-Trial Variability','Color','w','Position',[50 50 1000 400]);

    % Global mean trace per trial
    subplot(1,2,1); hold on;
    colors = lines(n_ok);
    ok_idx = 0;
    for i = 1:numel(CFG.h5_files)
        if strcmp(trial_metrics(i).status,'OK')
            ok_idx = ok_idx + 1;
            % re-load just the global mean (already computed via mean of dff)
            % approximate: show SNR and F0 CV as bar plots instead
        end
    end

    snr_vals = arrayfun(@(x) x.snr_db,  trial_metrics(strcmp({trial_metrics.status},'OK')));
    cv_vals  = arrayfun(@(x) x.F0_cv,   trial_metrics(strcmp({trial_metrics.status},'OK')));
    bar(snr_vals, 'FaceColor',[0.3 0.6 0.9]);
    xlabel('Trial #'); ylabel('SNR (dB)');
    title('Per-Trial SNR'); grid on;

    subplot(1,2,2);
    bar(cv_vals, 'FaceColor',[0.9 0.5 0.3]);
    xlabel('Trial #'); ylabel('Coefficient of Variation');
    title('F_0 Spatial Homogeneity (CV)'); grid on;

    sgtitle('Trial Quality Metrics');
end

%% Averaged movie baseline statistics

fprintf('\n=== AVERAGED dF/F STATISTICS ===\n');
baseline_frames = avg_dff(:,:,p.BaselineIdx(p.BaselineIdx<=T));
post_frames     = avg_dff(:,:,round(T*0.6):end);

fprintf('Baseline period  [frames %d-%d]:\n', p.BaselineIdx(1), p.BaselineIdx(end));
fprintf('  Mean dF/F : %.5f\n', mean(baseline_frames(:),'omitnan'));
fprintf('  Std  dF/F : %.5f\n', std(baseline_frames(:),'omitnan'));
fprintf('Post-stimulus period [frames %d-%d]:\n', round(T*0.6), T);
fprintf('  Mean dF/F : %.5f\n', mean(post_frames(:),'omitnan'));
fprintf('  Std  dF/F : %.5f\n', std(post_frames(:),'omitnan'));
fprintf('  Peak dF/F : %.5f\n', max(post_frames(:)));

% Save H5
if exist(CFG.output_h5,'file'), delete(CFG.output_h5); end
h5create(CFG.output_h5, CFG.dataset_out, size(avg_dff), 'DataType','double');
h5write( CFG.output_h5, CFG.dataset_out, avg_dff);
fprintf('\nSaved averaged movie → %s\n', CFG.output_h5);
try
    sd = h5read(CFG.h5_files{1},'/structural');
    h5create(CFG.output_h5,'/structural',size(sd),'DataType','double');
    h5write( CFG.output_h5,'/structural',sd);
    fprintf('Copied structural data.\n');
catch, warning('Could not copy structural data.'); end

%% Averaged dF/F spatial map (mean projection)

figure('Name','Averaged dF/F — Spatial Summary','Color','w','Position',[50 50 1200 400]);
subplot(1,3,1);
m = mean(avg_dff,3);
imagesc(m,[prctile(m(:),1) prctile(m(:),99)]); axis image off; colormap jet; colorbar;
title(sprintf('Mean dF/F  (all %d frames)',T));

subplot(1,3,2);
m2 = std(avg_dff,[],3);
imagesc(m2,[prctile(m2(:),1) prctile(m2(:),99)]); axis image off; colormap jet; colorbar;
title('Std dF/F across time');

subplot(1,3,3);
snr_map = mean(avg_dff,3) ./ (std(avg_dff,[],3) + eps);
imagesc(snr_map,[prctile(snr_map(:),2) prctile(snr_map(:),98)]); axis image off; colormap jet; colorbar;
title('Spatial SNR map (mean/std)');
sgtitle(sprintf('Averaged dF/F  |  %d trials  |  %dx%d px  |  %d frames',n_ok,H,W,T));

%% =========================================================================
%  STAGE 2 — PCA
% =========================================================================

X = reshape(avg_dff, H*W, T).';
X(isnan(X)) = 0;

fprintf('\nSpatial smoothing (sigma=2) before PCA...\n');
tmp = reshape(X.',H,W,T);
for t = 1:T, tmp(:,:,t) = imgaussfilt(tmp(:,:,t),2); end
X = reshape(tmp,H*W,T).';

fprintf('Running PCA...\n');
[pca_coeff_full, pca_score_full, pca_latent, ~, explained_full] = ...
    pca(X,'Algorithm','svd','Economy','on');
Z = size(pca_score_full,2);
n = CFG.num_components;

%% PCA metrics

fprintf('\n=== PCA METRICS ===\n');
fprintf('Total PCs computed : %d\n', Z);
fprintf('PCs retained       : %d\n', n);
fprintf('Variance explained by retained PCs: %.2f%%\n', sum(explained_full(1:n)));
fprintf('Variance in noise floor (remaining %d PCs): %.2f%%\n', Z-n, sum(explained_full(n+1:end)));
fprintf('\nPer-PC variance:\n');
fprintf('%-6s %-12s %-18s\n','PC #','Var expl (%)','Cumulative (%)');
fprintf('%s\n', repmat('-',1,40));
cumvar = 0;
for k = 1:min(n+3, Z)
    cumvar = cumvar + explained_full(k);
    tag = '';
    if k == n, tag = '  ← cutoff'; end
    fprintf('%-6d %-12.3f %-18.3f%s\n', k, explained_full(k), cumvar, tag);
end

%% Scree plot

figure('Name','PCA Scree Plot','Color','w','Position',[50 50 900 400]);
subplot(1,2,1);
bar(1:min(20,Z), explained_full(1:min(20,Z)), 'FaceColor',[0.3 0.5 0.8]);
xline(n+0.5,'--r','LineWidth',1.5);
xlabel('PC #'); ylabel('Variance explained (%)');
title('Individual Variance per PC'); grid on;
text(n+0.7, explained_full(1)*0.9, sprintf('Cutoff: %d PCs',n), 'Color','r');

subplot(1,2,2);
plot(1:min(30,Z), cumsum(explained_full(1:min(30,Z))), 'o-k','LineWidth',1.5,'MarkerFaceColor','k');
xline(n,'--r'); yline(sum(explained_full(1:n)),'--b');
xlabel('Number of PCs'); ylabel('Cumulative variance (%)');
title(sprintf('Cumulative: %d PCs = %.1f%%', n, sum(explained_full(1:n))));
grid on;
sgtitle('PCA Scree Analysis');

%% Top PC spatial maps and timecourses

figure('Name','Top PCA Components','Color','w','Position',[50 50 1100 700]);
for k = 1:n
    subplot(n, 3, (k-1)*3 + 1);
    pc_map = reshape(pca_coeff_full(:,k), H, W);
    imagesc(pc_map,[prctile(pc_map(:),2) prctile(pc_map(:),98)]);
    axis image off; colormap jet;
    title(sprintf('PC #%d  (%.2f%%)',k,explained_full(k)));

    subplot(n, 3, (k-1)*3 + 2);
    plot((1:T)/Fs, pca_score_full(:,k),'k','LineWidth',0.8);
    axis tight; box off; xlabel('Time (s)');
    title('Score (time course)');

    subplot(n, 3, (k-1)*3 + 3);
    L = T; f_ax = Fs*(0:(L/2))/L;
    Y = fft(pca_score_full(:,k));
    P2 = abs(Y/L); P1 = P2(1:L/2+1); P1(2:end-1)=2*P1(2:end-1);
    plot(f_ax, P1,'b','LineWidth',1.2); xlim([0 15]); box off;
    xlabel('Freq (Hz)'); title('Power spectrum');
end
sgtitle('Top PCA Components (spatial map | timecourse | PSD)');

pca_tc   = pca_score_full(:, 1:n);
pca_maps = pca_coeff_full(:, 1:n);

%% =========================================================================
%  STAGE 3 — ICA
% =========================================================================

rng(CFG.ica_seed);
fprintf('\nRunning FastICA (seed=%d, approach=symm, g=tanh)...\n', CFG.ica_seed);
tic;
[icasig, A, W_ica] = fastica(pca_maps', ...
    'verbose',  'off', ...
    'numOfIC',  n, ...
    'approach', 'symm', ...
    'g',        'tanh');
ica_time = toc;
fprintf('FastICA converged in %.2f s\n', ica_time);

ica_maps_flat   = icasig.';
ica_timecourses = pca_tc * A;
num_ICs         = size(ica_maps_flat,2);
ica_maps        = reshape(ica_maps_flat, H, W, num_ICs);

%% ICA metrics + sign correction

L  = T;
f  = Fs*(0:(L/2))/L;
stats = struct();

for k = 1:num_ICs
    mp = ica_maps_flat(:,k);
    tc = ica_timecourses(:,k);

    % Sign correction via spatial skewness
    if skewness(mp) < 0
        mp = -mp; tc = -tc;
        ica_maps_flat(:,k)   = mp;
        ica_timecourses(:,k) = tc;
        ica_maps(:,:,k)      = -ica_maps(:,:,k);
    end

    % Spatial metrics
    stats(k).sp_mean    = mean(mp);
    stats(k).sp_std     = std(mp);
    stats(k).sp_skew    = skewness(mp);
    stats(k).sp_kurt    = kurtosis(mp);
    stats(k).sp_gini    = gini_coeff(abs(mp));   % sparsity measure
    stats(k).activation_pct = 100*mean(mp > prctile(mp,95)); % % pixels in top 5%

    % Temporal metrics
    tc_z = (tc - mean(tc)) / std(tc);
    stats(k).tc_mean    = mean(tc);
    stats(k).tc_std     = std(tc);
    stats(k).tc_maxz    = max(abs(tc_z));
    stats(k).tc_skew    = skewness(tc);
    stats(k).tc_kurt    = kurtosis(tc);
    % Autocorrelation at lag-1 (temporal smoothness)
    ac = xcorr(tc, 1, 'normalized');
    stats(k).tc_autocorr = ac(2);

    % Spectral metrics
    Y = fft(tc); P2 = abs(Y/L); P1 = P2(1:L/2+1); P1(2:end-1)=2*P1(2:end-1);
    [~,idx] = max(P1(2:end));
    stats(k).dom_freq   = f(idx+1);
    stats(k).P1         = P1;

    % Spectral band power (% of total)
    total_pow = sum(P1.^2);
    stats(k).pwr_0_5hz  = 100*sum(P1(f<=5).^2)  / total_pow;
    stats(k).pwr_5_15hz = 100*sum(P1(f>5 & f<=15).^2) / total_pow;
    stats(k).pwr_15hz   = 100*sum(P1(f>15).^2)  / total_pow;
end

%% ICA metrics summary table

fprintf('\n=== ICA COMPONENT METRICS ===\n');
fprintf('%-5s %-10s %-10s %-10s %-10s %-10s %-10s %-12s %-10s\n', ...
    'IC','DomFreq','SpKurt','SpSkew','SpGini','TcMaxZ','TcAutocr','BandPwr<5Hz','Status');
fprintf('%s\n', repmat('-',1,90));
for k = 1:num_ICs
    % Heuristic classification for thesis reference
    tag = classify_IC(stats(k));
    fprintf('%-5d %-10.2f %-10.2f %-10.2f %-10.3f %-10.2f %-10.3f %-12.1f %s\n', ...
        k, stats(k).dom_freq, stats(k).sp_kurt, stats(k).sp_skew, ...
        stats(k).sp_gini, stats(k).tc_maxz, stats(k).tc_autocorr, ...
        stats(k).pwr_0_5hz, tag);
end
fprintf('\nNote: Classification is heuristic. Visual inspection required.\n');
fprintf('Abbreviations: sp=spatial, tc=temporal, kurt=kurtosis, autocorr=lag-1 autocorrelation\n');

%% ICA component inspection figures

comps_per_fig = 4;
for fig_idx = 1:ceil(num_ICs/comps_per_fig)
    figure('Name',sprintf('ICA Components (batch %d)',fig_idx),'Color','w','Position',[50 50 1100 850]);
    s = (fig_idx-1)*comps_per_fig+1;
    e = min(s+comps_per_fig-1, num_ICs);
    for ki = 1:(e-s+1)
        k = s+ki-1;

        % Spatial map
        subplot(comps_per_fig, 4, (ki-1)*4+1);
        m = ica_maps(:,:,k);
        imagesc(m,[prctile(m(:),2) prctile(m(:),98)]);
        axis image off; colormap jet;
        title(sprintf('IC #%d | Kurt=%.1f | Gini=%.2f', k, stats(k).sp_kurt, stats(k).sp_gini));

        % Time course
        subplot(comps_per_fig, 4, (ki-1)*4+2);
        plot((1:T)/Fs, ica_timecourses(:,k),'k','LineWidth',0.8); axis tight; box off;
        xlabel('Time (s)'); ylabel('a.u.');
        title(sprintf('MaxZ=%.1f | AC=%.2f', stats(k).tc_maxz, stats(k).tc_autocorr));

        % Power spectrum
        subplot(comps_per_fig, 4, (ki-1)*4+3);
        plot(f, stats(k).P1,'r','LineWidth',1.5); xlim([0 20]); box off;
        xlabel('Freq (Hz)'); ylabel('Magnitude');
        title(sprintf('Dom=%.2fHz | <5Hz: %.0f%%', stats(k).dom_freq, stats(k).pwr_0_5hz));
        xline(5,'--b','LineWidth',0.8);

        % Spatial histogram (for kurtosis interpretation)
        subplot(comps_per_fig, 4, (ki-1)*4+4);
        histogram(m(:), 50, 'FaceColor',[0.4 0.6 0.8], 'EdgeColor','none');
        xlabel('Pixel value'); ylabel('Count');
        title(sprintf('Skew=%.2f', stats(k).sp_skew));
        box off;
    end
    sgtitle(sprintf('ICA Batch %d  |  seed=%d  |  %d PCs', fig_idx, CFG.ica_seed, n));
end

%% ICA mixing matrix heatmap (A matrix — how PCs combine into ICs)

% Build diverging colormap inline (avoids publish function-hoisting issue)
h256 = 128;
rb_r = [linspace(0.2,1,h256), ones(1,h256)]';
rb_g = [linspace(0.2,1,h256), linspace(1,0.2,h256)]';
rb_b = [ones(1,h256), linspace(1,0.2,h256)]';
redblue256 = [rb_r, rb_g, rb_b];

figure('Name','ICA Mixing Matrix','Color','w','Position',[100 100 600 400]);
imagesc(A);
colormap(redblue256); colorbar;
clim_val = max(abs(A(:)));
caxis([-clim_val clim_val]);
xlabel('IC #'); ylabel('PC #');
xticks(1:num_ICs); yticks(1:n);
title(sprintf('ICA Mixing Matrix  A  (%d PCs × %d ICs)', n, num_ICs));
for r = 1:n
    for c = 1:num_ICs
        text(c,r,sprintf('%.2f',A(r,c)),'HorizontalAlignment','center','FontSize',7);
    end
end

%% Global PSD across top PCs (data quality reference)

figure('Name','Global PSD — Top PCs','Color','w','Position',[100 100 700 350]);
P1_global = zeros(L/2+1,1);
for k = 1:min(Z,10)
    Y = fft(pca_score_full(:,k)); P2=abs(Y/L);
    P1t=P2(1:L/2+1); P1t(2:end-1)=2*P1t(2:end-1);
    P1_global = P1_global + P1t;
end
plot(f, P1_global,'k','LineWidth',1.5); grid on;
xlabel('Frequency (Hz)'); ylabel('Summed magnitude (top 10 PCs)');
title('Global Power Spectral Density'); xlim([0 Fs]);
xline(5,'--b','5 Hz'); xline(15,'--r','15 Hz');

%% =========================================================================
%  SAVE DECOMPOSITION
% =========================================================================

if ~isempty(fileparts(CFG.decomp_save)) && ~exist(fileparts(CFG.decomp_save),'dir')
    mkdir(fileparts(CFG.decomp_save));
end

save(CFG.decomp_save, ...
    'ica_maps','ica_maps_flat','ica_timecourses', ...
    'stats','f','L', ...
    'H','W','T','Fs','num_ICs', ...
    'pca_score_full','pca_coeff_full','pca_latent','explained_full', ...
    'trial_metrics','A','W_ica', ...
    'CFG');

fprintf('\n✓ Decomposition saved → %s\n', CFG.decomp_save);
fprintf('\n==============================================\n');
fprintf(' STAGE A COMPLETE\n');
fprintf(' Inspect component figures, note IC numbers\n');
fprintf(' to exclude, then configure pipeline_B.\n');
fprintf('==============================================\n');

%% =========================================================================
%  LOCAL HELPER FUNCTIONS
% =========================================================================

function g = gini_coeff(x)
% Gini coefficient — 0=uniform (not sparse), 1=fully sparse
x = sort(x(:)); n = numel(x);
g = (2*sum((1:n)'.*x) / (n*sum(x))) - (n+1)/n;
g = max(0,min(1,g));
end

function tag = classify_IC(s)
% Heuristic IC label for thesis reference — adjust thresholds as needed
if s.dom_freq < 2 && s.pwr_0_5hz > 60
    tag = '[low-freq / slow drift]';
elseif s.dom_freq > 10 && s.pwr_15hz > 20
    tag = '[high-freq noise]';
elseif s.tc_autocorr > 0.9 && s.sp_kurt < 4
    tag = '[smooth / motion?]';
elseif s.sp_kurt > 10 && s.sp_gini > 0.5
    tag = '[focal / candidate signal]';
else
    tag = '[review]';
end
end