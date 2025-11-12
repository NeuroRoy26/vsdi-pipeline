function vsd_overlay(h5file, varargin)
% View/export fluorescence movie (F) with optional denoising and ΔF/F
% Example: vsd_overlay('data.h5', 'Mode','both', 'Bin',5, 'Out','movie.avi')
% Use 'none' for grayscale without colormap: 'ColormapF','none'

% reminder to remiove all the warning catch loops =====================

p = inputParser;
addRequired(p,'h5file',@(s)ischar(s)||isstring(s));
params = {'Dataset','functional'; 'Mode','F'; 'BaselineIdx',1:100; 'Bin',1; 'DisplayFPS',50; 
          'Sigma',0; 'MedianWin',0; 'ClipLowPct',1; 'ClipHighPct',99.9; 'Mask',[]; 'Out',''; 
          'ShowColorbar',true; 'ColormapF','gray'; 'ColormapDFF','parula'; 'IntensityLimitsF',[];
          'IntensityLimitsDFF',[]; 'UseSymmetricDFF',true; 'TransparencyThreshold',[]; 'StructuralDataset','structural';
          'StructuralAlpha',0.3; 'ShowDisplay',true; 'TrimEnd',0; 'SmoothDisplay','none'; 'ColormapAlpha',1.0};
for i = 1:size(params,1), addParameter(p, params{i,1}, params{i,2}); end
parse(p, h5file, varargin{:});

[ds, mode, pre, bin, fps, sig, mwin, clipL, clipH, mask, out, showcb, cmapF, cmapDFF, ...
 manualLimF, manualLimDFF, symDFF, transpThresh, structDS, structAlpha, showDisplay, ...
 trimEnd, smoothDisp, cmapAlpha] = deal(char(p.Results.Dataset), lower(char(p.Results.Mode)), ...
 p.Results.BaselineIdx(:)', p.Results.Bin, p.Results.DisplayFPS, p.Results.Sigma, ...
 p.Results.MedianWin, p.Results.ClipLowPct, p.Results.ClipHighPct, p.Results.Mask, ...
 char(p.Results.Out), p.Results.ShowColorbar, p.Results.ColormapF, p.Results.ColormapDFF, ...
 p.Results.IntensityLimitsF, p.Results.IntensityLimitsDFF, p.Results.UseSymmetricDFF, ...
 p.Results.TransparencyThreshold, char(p.Results.StructuralDataset), p.Results.StructuralAlpha, ...
 p.Results.ShowDisplay, p.Results.TrimEnd, lower(char(p.Results.SmoothDisplay)), p.Results.ColormapAlpha);

if trimEnd < 0
    error('TrimEnd must be >= 0');
end
if cmapAlpha < 0 || cmapAlpha > 1
    error('ColormapAlpha must be between 0 and 1');
end
if ~ismember(smoothDisp, {'none', 'nearest', 'bilinear'})
    error('SmoothDisplay must be ''none'', ''nearest'', or ''bilinear''');
end

fprintf('Reading %s /%s ...\n', h5file, ds);

if ~exist(h5file, 'file')
    error('File %s not found.', h5file);
end

try
    info = h5info(h5file);
    datasetExists = false;
    for i = 1:length(info.Datasets)
        if strcmp(info.Datasets(i).Name, ds)
            datasetExists = true;
            break;
        end
    end
    if ~datasetExists
        error('Dataset /%s not found in file %s', ds, h5file);
    end
catch ME
    error('Error reading HDF5 file info: %s', ME.message);
end

try
    F = double(h5read(h5file, ['/' ds])); 
catch ME
    error('Error reading dataset /%s from %s: %s', ds, h5file, ME.message);
end

[H,W,T] = size(F);
fprintf('Loaded functional data: %dx%dx%d (H x W x T)\n', H, W, T);

if trimEnd > 0
    if trimEnd >= T
        error('TrimEnd (%d) must be less than total frames (%d)', trimEnd, T);
    end
    F = F(:,:,1:end-trimEnd);
    T = size(F, 3);
    fprintf('Trimmed last %d frames. New frame count: %d\n', trimEnd, T);
end

