function vsd_fluorescence(h5file, varargin)
% View/export fluorescence movie (F) with optional denoising and ΔF/F
% Example: vsd_fluorescence('data.h5', 'Mode','both', 'Bin',5, 'Out','movie.mp4')
% Use 'none' for grayscale without colormap: 'ColormapF','none'

% Parse inputs with compact validation
p = inputParser;
addRequired(p,'h5file',@(s)ischar(s)||isstring(s));
params = {'Dataset','functional'; 'Mode','F'; 'BaselineIdx',1:100; 'Bin',1; 'DisplayFPS',50; 
          'Sigma',0; 'MedianWin',0; 'ClipLowPct',1; 'ClipHighPct',99.9; 'Mask',[]; 'Out',''; 
          'ShowColorbar',true; 'ColormapF','gray'; 'ColormapDFF','parula'; 'IntensityLimitsF',[];
          'IntensityLimitsDFF',[]; 'UseSymmetricDFF',true};
for i = 1:size(params,1), addParameter(p, params{i,1}, params{i,2}); end
parse(p, h5file, varargin{:});

% Extract parameters
[ds, mode, pre, bin, fps, sig, mwin, clipL, clipH, mask, out, showcb, cmapF, cmapDFF, ...
 manualLimF, manualLimDFF, symDFF] = deal(char(p.Results.Dataset), lower(char(p.Results.Mode)), ...
 p.Results.BaselineIdx(:)', p.Results.Bin, p.Results.DisplayFPS, p.Results.Sigma, ...
 p.Results.MedianWin, p.Results.ClipLowPct, p.Results.ClipHighPct, p.Results.Mask, ...
 char(p.Results.Out), p.Results.ShowColorbar, p.Results.ColormapF, p.Results.ColormapDFF, ...
 p.Results.IntensityLimitsF, p.Results.IntensityLimitsDFF, p.Results.UseSymmetricDFF);

% Load and process data
fprintf('Reading %s /%s ...\n', h5file, ds);

% Check if file exists
if ~exist(h5file, 'file')
    error('File %s not found.', h5file);
end

% Check if dataset exists in HDF5 file
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

% Load data with error handling
try
    F = double(h5read(h5file, ['/' ds])); 
catch ME
    error('Error reading dataset /%s from %s: %s', ds, h5file, ME.message);
end

[H,W,T] = size(F);
fprintf('Loaded data: %dx%dx%d (H x W x T)\n', H, W, T);

% Validate baseline indices
pre = pre(pre>=1 & pre<=T); 
if isempty(pre)
    error('BaselineIdx empty after clipping to valid range [1,%d].', T); 
end

% Validate mask dimensions
if ~isempty(mask) && ~isequal(size(mask),[H W])
    error('Mask must be %dx%d, but got %dx%d.', H, W, size(mask,1), size(mask,2)); 
end

% Build robust baseline F0
F0 = mean(F(:,:,pre), 3);
if clipL > 0
    thrL = prctile(F0(:), clipL); 
    F0(F0 < max(thrL, eps)) = max(thrL, eps);
else
    F0(F0==0) = eps; 
end

% Apply mask if provided
if ~isempty(mask)
    for t = 1:T
        tmp = F(:,:,t); 
        tmp(~mask) = NaN; 
        F(:,:,t) = tmp; 
    end
    F0(~mask) = NaN;
end

% Temporal binning and spatial denoising
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

% Median filtering with proper validation
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

% Gaussian filtering
if sig > 0
    fprintf('Applying Gaussian filter (sigma=%g)...\n', sig);
    fsz = max(3, 2*ceil(3*sig)+1);
    for t = 1:nOut
        F(:,:,t) = imgaussfilt(F(:,:,t), sig, 'FilterSize', fsz); 
    end
end

% Calculate dF/F if needed
if contains(mode,{'dff','both'})
    fprintf('Computing dF/F...\n');
    dff = (F - F0) ./ F0; 
end

% Set intensity limits for F - COMPUTE ONCE FOR ALL FRAMES
if ~isempty(manualLimF)
    [Fmin, Fmax] = deal(manualLimF(1), manualLimF(2));
else
    % Use all frames for consistent scaling
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

% Set intensity limits for dF/F - COMPUTE ONCE FOR ALL FRAMES
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
        % Ensure valid range
        if ~isfinite(dffRange(1)) || ~isfinite(dffRange(2)) || dffRange(1) >= dffRange(2)
            dffRange = [-0.1, 0.1];
        end
    end
end

