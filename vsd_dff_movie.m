function vsd_dff_movie(h5file, varargin)
% Make a ΔF/F movie from a motion-corrected stack.
% Usage:
%  vsd_dff_movie('data/motion_compensated/led_E0B0_vsd_corrected.h5', ...
%     'Dataset','functional', ...
%     'BaselineIdx',1:375, ...
%     'Bin',2, ...                % 250 Hz -> 125 fps display
%     'DisplayFPS',125, ...
%     'Sigma',1, ...              % light spatial smoothing
%     'Range',[-0.01 0.01], ...   % ±1%
%     'Out','data/led_E0B0_dff.mp4');
% Notes:
%  - Bin=5 turns 250 Hz data into 50 fps display with √5 SNR gain.
%  - Range is ΔF/F color scale (e.g., [-0.01 0.01] = ±1%).
%  - Mask (logical HxW) can hide vessels etc. (masked pixels shown as NaN).

p = inputParser;
addRequired(p,'h5file',@(s)ischar(s)||isstring(s));
addParameter(p,'Dataset','functional',@(s)ischar(s)||isstring(s));
addParameter(p,'BaselineIdx',1:375,@(v)isnumeric(v)&&isvector(v));
addParameter(p,'StimIdx',376:750,@(v)isnumeric(v)&&isvector(v)); %#ok<*NVREPL>
addParameter(p,'Bin',5,@(x)isnumeric(x)&&isscalar(x)&&x>=1);
addParameter(p,'DisplayFPS',50,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'Sigma',0,@(x)isnumeric(x)&&isscalar(x)&&x>=0);     % spatial Gaussian
addParameter(p,'Range',[-0.01 0.01],@(v)isnumeric(v)&&numel(v)==2);
addParameter(p,'Mask',[],@(m)islogical(m)||isempty(m));
addParameter(p,'Out','dff_movie.mp4',@(s)ischar(s)||isstring(s));
parse(p,h5file,varargin{:});
ds   = char(p.Results.Dataset);
pre  = p.Results.BaselineIdx(:)';
bin  = p.Results.Bin;
fps  = p.Results.DisplayFPS;
sig  = p.Results.Sigma;
rng  = p.Results.Range;
mask = p.Results.Mask;
out  = char(p.Results.Out);

fprintf('Reading %s /%s ...\n', h5file, ds);
X = double(h5read(h5file, ['/' ds]));   % H x W x T
[H,W,T] = size(X);

% sanity on indices
pre = pre(pre>=1 & pre<=T);
if isempty(pre), error('BaselineIdx empty after clipping.'); end

% baseline image and ΔF/F over all frames
F0 = mean(X(:,:,pre), 3);
F0(F0==0) = eps;
dff = bsxfun(@rdivide, bsxfun(@minus, X, F0), F0);  % HxWxT

% optional mask
if ~isempty(mask)
    if ~isequal(size(mask),[H W]), error('Mask must be %dx%d.',H,W); end
    for t = 1:T
        tmp = dff(:,:,t);
        tmp(~mask) = NaN;
        dff(:,:,t) = tmp;
    end
end

% optional spatial smoothing
if sig > 0
    for t = 1:T
        dff(:,:,t) = imgaussfilt(dff(:,:,t), sig, 'FilterSize',max(3,2*ceil(3*sig)+1));
    end
end

% temporal binning for SNR / display
if bin > 1
    nOut = floor(T/bin);
    dff = mean(reshape(dff(:,:,1:nOut*bin), H, W, bin, nOut), 3); % HxWxN
else
    nOut = T;
end

% video writer
v = VideoWriter(out, 'MPEG-4');
v.FrameRate = fps;
open(v);

% figure for consistent capture
f = figure('Color','w','Position',[100 100 720 720]);
ax = axes('Parent',f);
colormap(ax, parula);
for k = 1:nOut
    imagesc(ax, dff(:,:,k), rng);
    axis(ax,'image','off');
    colorbar(ax); title(ax, sprintf('\\DeltaF/F  (frame %d/%d)', k, nOut));
    drawnow;
    frame = getframe(f);
    writeVideo(v, frame);
end
close(v);
close(f);
fprintf('Saved movie to %s (display FPS = %g, bin = %d)\n', out, fps, bin);
end