structural = [];
structural_mean = [];
try
    structExists = false;
    for i = 1:length(info.Datasets)
        if strcmp(info.Datasets(i).Name, structDS)
            structExists = true;
            break;
        end
    end
    if structExists
        structural = double(h5read(h5file, ['/' structDS]));
        fprintf('Loaded structural data: %dx%dx%d\n', size(structural,1), size(structural,2), size(structural,3));
        structural_mean = mean(structural, 3);
        % Normalize structural to [0,1] for overlay
        structural_mean = (structural_mean - min(structural_mean(:))) / (max(structural_mean(:)) - min(structural_mean(:)));
    else
        fprintf('Warning: Structural dataset /%s not found. No overlay will be applied.\n', structDS);
    end
catch ME
    warning('Could not load structural data: %s. No overlay will be applied.', ME.message);
end %might remove this later on

pre = pre(pre>=1 & pre<=T); 
if isempty(pre)
    error('BaselineIdx empty after clipping to valid range [1,%d].', T); 
end

if ~isempty(mask) && ~isequal(size(mask),[H W])
    error('Mask must be %dx%d, but got %dx%d.', H, W, size(mask,1), size(mask,2)); 
end

F0 = mean(F(:,:,pre), 3);
if clipL > 0
    thrL = prctile(F0(:), clipL); 
    F0(F0 < max(thrL, eps)) = max(thrL, eps);
else
    F0(F0==0) = eps; 
end

if ~isempty(mask)
    for t = 1:T
        tmp = F(:,:,t); 
        tmp(~mask) = NaN; 
        F(:,:,t) = tmp; 
    end
    F0(~mask) = NaN;
end

if bin > 1
    nOut = floor(T/bin); 
    if nOut == 0
        error('Bin size (%d) is larger than number of frames (%d)', bin, T);
    end
    F_reshaped = F(:,:,1:nOut*bin);
    F = mean(reshape(F_reshaped, H, W, bin, nOut), 3);
    fprintf('Binned from %d to %d frames (bin=%d)\n', T, nOut, bin);
else
    nOut = T; 
end

if mwin >= 3 && mod(mwin,2)==1
    fprintf('Applying median filter (window=%d)...\n', mwin);
    for t = 1:nOut
        frame = F(:,:,t); 
        nanmask = isnan(frame); 
        frame(nanmask) = 0;
        frame = medfilt2(frame, [mwin mwin], 'symmetric'); 
        frame(nanmask) = NaN; 
        F(:,:,t) = frame;
    end
elseif mwin ~= 0
    warning('MedianWin should be odd integer >=3. Got %g. Skipping median filtering.', mwin); 
end

if sig > 0
    fprintf('Applying Gaussian filter (sigma=%g)...\n', sig);
    fsz = max(3, 2*ceil(3*sig)+1);
    for t = 1:nOut
        F(:,:,t) = imgaussfilt(F(:,:,t), sig, 'FilterSize', fsz); 
    end
end

if contains(mode,{'dff','both'})
    fprintf('Computing dF/F...\n');
    dff = (F - F0) ./ F0; 
end

if ~isempty(manualLimF)
    [Fmin, Fmax] = deal(manualLimF(1), manualLimF(2));
else
    validPixels = F(isfinite(F(:)));
    if ~isempty(validPixels)
        Fmin = prctile(validPixels, clipL);
        Fmax = prctile(validPixels, clipH);
    else
        Fmin = min(F(:),[],'omitnan');
        Fmax = max(F(:),[],'omitnan');
    end
    if ~isfinite(Fmin) || ~isfinite(Fmax) || Fmin >= Fmax
        Fmin = 0;
        Fmax = 1;
    end
end

if isempty(transpThresh) && ~isempty(manualLimF)
    transpThresh = manualLimF(1);
    fprintf('Setting transparency threshold to lower intensity limit: %.2f\n', transpThresh);
end

if exist('dff','var')
    if ~isempty(manualLimDFF)
        dffRange = manualLimDFF;
    else
        validDFF = dff(isfinite(dff(:)));
        if ~isempty(validDFF)
            if symDFF
                p = max(abs([prctile(validDFF, 99), prctile(validDFF, 1)])); 
                dffRange = [-p, p];
            else
                dffRange = [prctile(validDFF, 1), prctile(validDFF, 99)]; 
            end
        else
            dffRange = [-0.1, 0.1];
        end
        if ~isfinite(dffRange(1)) || ~isfinite(dffRange(2)) || dffRange(1) >= dffRange(2)
            dffRange = [-0.1, 0.1];
        end
    end
