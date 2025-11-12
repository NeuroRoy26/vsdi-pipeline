function vsd_view_fluorescence(h5file, varargin)
% View and/or export a raw fluorescence movie (F) with optional denoising,
% plus an optional ΔF/F view for comparison.
%
% Example:
%  vsd_view_fluorescence('data/motion_compensated/led_E0B0_vsd_corrected.h5', ...
%     'Dataset','functional', ...
%     'Mode','F', ...             % 'F' (raw/denoised), 'dff', or 'both'
%     'BaselineIdx',1:375, ...
%     'Bin',5, ...                % temporal binning: improves SNR ~ sqrt(bin)
%     'DisplayFPS',50, ...
%     'Sigma',1, ...              % Gaussian smoothing (pixels)
%     'MedianWin',0, ...          % median filter window (0=off, else odd int)
%     'ClipLowPct',1, ...         % clip bottom X% of F0 to avoid division noise
%     'ClipHighPct',99, ...     % clip top Y% for contrast when viewing F
%     'Mask',[], ...              % logical HxW
%     'Out', '', ...              % e.g., 'data/led_E0B0_F.mp4' (empty=don’t save)
%     'ShowColorbar',true);

p = inputParser;
addRequired(p,'h5file',@(s)ischar(s)||isstring(s));
addParameter(p,'Dataset','functional',@(s)ischar(s)||isstring(s));
addParameter(p,'Mode','F',@(s)ischar(s)||isstring(s));   % 'F','dff','both'
addParameter(p,'BaselineIdx',1:100,@(v)isnumeric(v)&&isvector(v));
addParameter(p,'Bin',1,@(x)isnumeric(x)&&isscalar(x)&&x>=1);
addParameter(p,'DisplayFPS',50,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'Sigma',0,@(x)isnumeric(x)&&isscalar(x)&&x>=0);
addParameter(p,'MedianWin',0,@(x)isnumeric(x)&&isscalar(x)&&x>=0);
addParameter(p,'ClipLowPct',1,@(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<=10);
addParameter(p,'ClipHighPct',99.9,@(x)isnumeric(x)&&isscalar(x)&&x>0&&x<=100);
addParameter(p,'Mask',[],@(m)islogical(m)||isempty(m));
addParameter(p,'Out','',@(s)ischar(s)||isstring(s));
addParameter(p,'ShowColorbar',true,@islogical);
parse(p,h5file,varargin{:});

ds    = char(p.Results.Dataset);
mode  = lower(char(p.Results.Mode));
pre   = p.Results.BaselineIdx(:)';
bin   = p.Results.Bin;
fps   = p.Results.DisplayFPS;
sig   = p.Results.Sigma;
mwin  = p.Results.MedianWin;
clipL = p.Results.ClipLowPct;
clipH = p.Results.ClipHighPct;
mask  = p.Results.Mask;
out   = char(p.Results.Out);
showcb= p.Results.ShowColorbar;

fprintf('Reading %s /%s ...\n', h5file, ds);
F = double(h5read(h5file, ['/' ds]));   % H x W x T
[H,W,T] = size(F);

% sanity on indices
pre = pre(pre>=1 & pre<=T);
if isempty(pre), error('BaselineIdx empty after clipping.'); end

% optional mask sanity
if ~isempty(mask) && ~isequal(size(mask),[H W])
    error('Mask must be %dx%d.',H,W);
end

% --------- Build a robust baseline image F0 ----------
% Raw mean baseline
F0 = mean(F(:,:,pre), 3);

% Clip very dim baseline pixels (avoid division blow-ups in dF/F)
if clipL > 0
    thrL = prctile(F0(:), clipL);
    F0(F0 < max(thrL, eps)) = max(thrL, eps);
else
    F0(F0==0) = eps;
end

% Optional masking of vessels or artifacts
if ~isempty(mask)
    % NaN out masked pixels in both F and F0 for viewing
    for t = 1:T
        tmp = F(:,:,t); tmp(~mask) = NaN; F(:,:,t) = tmp;
    end
    F0(~mask) = NaN;
end

% --------- Temporal binning for SNR / display ----------
if bin > 1
    nOut = floor(T/bin);
    F = mean(reshape(F(:,:,1:nOut*bin), H, W, bin, nOut), 3); % HxWxN
else
    nOut = T;
end

% --------- Spatial denoising ----------
% Order: median (kills isolated speckles) -> Gaussian (low-pass)
if mwin >= 3 && mod(mwin,2)==1
    for t = 1:nOut
        % medfilt2 handles NaNs by treating them as 0; avoid touching NaNs
        frame = F(:,:,t);
        nanmask = isnan(frame);
        frame(nanmask) = 0;
        frame = medfilt2(frame, [mwin mwin], 'symmetric');
        frame(nanmask) = NaN;
        F(:,:,t) = frame;
    end
elseif mwin ~= 0
    warning('MedianWin should be an odd integer >=3. Skipping median filter.');
end

if sig > 0
    fsz = max(3, 2*ceil(3*sig)+1);
    for t = 1:nOut
        F(:,:,t) = imgaussfilt(F(:,:,t), sig, 'FilterSize', fsz);
    end
end

% --------- Optional ΔF/F for comparison ----------
if strcmp(mode,'dff') || strcmp(mode,'both')
    dff = bsxfun(@rdivide, bsxfun(@minus, F, F0), F0); % robust F0 guards small baselines
end

% --------- Contrast settings for visualization ----------
% For F: percentile-based scaling to avoid being dominated by a few hot pixels
Fmin = prctile(F(:), clipL, 'all');
Fmax = prctile(F(:), clipH, 'all');
if ~isfinite(Fmin) || ~isfinite(Fmax) || Fmin==Fmax
    Fmin = min(F(:),[],'omitnan'); Fmax = max(F(:),[],'omitnan');
end

% For ΔF/F: symmetric ±range using robust percentiles around zero
if exist('dff','var')
    p = max(abs([prctile(dff(:), 99, 'all'), prctile(dff(:), 1, 'all')]));
    dffRange = [-p, p];  % auto-symmetric
end

% --------- Figure / video ----------
makeVideo = ~isempty(out);
if makeVideo
    v = VideoWriter(out, 'MPEG-4');
    v.FrameRate = fps;
    open(v);
end

switch mode
    case 'f'
        f1 = figure('Color','w','Position',[100 100 740 760]);
        ax1 = axes('Parent',f1); colormap(ax1, gray);
        for k = 1:nOut
            imagesc(ax1, F(:,:,k), [Fmin Fmax]); axis(ax1,'image','off');
            %imagesc(ax1, F(:,:,k), [395 400]); axis(ax1,'image','off');
            if showcb, colorbar(ax1); end
            title(ax1, sprintf('Fluorescence F (frame %d/%d)', k, nOut));
            drawnow;
            if makeVideo
                writeVideo(v, getframe(f1));
            end
        end
        if makeVideo
            close(v);
            fprintf('Saved movie to %s (FPS=%g, bin=%d)\n', out, fps, bin);
        end
        if isvalid(f1), close(f1); end

    case 'dff'
        f2 = figure('Color','w','Position',[100 100 740 760]);
        ax2 = axes('Parent',f2); colormap(ax2, parula);
        for k = 1:nOut
            imagesc(ax2, dff(:,:,k), dffRange); axis(ax2,'image','off');
            if showcb, colorbar(ax2); end
            title(ax2, sprintf('\\DeltaF/F (frame %d/%d)', k, nOut));
            drawnow;
            if makeVideo
                writeVideo(v, getframe(f2));
            end
        end
        if makeVideo
            close(v);
            fprintf('Saved movie to %s (FPS=%g, bin=%d)\n', out, fps, bin);
        end
        if isvalid(f2), close(f2); end

    case 'both'
        f3 = figure('Color','w','Position',[100 100 1280 640]);
        axF   = subplot(1,2,1,'Parent',f3); colormap(axF, gray);
        axDFF = subplot(1,2,2,'Parent',f3); colormap(axDFF, parula);
        for k = 1:nOut
            imagesc(axF,   F(:,:,k),   [Fmin Fmax]);   axis(axF,'image','off');
            if showcb, colorbar(axF); end
            title(axF,   sprintf('F (frame %d/%d)', k, nOut));

            imagesc(axDFF, dff(:,:,k), dffRange);     axis(axDFF,'image','off');
            if showcb, colorbar(axDFF); end
            title(axDFF, sprintf('\\DeltaF/F (frame %d/%d)', k, nOut));

            drawnow;
            if makeVideo
                writeVideo(v, getframe(f3));
            end
        end
        if makeVideo
            close(v);
            fprintf('Saved movie to %s (FPS=%g, bin=%d)\n', out, fps, bin);
        end
        if isvalid(f3), close(f3); end

    otherwise
        error('Mode must be ''F'', ''dff'', or ''both''.');
end
end
