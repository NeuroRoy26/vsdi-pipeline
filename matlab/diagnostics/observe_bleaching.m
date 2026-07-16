function diag = observe_bleaching(input_h5_path, varargin)
% OBSERVE_BLEACHING  Inspect photobleaching in motion-corrected VSD stacks.
% Usage:
%   bleaching_metrics = observe_bleaching('..._vsd_corrected.h5', ...
%         'Dataset','functional', ...
%         'FrameRate',100, ...            % Hz (optional)
%         'Mask',[], ...                  % logical HxW mask (optional)
%         'Downsample',1, ...             % spatial downsampling factor for map
%         'SmoothWin',11, ...             % frames for moving median (odd)
%         'FitDouble',false, ...          % also try double-exponential fit
%         'SavePrefix','plots/session1'); % if set, saves PNG + MAT
%
% Returns struct 'diag' with fields:
%   .frame_rate, .n_frames, .mean_trace, .median_trace
%   .linear_slope_per_min, .linear_r2
%   .exp_tau_s, .exp_r2, .exp_params [a,c,tau]
%   .doubleexp_tau1_s, .doubleexp_tau2_s, .doubleexp_r2 (if FitDouble)
%   .baseline_drift_pct (first 10% vs last 10%)
%   .residual_std, .has_bleach (simple heuristic)
%   .time_per_frame_s
%
% Notes:
% - Works on HDF5 datasets '/functional' or '/structural' created by vsd_motion_correct.
% - Mask is optional; if empty, uses all pixels.
% - Fits are ordinary least squares on smoothed mean trace.

%% Parse args
p = inputParser;
addRequired(p,'input_h5_path',@(s)ischar(s)||isstring(s));
addParameter(p,'Dataset','functional',@(s)ischar(s)||isstring(s));
addParameter(p,'FrameRate',[],@(x)isempty(x)||isscalar(x));
addParameter(p,'Mask',[],@(m)islogical(m)||isempty(m));
addParameter(p,'Downsample',1,@(x)isnumeric(x)&&x>=1);
addParameter(p,'SmoothWin',11,@(x)isnumeric(x)&&mod(x,2)==1&&x>=1);
addParameter(p,'FitDouble',false,@islogical);
addParameter(p,'SavePrefix','',@(s)ischar(s)||isstring(s));
parse(p,input_h5_path,varargin{:});

dataset   = char(p.Results.Dataset);
fs        = p.Results.FrameRate;
mask      = p.Results.Mask;
ds        = p.Results.Downsample;
win       = p.Results.SmoothWin;
fitDouble = p.Results.FitDouble;
savePref  = char(p.Results.SavePrefix);

if ~isfile(input_h5_path), error('File not found: %s',input_h5_path); end

%% Load data
fprintf('Reading HDF5 dataset "/%s" from %s ...\n', dataset, input_h5_path);
try
    data = h5read(input_h5_path, ['/' dataset]);
catch ME
    error('Failed to read dataset "/%s": %s', dataset, ME.message);
end
data = double(data); % H x W x T
[H,W,T] = size(data);
fprintf('Data: %dx%dx%d (H x W x T)\n', H,W,T);

if isempty(mask)
    mask = true(H,W);
elseif ~isequal(size(mask),[H W])
    error('Mask size must match data spatial size [%d %d].', H, W);
end
mask = mask & ~isnan(mask);

%% Compute per-frame stats
M = nnz(mask);
mean_trace   = zeros(T,1);
median_trace = zeros(T,1);
for t = 1:T
    v = data(:,:,t);
    v = v(mask);
    mean_trace(t)   = mean(v,'omitnan');
    median_trace(t) = median(v,'omitnan');
end

% Smooth for fitting/visualization
mean_s = movmedian(mean_trace, win, 'omitnan');

% Time vector
if isempty(fs)
    tvec = (0:T-1)';         % frames
    xlab1 = 'Frame';
    t_seconds = [];