end

% Helper for colormap, spring winter summer works better than othrs
    function cmapMatrix = getColormapMatrix(cmap)
        if ischar(cmap) || isstring(cmap)
            switch lower(cmap)
                case 'gray'
                    cmapMatrix = gray(256);
                case 'parula'
                    cmapMatrix = parula(256);
                case 'jet'
                    cmapMatrix = jet(256);
                case 'hot'
                    cmapMatrix = hot(256);
                case 'cool'
                    cmapMatrix = cool(256);
                case 'hsv'
                    cmapMatrix = hsv(256);
                case 'winter'
                    cmapMatrix = winter(256);
                case 'spring'
                    cmapMatrix = spring(256);
                case 'summer'
                    cmapMatrix = summer(256);
                case 'autumn'
                    cmapMatrix = autumn(256);
                otherwise
                    cmapMatrix = parula(256);
            end
        else
            cmapMatrix = cmap;
        end
    end

% Helper to display transparency and overlay
    function displayFrame(ax, data, limits, cmap, frameNum, totalFrames, titleStr, useTransparency, structFrame, structAlphaVal, globalAlpha, interpMethod)
        if nargin < 8
            useTransparency = false;
        end
        if nargin < 9
            structFrame = [];
        end
        if nargin < 10
            structAlphaVal = 0.3;
        end
        if nargin < 11
            globalAlpha = 1.0;
        end
        if nargin < 12
            interpMethod = 'none';
        end
        
        if strcmpi(cmap, 'none')
            normalizedData = (data - limits(1)) / (limits(2) - limits(1));
            normalizedData(normalizedData < 0) = 0;
            normalizedData(normalizedData > 1) = 1;
            
            rgbImage = repmat(normalizedData, [1, 1, 3]);
            
            nanMask = isnan(data);
            if any(nanMask(:))
                rgbImage(repmat(nanMask, [1, 1, 3])) = 0;
            end
            
            h = imshow(rgbImage, 'Parent', ax);
            if ~strcmp(interpMethod, 'none')
                set(h, 'Interpolation', interpMethod);
            end
            axis(ax, 'image', 'off');
        else
            cla(ax);
            
            if ~isempty(structFrame)
                structRGB = repmat(structFrame, [1, 1, 3]);
                hold(ax, 'off');
                hStruct = imshow(structRGB, 'Parent', ax);
                if ~strcmp(interpMethod, 'none')
                    set(hStruct, 'Interpolation', interpMethod);
                end
                hold(ax, 'on');
            end
            
            h = imagesc(ax, data);
            set(h, 'AlphaDataMapping', 'none');
            
            if ~strcmp(interpMethod, 'none')
                set(h, 'Interpolation', interpMethod);
            end
            
            caxis(ax, limits);
            cmapMatrix = getColormapMatrix(cmap);
            colormap(ax, cmapMatrix);
            alphaChannel = ones(size(data));
            if useTransparency && ~isempty(transpThresh)
                belowThreshold = data < transpThresh;
                alphaChannel(belowThreshold) = 0;
            end
            nanMask = isnan(data);
            if any(nanMask(:))
                alphaChannel(nanMask) = 0;
            end
            
            alphaChannel = alphaChannel * globalAlpha;
            
            if ~isempty(structFrame)
                % The functional data alpha is already reduced by globalAlpha
                % The structural shows through based on 1 - alphaChannel
            end
            
            set(h, 'AlphaData', alphaChannel);
            
            axis(ax, 'image', 'off');
            hold(ax, 'off');
        end
        
        title(ax, sprintf('%s (frame %d/%d)', titleStr, frameNum, totalFrames));
    end

% remove video writer later
makeVideo = ~isempty(out);
if makeVideo
    fprintf('Setting up video writer for %s (FPS=%g)...\n', out, fps);
    
    [outPath, outName, outExt] = fileparts(out);
    
    if isempty(outExt) || ~strcmpi(outExt, '.avi')
        out = fullfile(outPath, [outName '.avi']);
        fprintf('Output format corrected to: %s\n', out);
    end
    
    try
        v = VideoWriter(out, 'Motion JPEG AVI'); 
        v.FrameRate = fps; 
        v.Quality = 95;
        open(v); 
    catch ME
        warning('Could not create video writer: %s', ME.message);
        makeVideo = false;
    end
