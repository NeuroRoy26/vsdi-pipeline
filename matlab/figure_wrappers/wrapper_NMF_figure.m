%% pipeline_A_NMF.m
% NMF decomposition of averaged VSD dF/F data.
% Equivalent to pipeline_A_decomposition.m but uses Non-Negative Matrix
% Factorization instead of PCA+ICA.
%
% Advantages of NMF for VSD data (cited in script for thesis):
%   - Parts-based decomposition: components are strictly additive
%   - No blind polarity inversion (all maps non-negative)
%   - Depolarisation peaks remain positive (consistent with Morales-Botello
%     et al. 1999; Grinvald & Hildesheim 2004, Nature)
%
% Produces detailed metrics + figures for thesis documentation.
% Publishable to PDF — no interactive prompts.
%
%   publish('pipeline_A_NMF.m', 'pdf')
%
% After publishing: inspect component figures, note which components to
% keep/exclude, then set selected_components in pipeline_B_reconstruct.m

clc; clear; close all;

%% =========================================================================
%                        *** CONFIGURATION ***
% =========================================================================

CFG.input_file     = 'data/preprocessing/led_averaged.h5';
CFG.dataset_name   = '/functional_dff';
CFG.sampling_rate  = 500;      % raw acquisition rate Hz (interleaved → 250 Hz effective)

% NMF parameters
CFG.num_components = 8;
CFG.bin_factor     = 2;        % spatial downscale before NMF (2 = 4× faster, restores after)
CFG.smooth_sigma   = 2;        % Gaussian sigma applied to each frame before NMF
CFG.nmf_replicates = 3;        % random restarts — best solution kept
CFG.nmf_algorithm  = 'als';    % 'als' (alternating least squares) or 'mult'
CFG.nmf_seed       = 42;       % rng seed for reproducibility

% Output
CFG.output_dir  = 'data/batch_output500';
CFG.decomp_save = 'data/nmf_decomposition.mat';

% =========================================================================
%                        END OF CONFIGURATION
% =========================================================================

if ~exist(CFG.output_dir,  'dir'), mkdir(CFG.output_dir);  end
if ~exist(fileparts(CFG.decomp_save), 'dir') && ~isempty(fileparts(CFG.decomp_save))
    mkdir(fileparts(CFG.decomp_save));
end
[~, base_name, ~] = fileparts(CFG.input_file);
Fs = CFG.sampling_rate / 2;   % effective rate after interleaving

%% =========================================================================
%  PARAMETER SUMMARY
% =========================================================================

fprintf('=== PIPELINE A (NMF) — PARAMETER SUMMARY ===\n');
fprintf('Date/Time          : %s\n', datestr(now));
fprintf('Input file         : %s\n', CFG.input_file);
fprintf('Dataset            : %s\n', CFG.dataset_name);
fprintf('Acquisition rate   : %d Hz  →  %.1f Hz effective (interleaved)\n', ...
    CFG.sampling_rate, Fs);
fprintf('NMF components     : %d\n',   CFG.num_components);
fprintf('Spatial bin factor : %d  (%.0f%% size reduction)\n', ...
    CFG.bin_factor, (1 - 1/CFG.bin_factor^2)*100);
fprintf('Smooth sigma       : %.1f px\n', CFG.smooth_sigma);
fprintf('NMF replicates     : %d\n',   CFG.nmf_replicates);
fprintf('NMF algorithm      : %s\n',   CFG.nmf_algorithm);
fprintf('RNG seed           : %d\n',   CFG.nmf_seed);
fprintf('Output dir         : %s\n',   CFG.output_dir);
fprintf('Decomp save        : %s\n',   CFG.decomp_save);

%% =========================================================================
%  LOAD DATA
% =========================================================================

fprintf('\n--- Loading data ---\n');
assert(exist(CFG.input_file,'file')==2, 'Input file not found: %s', CFG.input_file);

mov = h5read(CFG.input_file, CFG.dataset_name);
[H, W, T] = size(mov);
fprintf('Loaded: %d × %d px, %d frames (%.2f s @ %.1f Hz)\n', H, W, T, T/Fs, Fs);