% Helper function for colormap - UPDATED TO HANDLE 'none'
    function setCmap(ax, cmap, useGrayscale)
        if nargin < 3
            useGrayscale = false;
        end
        
        if strcmpi(cmap, 'none') || useGrayscale
            % No colormap - will use direct grayscale display
            return;
        end
        
        try
            if ischar(cmap) || isstring(cmap)
                switch lower(cmap)
                    case 'gray'
                        colormap(ax, gray(256));
                    case 'parula'
                        colormap(ax, parula(256));
                    case 'jet'
                        colormap(ax, jet(256));
                    case 'hot'
                        colormap(ax, hot(256));
                    case 'cool'
                        colormap(ax, cool(256));
                    case 'hsv'
                        colormap(ax, hsv(256));
                    otherwise
                        colormap(ax, parula(256));
                end
            else
                colormap(ax, cmap);
            end
        catch
            colormap(ax, parula(256));
        end
    end

% Helper function to display frame - NEW FUNCTION FOR CONSISTENT DISPLAY
    function displayFrame(ax, data, limits, cmap, frameNum, totalFrames, titleStr)
        if strcmpi(cmap, 'none')
            % Direct grayscale display without colormap
            % Normalize to [0,1] for grayscale
            normalizedData = (data - limits(1)) / (limits(2) - limits(1));
            normalizedData(normalizedData < 0) = 0;
            normalizedData(normalizedData > 1) = 1;
            
            % Convert to RGB grayscale (same value for R,G,B)
            rgbImage = repmat(normalizedData, [1, 1, 3]);
            
            % Handle NaN values (show as black or white)
            nanMask = isnan(data);
            if any(nanMask(:))
                rgbImage(repmat(nanMask, [1, 1, 3])) = 0; % Black for NaN
            end
            
            % Display as RGB image
            image(ax, rgbImage);
            axis(ax, 'image', 'off');
        else
            % Standard colormap display
            imagesc(ax, data, limits);
            axis(ax, 'image', 'off');
            setCmap(ax, cmap);
        end
        
        title(ax, sprintf('%s (frame %d/%d)', titleStr, frameNum, totalFrames));
    end

% Create video writer if needed
makeVideo = ~isempty(out);
if makeVideo
    fprintf('Setting up video writer for %s (FPS=%g)...\n', out, fps);
    try
        v = VideoWriter(out, 'MPEG-4'); 
        v.FrameRate = fps; 
        v.Quality = 95;  % Higher quality to reduce compression artifacts
        open(v); 
    catch ME
        warning('Could not create video writer: %s', ME.message);
        makeVideo = false;
    end
end

% Display based on mode
fprintf('Displaying movie (mode=%s)...\n', mode);
switch mode
    case 'f'
        fig = figure('Color','w','Position',[100 100 740 760]); 
        ax = axes('Parent', fig);
        
        % Set up colormap once if not 'none'
        if ~strcmpi(cmapF, 'none')
            setCmap(ax, cmapF);
            % Fix color limits for entire movie
            caxis(ax, [Fmin Fmax]);
        end
        
        for k = 1:nOut
            displayFrame(ax, F(:,:,k), [Fmin Fmax], cmapF, k, nOut, 'Fluorescence F');
            
            if showcb && ~strcmpi(cmapF, 'none')
                colorbar(ax);
            end
            
            drawnow;
            
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
        ax = axes('Parent', fig);
        
        % Set up colormap once if not 'none'
        if ~strcmpi(cmapDFF, 'none')
            setCmap(ax, cmapDFF);
            % Fix color limits for entire movie
            caxis(ax, dffRange);
        end
        
        for k = 1:nOut
            displayFrame(ax, dff(:,:,k), dffRange, cmapDFF, k, nOut, '\DeltaF/F');
            
            if showcb && ~strcmpi(cmapDFF, 'none')
                colorbar(ax);
            end
            
            drawnow;
            
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
        axF = subplot(1,2,1, 'Parent', fig);
        axDFF = subplot(1,2,2, 'Parent', fig);
        
        % Set up colormaps once if not 'none'
        if ~strcmpi(cmapF, 'none')
            setCmap(axF, cmapF);
            caxis(axF, [Fmin Fmax]);
        end
        if ~strcmpi(cmapDFF, 'none')
            setCmap(axDFF, cmapDFF);
            caxis(axDFF, dffRange);
        end
        
        for k = 1:nOut
            displayFrame(axF, F(:,:,k), [Fmin Fmax], cmapF, k, nOut, 'F');
            displayFrame(axDFF, dff(:,:,k), dffRange, cmapDFF, k, nOut, '\DeltaF/F');
            
            if showcb
                if ~strcmpi(cmapF, 'none')
                    colorbar(axF);
                end
                if ~strcmpi(cmapDFF, 'none')
                    colorbar(axDFF);
                end
            end
            
            drawnow;
            
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

% Clean up
if makeVideo && exist('v', 'var') && isvalid(v)
    try
        close(v); 
        fprintf('Saved movie to %s (FPS=%g, bin=%d)\n', out, fps, bin); 
    catch ME
        warning('Error closing video: %s', ME.message);
    end
end

if exist('fig','var') && isvalid(fig) && ishandle(fig)
    close(fig); 
end

fprintf('Function completed successfully.\n');
end