end

fprintf('Displaying movie (mode=%s)...\n', mode);
if ~strcmp(smoothDisp, 'none')
    fprintf('Using %s interpolation for smoother display\n', smoothDisp);
end

if showDisplay || makeVideo
    switch mode
        case 'f'
            fig = figure('Color','w','Position',[100 100 740 760]); 
            if ~showDisplay
                set(fig, 'Visible', 'off');
            end
            ax = axes('Parent', fig);
            
            for k = 1:nOut
                displayFrame(ax, F(:,:,k), [Fmin Fmax], cmapF, k, nOut, 'Fluorescence F', ...
                             ~isempty(transpThresh), structural_mean, structAlpha, cmapAlpha, smoothDisp);
                
                if showcb && ~strcmpi(cmapF, 'none')
                    colorbar(ax);
                end
                
                if showDisplay
                    drawnow;
                    pause(0.001); % maybe implement real-time delay (1/fs)
                end
                
                if makeVideo
                    try
                        writeVideo(v, getframe(fig)); 
                    catch ME
                        warning('Error writing frame %d: %s', k, ME.message);
                    end
                end
            end
            
        case 'dff'
            if ~exist('dff', 'var')
                error('dF/F data not computed. This should not happen.');
            end
            fig = figure('Color','w','Position',[100 100 740 760]); 
            if ~showDisplay
                set(fig, 'Visible', 'off');
            end
            ax = axes('Parent', fig);
            
            for k = 1:nOut
                displayFrame(ax, dff(:,:,k), dffRange, cmapDFF, k, nOut, '\DeltaF/F', ...
                             false, structural_mean, structAlpha, cmapAlpha, smoothDisp);
                
                if showcb && ~strcmpi(cmapDFF, 'none')
                    colorbar(ax);
                end
                
                if showDisplay
                    drawnow;
                    pause(0.001); 
                end
                
                if makeVideo
                    try
                        writeVideo(v, getframe(fig)); 
                    catch ME
                        warning('Error writing frame %d: %s', k, ME.message);
                    end
                end
            end
            
        case 'both'
            if ~exist('dff', 'var')
                error('dF/F data not computed. This should not happen.');
            end
            fig = figure('Color','w','Position',[100 100 1280 640]);
            if ~showDisplay
                set(fig, 'Visible', 'off');
            end
            axF = subplot(1,2,1, 'Parent', fig);
            axDFF = subplot(1,2,2, 'Parent', fig);
            
            for k = 1:nOut
                displayFrame(axF, F(:,:,k), [Fmin Fmax], cmapF, k, nOut, 'F', ...
                             ~isempty(transpThresh), structural_mean, structAlpha, cmapAlpha, smoothDisp);
                displayFrame(axDFF, dff(:,:,k), dffRange, cmapDFF, k, nOut, '\DeltaF/F', ...
                             false, structural_mean, structAlpha, cmapAlpha, smoothDisp);
                
                if showcb
                    if ~strcmpi(cmapF, 'none')
                        colorbar(axF);
                    end
                    if ~strcmpi(cmapDFF, 'none')
                        colorbar(axDFF);
                    end
                end
                
                if showDisplay
                    drawnow;
                    pause(0.001); 
                end
                
                if makeVideo
                    try
                        writeVideo(v, getframe(fig)); 
                    catch ME
                        warning('Error writing frame %d: %s', k, ME.message);
                    end
                end
            end
            
        otherwise
            error('Mode must be ''F'', ''dff'', or ''both''. Got ''%s''.', mode);
    end
    
    if exist('fig','var') && isvalid(fig) && ishandle(fig)
        close(fig); 
    end
else
    fprintf('Display suppressed (ShowDisplay=false and no video output).\n');
end

if makeVideo && exist('v', 'var') && isvalid(v)
    try
        close(v); 
        fprintf('Saved movie to %s (FPS=%g, bin=%d)\n', out, fps, bin); 
    catch ME
        warning('Error closing video: %s', ME.message);
    end
end

fprintf('Function completed successfully.\n');
end