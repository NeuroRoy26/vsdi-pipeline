function viz = vsd_visualize(h5file, varargin)
% Visualize VSD ΔF/F with a diverging colormap and gentle enhancement.
%usage: viz = vsd_visualize('data/motion_compensated/led_E0B0_vsd_corrected.h5', 'Dataset','functional');
p = inputParser;
addRequired(p,'h5file',@(s)ischar(s)||isstring(s));
addParameter(p,'Dataset','functional',@(s)ischar(s)||isstring(s));
addParameter(p,'sigma',1.0,@isnumeric);          % spatial blur (pixels)
addParameter(p,'clim',3e-4,@isnumeric);          % half-range for display
addParameter(p,'percentile_clip',[]);            % e.g., [1 99] overrides clim
parse(p,h5file,varargin{:});

dataset = char(p.Results.Dataset);
X = double(h5read(h5file, ['/' dataset]));   % H x W x T
[H,W,T] = size(X);

% Pre/stim indices (match your sanity check behavior)
if T ~= 750
    half = floor(T/2);
    pre_idx  = 1:half;
    stim_idx = half+1:T;
else
    pre_idx  = 1:375;
    stim_idx = 376:750;
end

% --- 1) Per-pixel baseline and ΔF/F ---
F0      = mean(X(:,:,pre_idx), 3);                  % baseline per pixel
F0      = F0 + eps;                                 % avoid divide-by-zero
dff_all = bsxfun(@rdivide, bsxfun(@minus, X, F0), F0);

% Summaries to visualize
dff_pre_mean  = mean(dff_all(:,:,pre_idx), 3);
dff_stim_mean = mean(dff_all(:,:,stim_idx), 3);
dff_delta     = dff_stim_mean - dff_pre_mean;       % effect of stimulus

% --- 2) Gentle denoising to reduce speckle but keep edges ---
if p.Results.sigma > 0
    dff_pre_mean  = imgaussfilt(dff_pre_mean,  p.Results.sigma);
    dff_stim_mean = imgaussfilt(dff_stim_mean, p.Results.sigma);
    dff_delta     = imgaussfilt(dff_delta,     p.Results.sigma);
end

% --- 3) Decide display limits ---
if ~isempty(p.Results.percentile_clip)
    % Robust symmetric limits around zero using percentiles of |ΔF/F|
    mags   = abs(dff_delta(:));
    pr     = prctile(mags, p.Results.percentile_clip(2));
    clim   = pr;                                     % symmetric about 0
else
    clim = p.Results.clim;                           % e.g., 3e-4 as you saw
end
clims = [-clim, +clim];

% --- 4) Show three useful views ---
figure('Color','w','Name','VSD ΔF/F visualization');

subplot(1,3,1);
imagesc(dff_pre_mean); axis image off;
title('mean ΔF/F (pre)'); caxis(clims); colormap(gca,divergingCmap());

subplot(1,3,2);
imagesc(dff_stim_mean); axis image off;
title('mean ΔF/F (stim)'); caxis(clims); colormap(gca,divergingCmap());

subplot(1,3,3);
imagesc(dff_delta); axis image off;
title('stim - pre (ΔΔF/F)'); caxis(clims); colormap(gca,divergingCmap());
cb = colorbar; cb.Label.String = 'ΔF/F';

% Optional pop: light unsharp mask on the delta view (display only)
% (comment out if you prefer raw)
drawnow;
frame = getframe(subplot(1,3,3));
I = im2double(frame.cdata);
I_sharp = imsharpen(I,'Radius',1.0,'Amount',0.7);
subplot(1,3,3); imshow(I_sharp); title('stim - pre (sharpened view)');

viz = struct('dff_pre_mean',dff_pre_mean,...
             'dff_stim_mean',dff_stim_mean,...
             'dff_delta',dff_delta,...
             'clims',clims);
end

function cmap = divergingCmap(n)
% Simple blue-white-red diverging map with white at zero.
if nargin<1, n = 256; end
h = n/2;
% negative: blue -> white
neg = [linspace(0,1,h)', linspace(0,1,h)', ones(h,1)];
neg(:,1) = 0;              % R from 0->1 but we’ll clamp to build white
neg(:,2) = linspace(0,1,h)'; 
neg(:,3) = 1;              % blue channel high
neg = [linspace(0,1,h)', linspace(0,1,h)', ones(h,1)]; % actually build via HSV is cleaner
% Let’s do it more explicitly:
neg = [linspace(0,1,h)', linspace(0,1,h)', ones(h,1)]; % start black->white
neg(:,1) = 0;                  % R: 0->0
neg(:,2) = linspace(0,1,h)';   % G: 0->1
neg(:,3) = 1;                  % B: 1
% positive: white -> red
pos = [ones(h,1), linspace(1,0,h)', linspace(1,0,h)'];
cmap = [neg; pos];
% Ensure size and bounds
cmap = max(0,min(1,cmap));
end
%%
h5file  = 'data/motion_compensated/led_E0B0_vsd_corrected.h5';
dataset = 'functional';

X = double(h5read(h5file, ['/' dataset]));   % H x W x T
[~,~,T] = size(X);

% Split into pre/stim like before
if T ~= 750
    half = floor(T/2);
    pre_idx  = 1:half;
else
    pre_idx  = 1:375;
end

% Baseline per pixel
F0 = mean(X(:,:,pre_idx), 3);
F0 = F0 + eps;

% ΔF/F for all frames
dff_all = bsxfun(@rdivide, bsxfun(@minus, X, F0), F0);

% Display loop
clim = 3e-4; % same as static plots
figure('Color','w');
for t = 1:T
    imagesc(dff_all(:,:,t)); axis image off;
    caxis([-clim clim]); colormap(redblue); colorbar;
    title(sprintf('ΔF/F, frame %d/%d', t, T));
    drawnow;
end

function cmap = redblue(n)
    if nargin<1, n=256; end
    cmap = [linspace(0,1,n/2)', linspace(0,1,n/2)', ones(n/2,1); ...
            ones(n/2,1), linspace(1,0,n/2)', linspace(1,0,n/2)'];
end
%%
viz = vsd_visualize('data/motion_compensated/led_E0B0_vsd_corrected.h5', 'Dataset','functional');