else
    tvec = ((0:T-1)')/fs;    % seconds
    xlab1 = 'Time (s)';
    t_seconds = tvec;
end

%% Linear trend (frame or seconds)
X = [ones(T,1) tvec];
b = X \ mean_s;
yhat_lin = X*b;
SS_res = sum((mean_s - yhat_lin).^2);
SS_tot = sum((mean_s - mean(mean_s)).^2);
r2_lin = 1 - SS_res/SS_tot;

% slope in units per minute for interpretability (if time known)
if isempty(fs)
    slope_per_min = NaN;
else
    slope_per_min = b(2)*60; % intensity units per minute
end

%% Single-exponential fit y = a*exp(-t/tau) + c
if isempty(fs)
    tfit = (0:T-1)'; % frames
    scale = 1;       % tau in frames
else
    tfit = t_seconds;
    scale = 1;       % tau in seconds
end

y = mean_s;
y0 = y(1);
y_end = y(round(0.9*T));
guess_tau = max( (tfit(end)-tfit(1))/3 , eps );
guess = [max(y0 - y_end, eps), y_end, max(guess_tau, eps)]; % [a, c, tau]

expfun = @(prm,t) prm(1).*exp(-(t)./max(prm(3),eps)) + prm(2);
obj = @(prm) expfun(prm,tfit) - y;

opts = optimset('Display','off','TolX',1e-8,'TolFun',1e-8,'MaxFunEvals',2e4,'MaxIter',2e4);
try
    prm_exp = fminsearch(@(p) norm(obj(p))^2, guess, opts);
catch
    prm_exp = guess;
end
yhat_exp = expfun(prm_exp, tfit);
SS_res_e = sum((y - yhat_exp).^2);
r2_exp   = 1 - SS_res_e/SS_tot;
tau_s    = prm_exp(3)*scale;

%% Optional double-exponential y = a1*exp(-t/t1)+a2*exp(-t/t2)+c
prm2 = []; r2_2 = NaN; tau1_s = NaN; tau2_s = NaN; yhat_exp2 = [];
if fitDouble
    dexpfun = @(p,t) p(1).*exp(-t./max(p(3),eps)) + p(2).*exp(-t./max(p(4),eps)) + p(5);
    % initial guess: split single a into two, taus: tau and 5*tau
    g = [0.6*prm_exp(1), 0.4*prm_exp(1), max(prm_exp(3),eps), max(5*prm_exp(3),eps), prm_exp(2)];
    lb = [0, 0, eps, eps, -Inf];
    ub = [Inf, Inf, Inf, Inf, Inf];
    % simple projected fminsearch
    clamp = @(p) max(min(p,ub),lb);
    f = @(p) sum((dexpfun(p,tfit)-y).^2);
    p = g; fbest = f(p);
    for k=1:5000
        p = clamp(p + 0.01*randn(size(p)));
        fk = f(p);
        if fk < fbest
            fbest = fk; g = p;
        end
    end
    try
        prm2 = fminsearch(@(p) f(clamp(p)), g, opts);
        prm2 = clamp(prm2);
    catch
        prm2 = g;
    end
    yhat_exp2 = dexpfun(prm2,tfit);
    SS_res2 = sum((y - yhat_exp2).^2);
    r2_2    = 1 - SS_res2/SS_tot;
    tau1_s  = prm2(3)*scale;
    tau2_s  = prm2(4)*scale;
end

%% Baseline drift early vs late (10% windows)
w = max(1, floor(0.1*T));
m_early = mean(mean_trace(1:w),'omitnan');
m_late  = mean(mean_trace(end-w+1:end),'omitnan');
baseline_drift_pct = 100*(m_late - m_early)/max(m_early, eps);

%% Residuals (single-exp)
residual = y - yhat_exp;
res_std  = std(residual,1,'omitnan');

%% Simple heuristic: evidence of bleaching?
has_bleach = false;
if ~isempty(fs)
    has_bleach = (slope_per_min < 0) && (r2_exp > 0.5) && (baseline_drift_pct < -2);
else
    has_bleach = (r2_exp > 0.5) && (baseline_drift_pct < -2);
end

%% Spatial quick-look: per-pixel Spearman rho with time (downsampled)
rho_map = [];
if ds > 1
    data_ds = data(1:ds:end, 1:ds:end, :);
    mask_ds = mask(1:ds:end, 1:ds:end);
else
    data_ds = data; mask_ds = mask;
end
[Hd,Wd,~] = size(data_ds);
rho_map = nan(Hd,Wd);
tt = (1:T)'; % frame index is fine for correlation
for i = 1:Hd
    for j = 1:Wd
        if mask_ds(i,j)
            v = squeeze(data_ds(i,j,:));
            if any(isfinite(v))
                rho_map(i,j) = corr(v, tt, 'Type','Spearman','Rows','complete');
            end
        end
    end
end

%% Plots
figure('Name','Bleaching diagnostics','Color','w','Position',[100 100 1200 700]);

subplot(2,3,1);
plot(tvec, mean_trace, '.', 'MarkerSize',5); hold on;
plot(tvec, mean_s, 'LineWidth',1);
if ~isempty(fs), xlabel('Time (s)'); else, xlabel('Frame'); end
ylabel('Mean intensity'); title('Global mean over time');
legend({'mean','smoothed'},'Location','best'); box on;

subplot(2,3,2);
plot(tvec, mean_s, 'LineWidth',1); hold on;
plot(tvec, yhat_lin, '--');
plot(tvec, yhat_exp, '-', 'LineWidth',1.5);
if fitDouble && ~isempty(yhat_exp2), plot(tvec, yhat_exp2, '-.','LineWidth',1); end
if ~isempty(fs), xlabel('Time (s)'); else, xlabel('Frame'); end
ylabel('Intensity'); title('Fits: linear vs exponential');
leg = {'data','linear','exp1'};
if fitDouble, leg{end+1} = 'exp2'; end
legend(leg,'Location','best'); box on;

subplot(2,3,3);
plot(tvec, residual, 'LineWidth',1);
if ~isempty(fs), xlabel('Time (s)'); else, xlabel('Frame'); end
ylabel('Residual (data - exp1)'); title(sprintf('Residuals (std = %.3g)', res_std)); box on;

subplot(2,3,4);
bar([baseline_drift_pct]); ylabel('%'); title('Baseline drift (early→late)');
set(gca,'XTickLabel',{'drift %'}); grid on;

subplot(2,3,5);
text(0.05,0.95, sprintf('Frames: %d\nLinear slope (/min): %s\nR^2 linear: %.3f\nTau (exp1): %s\nR^2 exp1: %.3f%s\nDrift: %.2f %%\nBleach detected: %d', ...
    T, num2str_safe(slope_per_min), r2_lin, num2str_safe(tau_s), r2_exp, ...
    ternary(fitDouble, sprintf('\nR^2 exp2: %.3f', r2_2), ''), ...
    baseline_drift_pct, has_bleach), 'Units','normalized','VerticalAlignment','top','FontName','Consolas','FontSize',11);
axis off;

subplot(2,3,6);
if ~all(isnan(rho_map(:)))
    imagesc(rho_map, [-1 1]); axis image off; colorbar;
    title(sprintf('Spearman rho(pixel, time)%s', ternary(ds>1, sprintf(' (downsample %dx)',ds), '')));
else
    axis off; title('No rho map');
end

sgtitle(sprintf('Bleaching diagnostics: %s /%s', input_h5_path, dataset), 'Interpreter','none');

%% Save (optional)
diag = struct();
diag.frame_rate           = fs;
diag.n_frames             = T;
diag.mean_trace           = mean_trace;
diag.median_trace         = median_trace;
diag.linear_slope_per_min = slope_per_min;
diag.linear_r2            = r2_lin;
diag.exp_tau_s            = tau_s;
diag.exp_r2               = r2_exp;
diag.exp_params           = struct('a',prm_exp(1),'c',prm_exp(2),'tau',prm_exp(3));
if fitDouble
    diag.doubleexp_tau1_s = tau1_s;
    diag.doubleexp_tau2_s = tau2_s;
    diag.doubleexp_r2     = r2_2;
end
diag.baseline_drift_pct   = baseline_drift_pct;
diag.residual_std         = res_std;
diag.has_bleach           = has_bleach;
diag.time_per_frame_s     = ternary(isempty(fs), NaN, 1/fs);
diag.rho_map              = rho_map;
diag.mask                 = mask;

if ~isempty(savePref)
    png = [savePref '_bleach.png'];
    mat = [savePref '_bleach.mat'];
    try
        exportgraphics(gcf, png, 'Resolution', 200);
        save(mat, 'diag','-v7.3');
        fprintf('Saved %s and %s\n', png, mat);
    catch ME
        warning('Failed to save outputs: %s', ME.message);
    end
end

end % main

function s = num2str_safe(x)
if isnan(x), s = 'NaN'; else, s = sprintf('%.3g',x); end
end
function out = ternary(cond, a, b), if cond, out=a; else, out=b; end, end