% Basic data statistics
fprintf('\n=== RAW DATA STATISTICS ===\n');
fprintf('Global mean dF/F : %.5f\n', mean(mov(:),'omitnan'));
fprintf('Global std  dF/F : %.5f\n', std(mov(:),'omitnan'));
fprintf('Global min  dF/F : %.5f\n', min(mov(:)));
fprintf('Global max  dF/F : %.5f\n', max(mov(:)));
fprintf('NaN pixels       : %d / %d (%.2f%%)\n', ...
    sum(isnan(mov(:))), numel(mov), 100*mean(isnan(mov(:))));

%% Raw data spatial overview

figure('Name','Raw dF/F Spatial Summary','Color','w','Position',[50 50 1200 380]);
subplot(1,3,1);
m = mean(mov,3,'omitnan');
imagesc(m,[prctile(m(:),1) prctile(m(:),99)]); axis image off; colormap jet; colorbar;
title(sprintf('Mean dF/F  (%d frames)',T));

subplot(1,3,2);
s = std(mov,[],3,'omitnan');
imagesc(s,[prctile(s(:),1) prctile(s(:),99)]); axis image off; colormap jet; colorbar;
title('Std dF/F across time');

subplot(1,3,3);
snr_map = m ./ (s + eps);
imagesc(snr_map,[prctile(snr_map(:),2) prctile(snr_map(:),98)]); axis image off; colormap jet; colorbar;
title('Spatial SNR map (mean/std)');
sgtitle(sprintf('Input data  |  %d × %d px  |  %d frames  |  %.1f Hz', H, W, T, Fs));

%% Global temporal trace

global_raw = squeeze(mean(mean(mov,1,'omitnan'),2,'omitnan'));
time_ms    = (0:T-1) * (1000/Fs);

figure('Name','Global Temporal Trace (raw)','Color','w','Position',[50 50 900 300]);
plot(time_ms, global_raw, 'k', 'LineWidth', 1.2);
xlabel('Time (ms)'); ylabel('Mean dF/F'); title('Global Mean Trace (pre-NMF)');
grid on; axis tight;

%% =========================================================================
%  STAGE 1 — SPATIAL BINNING
% =========================================================================

fprintf('\n--- Spatial binning (factor %d) ---\n', CFG.bin_factor);
tic;
mov_binned = imresize(mov, 1/CFG.bin_factor);
[Hb, Wb, ~] = size(mov_binned);
t_bin = toc;
fprintf('Binned size : %d × %d px  (%.2f s)\n', Hb, Wb, t_bin);
fprintf('Memory reduction : %.1f×\n', (H*W) / (Hb*Wb));

%% =========================================================================
%  STAGE 2 — SPATIAL SMOOTHING
% =========================================================================

fprintf('\nApplying spatial smoothing (sigma=%.1f)...\n', CFG.smooth_sigma);
tic;
for t = 1:T
    mov_binned(:,:,t) = imgaussfilt(mov_binned(:,:,t), CFG.smooth_sigma);
end
fprintf('Smoothing done (%.2f s)\n', toc);

%% =========================================================================
%  STAGE 3 — NMF DATA PREPARATION
% =========================================================================

% Flatten: rows = pixels, cols = time
X = reshape(mov_binned, Hb*Wb, T);
X(isnan(X)) = 0;

% NMF requires non-negative input — shift if needed
min_val = min(X(:));
fprintf('\nData minimum before shift : %.5f\n', min_val);
if min_val < 0
    X_pos = X - min_val;
    fprintf('Shifted by %.5f to make strictly non-negative.\n', min_val);
else
    X_pos = X;
    fprintf('Data already non-negative — no shift required.\n');
end
fprintf('Post-shift range : [%.5f, %.5f]\n', min(X_pos(:)), max(X_pos(:)));

% Frobenius norm of input matrix (reference for reconstruction error)
X_frob = norm(X_pos, 'fro');
fprintf('Input matrix Frobenius norm : %.4f\n', X_frob);

%% =========================================================================
%  STAGE 4 — NMF
% =========================================================================

fprintf('\n--- Running NMF (%s, %d components, %d replicates, seed=%d) ---\n', ...
    CFG.nmf_algorithm, CFG.num_components, CFG.nmf_replicates, CFG.nmf_seed);

