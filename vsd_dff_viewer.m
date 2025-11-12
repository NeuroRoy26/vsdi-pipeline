function R = vsd_dff_viewer(h5file, varargin)
% VSD_DFF_VIEWER  Compute and visualize ΔF/F from a motion-corrected stack.
%
% Usage:
%   R = vsd_dff_viewer('data/motion_compensated/led_E0B0_vsd_corrected.h5', ...
%         'Dataset','functional', ...
%         'BaselineIdx',1:375, ...
%         'StimIdx',376:750, ...
%         'ROI',[], ...           % logical HxW; if empty: global trace
%         'FrameRate',250.335, ...     % Hz; for time axis (optional)
%         'SavePrefix','data/led_E0B0');       % if non-empty: saves PNG + MAT
%
% Outputs struct R:
%   .F0            : baseline mean image (HxW)
%   .dFF_map       : mean ΔF/F over StimIdx (HxW)
%   .z_map         : (mean_stim - mean_base) / std_base (HxW)
%   .trace_time    : time vector (T x 1)
%   .trace_raw     : ROI/global raw intensity (T x 1)
%   .trace_dff     : ROI/global ΔF/F (T x 1)
%   .baseline_mean : scalar baseline for the ROI/global trace
%   .params        : struct of parameters
%
% Notes:
% - Works on HDF5 dataset '/functional' (default) produced by your motion-correction script.
% - Handles large files by reading in time chunks (no full stack in RAM).
% - ΔF/F(t) = (F(t) - F0) / F0 with F0 = mean over BaselineIdx.

%% ---- args
p = inputParser;
addRequired(p,'h5file',@(s)ischar(s)||isstring(s));
addParameter(p,'Dataset','functional',@(s)ischar(s)||isstring(s));
addParameter(p,'BaselineIdx',1:375,@(v)isnumeric(v)&&isvector(v));
addParameter(p,'StimIdx',376:750,@(v)isnumeric(v)&&isvector(v));
addParameter(p,'ROI',[],@(m)islogical(m)||isempty(m));
addParameter(p,'FrameRate',[],@(x)isempty(x)||isscalar(x));
addParameter(p,'SavePrefix','',@(s)ischar(s)||isstring(s));
addParameter(p,'ChunkT',200,@(x)isnumeric(x)&&isscalar(x)&&x>=1);
parse(p,h5file,varargin{:});
ds    = char(p.Results.Dataset);
pre   = p.Results.BaselineIdx(:)';
stim  = p.Results.StimIdx(:)';
roi   = p.Results.ROI;
fs    = p.Results.FrameRate;
saveP = char(p.Results.SavePrefix);
chunkT= p.Results.ChunkT;

if ~isfile(h5file), error('File not found: %s', h5file); end

%% ---- dataset info
info = h5info(h5file, ['/' ds]);
sz   = info.Dataspace.Size;       % [H W T]
H=sz(1); W=sz(2); T=sz(3);

% clip indices into [1..T]
pre  = pre(pre>=1 & pre<=T);
stim = stim(stim>=1 & stim<=T);
if isempty(pre) || isempty(stim)
    error('BaselineIdx or StimIdx empty after clipping to [1..%d].', T);
end

% default ROI is "all pixels"
if isempty(roi)
    roi = true(H,W);
else
    if ~isequal(size(roi),[H W])
        error('ROI size must be %dx%d to match dataset.', H, W);
    end
end
roi_idx = find(roi);
n_roi   = numel(roi_idx);

%% ---- helpers
readBlock = @(tStart,tCount) double(h5read(h5file, ['/' ds], [1 1 tStart], [H W tCount]));

% Split an index vector into contiguous runs (start,count) pairs
contigRuns = @(idx) split_runs(idx);
preRuns  = contigRuns(pre);
stimRuns = contigRuns(stim);

%% ---- accumulate baseline stats: mean and std per pixel
sum_base  = zeros(H,W);
sum2_base = zeros(H,W);
nb = numel(pre);

for r = 1:size(preRuns,1)
    s  = preRuns(r,1);
    nc = preRuns(r,2);
    X  = readBlock(s, nc);        % HxWxnc
    sum_base  = sum_base  + sum(X,3);
    sum2_base = sum2_base + sum(X.^2,3);
