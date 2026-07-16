function inspect_frames_gui()
% inspect_frames_gui.m
% Simple interactive frame inspector: raw dF/F, 3x mask, 4x mask, overlay
%
% Usage:
%   Run in the folder with the same data paths as diagnostics script.
%   Drag the slider to step through frames, or use left/right arrow keys.
% simply type inspect_frames_gui in the command window to run this gui
clearvars; close all; clc;
dff_file    = 'data/averaged_movie_E0B0-B3_unbinned.h5';
dff_dataset = '/functional_dff';
mask3_file  = 'data/activation_mask_3x.h5';
mask4_file  = 'data/activation_mask_4x.h5';
mask_dataset = '/activation_mask';

% Load
dff = h5read(dff_file, dff_dataset);
mask3 = logical(h5read(mask3_file, mask_dataset));
mask4 = logical(h5read(mask4_file, mask_dataset));
[H,W,T] = size(dff);

% Figure
hfig = figure('Name','Frame Inspector','NumberTitle','off','Position',[100 100 1400 700]);
ax1 = subplot(2,3,1);
hIm1 = imagesc(dff(:,:,1)); axis image; colormap(ax1,'jet'); colorbar;
title('dF/F');

ax2 = subplot(2,3,2);
hIm2 = imagesc(mask3(:,:,1)); axis image; colormap(ax2,'gray');
title('3x mask');

ax3 = subplot(2,3,3);
hIm3 = imagesc(mask4(:,:,1)); axis image; colormap(ax3,'gray');
title('4x mask');

ax4 = subplot(2,3,4:6);
overlay = cat(3, normalize_image(dff(:,:,1)), normalize_image(dff(:,:,1)), zeros(H,W));
overlay(repmat(mask3(:,:,1),[1 1 3])) = 0; % show masks overlayed differently below
hIm4 = imshow(overlay);
title('Overlay (red=signal; green=3x mask; blue=4x mask)');
hold on;
h3 = plot(nan,nan,'g.','MarkerSize',6);
h4 = plot(nan,nan,'b.','MarkerSize',6);
hold off;

% slider
sld = uicontrol('Style','slider','Min',1,'Max',T,'Value',1,'Position',[200 10 1000 20],...
    'Callback',@sld_callback);

% key press navigation
set(hfig,'KeyPressFcn',@keynav);

% initial update
update_frame(1);

fprintf('Frame inspector ready (frames 1-%d). Use slider or arrow keys.\n', T);

    function update_frame(f)
        f = round(max(1,min(T,f)));
        set(hIm1,'CData',dff(:,:,f));
        title(ax1, sprintf('dF/F - Frame %d  Min %.6f Max %.6f', f, min(dff(:,:,f),[],'all'), max(dff(:,:,f),[],'all')));
        
        set(hIm2,'CData',mask3(:,:,f));
        title(ax2, sprintf('3x mask - %d pixels', sum(mask3(:,:,f),'all')));
        
        set(hIm3,'CData',mask4(:,:,f));
        title(ax3, sprintf('4x mask - %d pixels', sum(mask4(:,:,f),'all')));
        
        % overlay: signal as red channel, mask3 as green dots, mask4 as blue dots
        img_norm = normalize_image(dff(:,:,f));
        overlay = cat(3, img_norm, img_norm, zeros(H,W));
        set(hIm4,'CData', overlay);
        
        % update scatter
        [y3,x3] = find(mask3(:,:,f));
        [y4,x4] = find(mask4(:,:,f));
        set(h3, 'XData', x3, 'YData', y3);
        set(h4, 'XData', x4, 'YData', y4);
        
        drawnow;
        set(sld,'Value',f);
    end

    function sld_callback(src,~)
        val = round(get(src,'Value'));
        update_frame(val);
    end

    function keynav(~, event)
        cur = round(get(sld,'Value'));
        switch event.Key
            case 'rightarrow'
                update_frame(min(T,cur+1));
            case 'leftarrow'
                update_frame(max(1,cur-1));
            case 'space'
                fprintf('Current frame %d\n', cur);
        end
    end

    function out = normalize_image(in)
        in = double(in);
        mn = min(in(:)); mx = max(in(:));
        if mx>mn
            out = (in - mn) / (mx-mn);
        else
            out = zeros(size(in));
        end
    end
end