rng(CFG.nmf_seed);
opts = statset('UseParallel', false);   % set true if Parallel Computing Toolbox available
tic;
[W_nmf, H_nmf] = nnmf(X_pos, CFG.num_components, ...
    'options',    opts, ...
    'algorithm',  CFG.nmf_algorithm, ...
    'replicates', CFG.nmf_replicates);
t_nmf = toc;

fprintf('NMF converged in %.2f s\n', t_nmf);

% Reshape spatial maps back to binned 2D
nmf_maps_binned = reshape(W_nmf, Hb, Wb, CFG.num_components);

% Upsample spatial maps back to original resolution for display/saving
nmf_maps_full = zeros(H, W, CFG.num_components);
for k = 1:CFG.num_components
    nmf_maps_full(:,:,k) = imresize(nmf_maps_binned(:,:,k), [H W]);
end

%% =========================================================================
%  STAGE 5 — NMF METRICS
% =========================================================================

fprintf('\n=== NMF QUALITY METRICS ===\n');

% Overall reconstruction error
X_recon_full = W_nmf * H_nmf;
resid        = X_pos - X_recon_full;
recon_err    = norm(resid, 'fro');
rel_err      = recon_err / X_frob;
r_squared    = 1 - (recon_err^2 / X_frob^2);

fprintf('Reconstruction error (Frobenius)   : %.4f\n', recon_err);
fprintf('Relative reconstruction error      : %.4f  (%.2f%%)\n', rel_err, rel_err*100);
fprintf('R² (variance explained)            : %.4f  (%.2f%%)\n', r_squared, r_squared*100);

% Per-component metrics
n  = CFG.num_components;
L  = T;
f  = Fs*(0:(L/2))/L;

comp_stats = struct();

for k = 1:n
    % Spatial map (full resolution)
    sp = nmf_maps_full(:,:,k);
    sp_flat = sp(:);

    % Temporal course
    tc = H_nmf(k,:)';

    % Per-component reconstruction contribution
    comp_recon = W_nmf(:,k) * H_nmf(k,:);
    comp_var   = var(comp_recon(:));
    total_var  = var(X_pos(:));
    comp_stats(k).var_pct = 100 * comp_var / total_var;

    % Spatial metrics
    comp_stats(k).sp_mean  = mean(sp_flat);
    comp_stats(k).sp_std   = std(sp_flat);
    comp_stats(k).sp_max   = max(sp_flat);
    comp_stats(k).sp_kurt  = kurtosis(sp_flat);
    comp_stats(k).sp_skew  = skewness(sp_flat);
    comp_stats(k).sp_gini  = gini_coeff(sp_flat);
    comp_stats(k).sp_area_pct = 100*mean(sp_flat > 0.5*max(sp_flat)); % % pixels > 50% peak

    % Temporal metrics
    tc_z = (tc - mean(tc)) / (std(tc) + eps);
    comp_stats(k).tc_mean     = mean(tc);
    comp_stats(k).tc_std      = std(tc);
    comp_stats(k).tc_maxz     = max(abs(tc_z));
    comp_stats(k).tc_skew     = skewness(tc);
    comp_stats(k).tc_kurt     = kurtosis(tc);
    ac = xcorr(tc, 1, 'normalized');
    comp_stats(k).tc_autocorr = ac(2);

    % Spectral metrics
    Y = fft(tc); P2 = abs(Y/L); P1 = P2(1:L/2+1); P1(2:end-1) = 2*P1(2:end-1);
    [~,idx] = max(P1(2:end));
    comp_stats(k).dom_freq    = f(idx+1);
    comp_stats(k).P1          = P1;
    total_pow = sum(P1.^2);
    comp_stats(k).pwr_0_5hz   = 100*sum(P1(f<=5).^2)          / total_pow;
    comp_stats(k).pwr_5_15hz  = 100*sum(P1(f>5  & f<=15).^2)  / total_pow;
    comp_stats(k).pwr_gt15hz  = 100*sum(P1(f>15).^2)           / total_pow;

    % Heuristic classification
    comp_stats(k).tag = classify_nmf(comp_stats(k));
end

%% Per-component summary table

fprintf('\n=== PER-COMPONENT METRICS TABLE ===\n');
fprintf('%-5s %-9s %-9s %-9s %-9s %-9s %-9s %-12s %-25s\n', ...
    'Comp','Var(%)','DomFreq','SpKurt','SpGini','TcMaxZ','TcAC','<5Hz Pwr(%)','Tag');