end
F0   = sum_base ./ max(nb,1);
varb = max(sum2_base./max(nb,1) - F0.^2, 0);
stdb = sqrt(varb);

%% ---- accumulate stim mean per pixel
sum_stim = zeros(H,W);
ns = numel(stim);
for r = 1:size(stimRuns,1)
    s  = stimRuns(r,1);
    nc = stimRuns(r,2);
    X  = readBlock(s, nc);
    sum_stim = sum_stim + sum(X,3);
end
Fstim = sum_stim ./ max(ns,1);

% ΔF/F map (mean over stim window)
dFF_map = (Fstim - F0) ./ max(F0, eps);
% z-like map (quick SNR proxy)
z_map   = (Fstim - sum_base./max(nb,1)) ./ max(stdb, eps);

%% ---- ROI/global trace across all frames (streamed)
trace_raw = zeros(T,1);
for tStart = 1:chunkT:T
    nc = min(chunkT, T - tStart + 1);
    X  = readBlock(tStart, nc);   % HxWxnc
    Xr = reshape(X, H*W, nc);
    vr = mean(Xr(roi_idx,:), 1);  % mean over ROI for each frame
    trace_raw(tStart:tStart+nc-1) = vr(:);
end
% ROI baseline (mean over baseline frames)
F0_roi = mean(trace_raw(pre), 'omitnan');
trace_dff = (trace_raw - F0_roi) / max(F0_roi, eps);

% time axis
if isempty(fs)
    tt = (1:T)';  % frames
else
    tt = (0:T-1)'/fs; % seconds
end

%% ---- figure
figure('Color','w','Position',[100 100 1200 550]);
tlabel = ternary(isempty(fs), 'Frame', 'Time (s)');

subplot(1,2,1);
plot(tt, trace_dff, 'LineWidth',1); hold on;
yl = ylim;
xline(tt(pre(1)), ':'); xline(tt(pre(end)), ':');
xline(tt(stim(1)), '--'); xline(tt(stim(end)), '--');
ylim(yl);
xlabel(tlabel); ylabel('ΔF/F (ROI/global)');
title('ROI/global ΔF/F trace'); grid on;

subplot(1,2,2);
% robust display range
vals = dFF_map(roi);
lo = prctile(vals(:), 2); hi = prctile(vals(:), 98);
imagesc(dFF_map, [lo hi]); axis image off; colorbar;
title(sprintf('Stimulus ΔF/F map (mean over %d frames)', ns));

sgtitle(sprintf('ΔF/F viewer: %s /%s', h5file, ds), 'Interpreter','none');

%% ---- save (optional)
R = struct();
R.F0            = F0;
R.dFF_map       = dFF_map;
R.z_map         = z_map;
R.trace_time    = tt;
R.trace_raw     = trace_raw;
R.trace_dff     = trace_dff;
R.baseline_mean = F0_roi;
R.params        = struct('Dataset',ds,'BaselineIdx',pre,'StimIdx',stim,'ROI_is_global',isempty(p.Results.ROI),'FrameRate',fs);

if ~isempty(saveP)
    png = [saveP '_dff.png'];
    mat = [saveP '_dff.mat'];
    try
        exportgraphics(gcf, png, 'Resolution', 200);
        save(mat, 'R','-v7.3');
        fprintf('Saved %s and %s\n', png, mat);
    catch ME
        warning('Save failed: %s', ME.message);
    end
end

end % main

%% ---- helpers
function runs = split_runs(idx)
% Return Nx2 [start,count] for contiguous ascending integer indices.
idx = sort(unique(idx(:)'));
if isempty(idx), runs = zeros(0,2); return; end
d = [true, diff(idx)==1];  % new run starts where d==false (after shift)
starts = idx([1, find(~d(2:end))+1]);
ends   = [idx(find(~d(2:end))), idx(end)];
runs = [starts(:), (ends(:)-starts(:)+1)];
end

function out = ternary(cond,a,b), if cond, out=a; else, out=b; end, end