fprintf('%s\n', repmat('-',1,100));
for k = 1:n
    fprintf('%-5d %-9.2f %-9.2f %-9.2f %-9.3f %-9.2f %-9.3f %-12.1f %s\n', ...
        k, comp_stats(k).var_pct, comp_stats(k).dom_freq, ...
        comp_stats(k).sp_kurt,    comp_stats(k).sp_gini, ...
        comp_stats(k).tc_maxz,    comp_stats(k).tc_autocorr, ...
        comp_stats(k).pwr_0_5hz,  comp_stats(k).tag);
end
fprintf('\nTotal variance explained (sum): %.2f%%\n', sum([comp_stats.var_pct]));
fprintf('Global R²                     : %.4f (%.2f%%)\n', r_squared, r_squared*100);
fprintf('Relative reconstruction error : %.4f (%.2f%%)\n', rel_err, rel_err*100);
fprintf('\nAbbreviations:\n');
fprintf('  Var(%%)   = component variance / total variance\n');
fprintf('  DomFreq  = dominant frequency (Hz)\n');
fprintf('  SpKurt   = spatial kurtosis (>3 = leptokurtic / focal)\n');
fprintf('  SpGini   = spatial Gini coefficient (0=uniform, 1=sparse)\n');
fprintf('  TcMaxZ   = max |z-score| of timecourse\n');
fprintf('  TcAC     = lag-1 autocorrelation (1=smooth, 0=noisy)\n');
fprintf('  <5Hz Pwr = %% spectral power below 5 Hz\n');

%% Variance contribution bar chart

figure('Name','NMF Component Variance Contributions','Color','w','Position',[50 50 800 380]);
var_pcts = [comp_stats.var_pct];
bar(1:n, var_pcts, 'FaceColor',[0.3 0.6 0.85]);
xlabel('Component #'); ylabel('Variance contribution (%)');
title(sprintf('NMF Component Contributions  |  Total R²=%.1f%%  |  Rel.Err=%.3f', ...
    r_squared*100, rel_err));
grid on; axis tight;
for k = 1:n
    text(k, var_pcts(k)+0.1, sprintf('%.1f%%',var_pcts(k)), ...
        'HorizontalAlignment','center','FontSize',8);
end

%% =========================================================================
%  STAGE 6 — COMPONENT INSPECTION FIGURES
% =========================================================================

comps_per_fig = 4;
num_figs = ceil(n / comps_per_fig);

for fig_idx = 1:num_figs
    figure('Name',sprintf('NMF Components (batch %d)',fig_idx),...
        'Color','w','Position',[50 50 1200 900]);
    s_idx = (fig_idx-1)*comps_per_fig + 1;
    e_idx = min(s_idx + comps_per_fig - 1, n);

    for ki = 1:(e_idx - s_idx + 1)
        k = s_idx + ki - 1;

        % --- Spatial map (full resolution) ---
        subplot(comps_per_fig, 4, (ki-1)*4 + 1);
        m = nmf_maps_full(:,:,k);
        imagesc(m, [0 prctile(m(:),99)]);
        axis image off; colormap(gca,'turbo'); colorbar;
        title(sprintf('Comp #%d | Kurt=%.1f | Gini=%.2f | %.1f%%var', ...
            k, comp_stats(k).sp_kurt, comp_stats(k).sp_gini, comp_stats(k).var_pct));

        % --- Timecourse ---
        subplot(comps_per_fig, 4, (ki-1)*4 + 2);
        tc = H_nmf(k,:);
        plot((1:T)/Fs, tc, 'k', 'LineWidth', 0.9);
        axis tight; box off;
        xlabel('Time (s)'); ylabel('Intensity (a.u.)');
        title(sprintf('MaxZ=%.1f | AC=%.2f | Skew=%.2f', ...
            comp_stats(k).tc_maxz, comp_stats(k).tc_autocorr, comp_stats(k).tc_skew));

        % --- Power spectrum ---
        subplot(comps_per_fig, 4, (ki-1)*4 + 3);
        plot(f, comp_stats(k).P1, 'r', 'LineWidth', 1.5);
        xlim([0 min(20, Fs)]); box off;
        xlabel('Freq (Hz)'); ylabel('Magnitude');
        xline(5,'--b','LineWidth',0.8);
        title(sprintf('Dom=%.2fHz | <5Hz: %.0f%%', ...
            comp_stats(k).dom_freq, comp_stats(k).pwr_0_5hz));

        % --- Spatial histogram ---
        subplot(comps_per_fig, 4, (ki-1)*4 + 4);
        histogram(m(:), 60, 'FaceColor',[0.4 0.65 0.8], 'EdgeColor','none');
        xlabel('Pixel value'); ylabel('Count'); box off;
        title(sprintf('%s', comp_stats(k).tag));
    end

    sgtitle(sprintf('NMF Batch %d  |  seed=%d  |  %d components  |  %s algorithm', ...
        fig_idx, CFG.nmf_seed, n, CFG.nmf_algorithm));
end

%% =========================================================================
%  STAGE 7 — RECONSTRUCTION ERROR ANALYSIS
% =========================================================================

fprintf('\n=== RECONSTRUCTION ERROR ANALYSIS ===\n');

% Per-pixel residual RMS map
resid_3d   = reshape(resid, Hb, Wb, T);
resid_rms  = sqrt(mean(resid_3d.^2, 3));
resid_rms_full = imresize(resid_rms, [H W]);

% Cumulative variance captured as components are added
cum_var = zeros(1, n);
for k = 1:n
    X_cum = W_nmf(:,1:k) * H_nmf(1:k,:);
    err_k = norm(X_pos - X_cum, 'fro');
    cum_var(k) = (1 - (err_k/X_frob)^2) * 100;
end

marginal = diff([0, cum_var]);   % prepend 0 so marginal(1) = cum_var(1)

fprintf('%-6s %-20s %-20s\n','Comp','Cumulative R² (%)', 'Marginal R² (%)');
fprintf('%s\n', repmat('-',1,50));
for k = 1:n
    fprintf('%-6d %-20.3f %-20.3f\n', k, cum_var(k), marginal(k));
end

% Cumulative R² plot
figure('Name','NMF Cumulative Variance Explained','Color','w','Position',[50 50 900 400]);
subplot(1,2,1);
plot(1:n, cum_var, 'o-k', 'LineWidth',1.8, 'MarkerFaceColor','k');
xlabel('Number of components retained'); ylabel('Cumulative R² (%)');
title('Cumulative Variance Explained'); grid on;
yline(90,'--r','90%'); yline(95,'--b','95%');

subplot(1,2,2);
bar(1:n, marginal, 'FaceColor',[0.3 0.6 0.85]);
xlabel('Component #'); ylabel('Marginal R² (%)');
title('Marginal Variance per Component'); grid on;
sgtitle('NMF Reconstruction Quality');

% Residual map
figure('Name','Residual RMS Map','Color','w','Position',[50 50 900 380]);
subplot(1,2,1);
imagesc(resid_rms_full, [0 prctile(resid_rms_full(:),99)]);
axis image off; colormap(gca,'hot'); colorbar;
title('Per-pixel Residual RMS (full resolution)');

subplot(1,2,2);
histogram(resid_rms_full(:), 60, 'FaceColor',[0.8 0.4 0.3], 'EdgeColor','none');
xlabel('Residual RMS'); ylabel('Pixel count'); box off;
xline(mean(resid_rms_full(:)),'--k',sprintf('mean=%.4f',mean(resid_rms_full(:))));
title('Residual RMS Distribution');
sgtitle(sprintf('Reconstruction Residuals  |  Global rel. error = %.3f', rel_err));

%% =========================================================================
%  STAGE 8 — GLOBAL PSD (temporal quality reference)
% =========================================================================

figure('Name','Global PSD — all NMF timecourses','Color','w','Position',[50 50 800 380]);
subplot(1,2,1);
P1_sum = zeros(L/2+1, 1);
colors_psd = lines(n);
hold on;
for k = 1:n
    Y = fft(H_nmf(k,:)'); P2 = abs(Y/L);
    P1k = P2(1:L/2+1); P1k(2:end-1) = 2*P1k(2:end-1);
    plot(f, P1k, 'Color', colors_psd(k,:), 'LineWidth', 1.2, ...
        'DisplayName', sprintf('Comp %d (%.1fHz)',k,comp_stats(k).dom_freq));
    P1_sum = P1_sum + P1k;
end
hold off;
xlim([0 min(20,Fs)]); box off; grid on;
xlabel('Frequency (Hz)'); ylabel('Magnitude');
xline(5,'--k','5Hz','LineWidth',1);
title('Per-component PSD'); legend('Location','northeast','FontSize',7);

subplot(1,2,2);
plot(f, P1_sum, 'k', 'LineWidth', 1.8);
xlim([0 min(20,Fs)]); box off; grid on;
xline(5,'--b','5Hz'); xline(15,'--r','15Hz');
xlabel('Frequency (Hz)'); ylabel('Summed magnitude');
title('Summed PSD (all components)');
sgtitle('Spectral Content of NMF Timecourses');

%% =========================================================================
%  STAGE 9 — SAVE INDIVIDUAL COMPONENT .mat FILES
% =========================================================================

fprintf('\n--- Saving individual component reconstructions ---\n');
for k = 1:n
    X_single       = W_nmf(:,k) * H_nmf(k,:);
    recon_binned   = reshape(X_single, Hb, Wb, T);
    reconstructed_movie = imresize(recon_binned, [H W]);

    selected_component = k;
    Fs_out             = Fs;

    out_file = fullfile(CFG.output_dir, ...
        sprintf('reconstructed_NMF_Comp%d_%s.mat', k, base_name));
    save(out_file, 'reconstructed_movie', 'Fs_out', 'selected_component', ...
        'comp_stats', 'CFG');
    fprintf('  Saved Comp %d → %s\n', k, out_file);
end

% Combined (all components)
X_all     = W_nmf * H_nmf;
recon_all = imresize(reshape(X_all, Hb, Wb, T), [H W]);
reconstructed_movie = recon_all;
selected_ICs = 1:n;
out_combined = fullfile(CFG.output_dir, ...
    sprintf('reconstructed_NMF_COMBINED_%s.mat', base_name));
save(out_combined, 'reconstructed_movie', 'Fs', 'selected_ICs');
fprintf('  Saved COMBINED → %s\n', out_combined);

%% =========================================================================
%  STAGE 10 — SAVE DECOMPOSITION WORKSPACE
% =========================================================================

save(CFG.decomp_save, ...
    'W_nmf', 'H_nmf', 'nmf_maps_binned', 'nmf_maps_full', ...
    'comp_stats', 'f', 'L', ...
    'H', 'W', 'T', 'Hb', 'Wb', 'Fs', ...
    'n', 'min_val', 'r_squared', 'rel_err', ...
    'CFG', 'base_name');

fprintf('\n✓ Decomposition saved → %s\n', CFG.decomp_save);

fprintf('\n==============================================\n');
fprintf(' PIPELINE A (NMF) COMPLETE\n');
fprintf(' Components : %d\n', n);
fprintf(' Global R²  : %.2f%%\n', r_squared*100);
fprintf(' Rel. error : %.4f\n', rel_err);
fprintf(' Inspect figures, then set selected_components\n');
fprintf(' in pipeline_B_reconstruct.m (NMF version).\n');
fprintf('==============================================\n');

%% =========================================================================
%  LOCAL HELPER FUNCTIONS
% =========================================================================

function g = gini_coeff(x)
% Gini coefficient: 0 = uniform, 1 = fully sparse
x = abs(x(:)); x = sort(x);
n = numel(x);
if sum(x) == 0, g = 0; return; end
g = (2*sum((1:n)'.*x) / (n*sum(x))) - (n+1)/n;
g = max(0, min(1, g));
end

function tag = classify_nmf(s)
% Heuristic classification for thesis reference — adjust thresholds as needed
if s.dom_freq < 2 && s.pwr_0_5hz > 60
    tag = '[slow drift / DC]';
elseif s.dom_freq > 10 && s.pwr_gt15hz > 20
    tag = '[high-freq noise]';
elseif s.tc_autocorr > 0.95 && s.sp_kurt < 4
    tag = '[smooth / motion artefact?]';
elseif s.sp_kurt > 8 && s.sp_gini > 0.5
    tag = '[focal — candidate signal]';
elseif s.pwr_0_5hz > 70
    tag = '[low-freq dominated]';
else
    tag = '[review]';
end
end