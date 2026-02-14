% analysis_Step2_DirectAccess_Final.m
% Same as analysis_Step2.m script but concatenated
% INTERACTIVE VIEWER: DIRECT DISK ACCESS + KEYBOARD NAVIGATION
% 
% FEATURES:
%   - Zero Stutter: Reads directly from disk using 'matfile'.
%   - Keyboard Nav: Use Arrow Keys (Left/Right) to step frames.
%   - Click-to-Seek: Click on the trace to jump to that time.
%
clear; clc; close all;

%% ======================== INITIALIZATION ========================
SUMMARY_FILE = 'All_Experiments_Summary.mat';

if ~exist(SUMMARY_FILE, 'file')
    errordlg(['Summary file not found! Run Step 1 first.'], 'Error');
    return;
end

fprintf('Loading summary: %s...\n', SUMMARY_FILE);
loaded_data = load(SUMMARY_FILE);
All_Experiments = loaded_data.All_Experiments;

if isfield(loaded_data, 'Concatenated_Recording')
    Concat = loaded_data.Concatenated_Recording;
    has_concat = true;
    fprintf('✓ Found Concatenated Recording (%d files)\n', Concat.num_files);
else
    has_concat = false;
    Concat = [];
end

%% ======================== MAIN GUI ========================
f = figure('Name', 'Batch Sweep Viewer (Direct Access)', ...
           'Position', [50, 50, 1400, 800], 'Color', 'w', ...
           'MenuBar', 'none', 'NumberTitle', 'off');

% --- LEFT PANEL: List ---
panel_left = uipanel('Parent', f, 'Position', [0.01, 0.02, 0.18, 0.96], ...
                     'Title', 'Files', 'BackgroundColor', 'w');

list_items = {};
if has_concat
    list_items{1} = '🔗 CONCATENATED VIEW';
    offset = 1;
else
    offset = 0;
end
for i = 1:length(All_Experiments)
    list_items{i+offset} = All_Experiments(i).filename;
end

lst_box = uicontrol('Parent', panel_left, 'Style', 'listbox', ...
                    'Units', 'normalized', 'Position', [0.05, 0.20, 0.9, 0.75], ...
                    'String', list_items, 'FontSize', 10, ...
                    'Callback', @updateView);

txt_info = uicontrol('Parent', panel_left, 'Style', 'text', ...
                     'Units', 'normalized', 'Position', [0.05, 0.02, 0.9, 0.15], ...
                     'String', 'Select a file...', 'HorizontalAlignment', 'left', ...
                     'BackgroundColor', 'w', 'FontSize', 9);

% --- RIGHT PANEL: Visualization ---
panel_right = uipanel('Parent', f, 'Position', [0.20, 0.02, 0.79, 0.96], ...
                      'Title', 'Preview', 'BackgroundColor', 'w');

ax_trace = axes('Parent', panel_right, 'Position', [0.08, 0.40, 0.88, 0.55]); 
xlabel('Time (s)'); ylabel('Z-Score / dF/F'); grid on; title('Trace Preview');

ax_img = axes('Parent', panel_right, 'Position', [0.72, 0.05, 0.24, 0.30]); 
axis off; title('Preview Map');

btn_load = uicontrol('Parent', panel_right, 'Style', 'pushbutton', ...
                     'String', 'OPEN ANALYZER', ...
                     'Units', 'normalized', 'Position', [0.45, 0.15, 0.25, 0.10], ...
                     'FontSize', 11, 'FontWeight', 'bold', ...
                     'BackgroundColor', [0.2, 0.6, 1], 'ForegroundColor', 'w', ...
                     'Callback', @loadAnalyzer);

% Store Data
gui_data = struct();
gui_data.All = All_Experiments;
gui_data.Concat = Concat;
gui_data.has_concat = has_concat;
gui_data.ax_trace = ax_trace;
gui_data.ax_img = ax_img;
gui_data.txt_info = txt_info;
gui_data.curr_idx = 1;
guidata(f, gui_data);

updateView(lst_box, []);

%% ======================== CALLBACKS ========================
function updateView(src, ~)
    fig = ancestor(src, 'figure');
    G = guidata(fig);
    val = get(src, 'Value');
    
    if G.has_concat && val == 1
        % CONCATENATED PREVIEW
        S = G.Concat;
        G.curr_idx = 0; 
        
        axes(G.ax_trace); cla;
        plot(S.time_axis, S.trace, 'k-', 'LineWidth', 1); hold on;
        for k = 1:length(S.file_segments)
            seg = S.file_segments(k);
            x = S.time_axis(seg.start_frame);
            xline(x, 'r--', 'LineWidth', 1);
        end
        axis tight; grid on;
        title(sprintf('Concatenated: %d Files, %.1f sec', S.num_files, S.time_axis(end)));
        axes(G.ax_img); cla; axis off;
        text(0.5, 0.5, 'Virtual View', 'HorizontalAlignment', 'center');
    else
        % INDIVIDUAL PREVIEW
        if G.has_concat, real_idx = val - 1; else, real_idx = val; end
        S = G.All(real_idx);
        G.curr_idx = real_idx;
        
        axes(G.ax_trace); cla;
        plot(S.time_axis, S.trace, 'b-'); axis tight; grid on;
        title(S.filename, 'Interpreter', 'none');
        axes(G.ax_img); cla;
        if isfield(S, 'preview_img') && ~isempty(S.preview_img)
            imagesc(S.preview_img); axis image off; colormap jet;
        end
    end
    guidata(fig, G);
end

function loadAnalyzer(src, ~)
    fig = ancestor(src, 'figure');
    G = guidata(fig);
    
    if G.curr_idx == 0
        createDirectAnalyzer(G.Concat, G.All);
    else
        idx = G.curr_idx;
        fname = G.All(idx).filename;
        fpath = fullfile(G.All(idx).folder, fname);
        
        % Use matfile even for single files for consistency/speed
        m = matfile(fpath);
        createStandardAnalyzer(m, G.All(idx));
    end
end

%% ======================== DIRECT ACCESS ANALYZER ========================
function createDirectAnalyzer(Concat, All_Exps)
    h = figure('Name', 'Virtual Analyzer (Direct Access)', 'Position', [100, 100, 1200, 800], ...
               'Color', 'w', 'NumberTitle', 'off', 'MenuBar', 'none');
    
    % Initialize Data
    D = struct();
    D.Concat = Concat;
    D.All_Exps = All_Exps;
    D.curr_global_frame = 1;
    D.total_frames = Concat.total_frames;
    D.trace = Concat.trace;
    D.time = Concat.time_axis;
    
    % --- MATFILE CACHE ---
    D.FileMaps = cell(Concat.num_files, 1);
    fprintf('Mapping files for direct access...\n');
    for k = 1:Concat.num_files
        seg = Concat.file_segments(k);
        file_info = All_Exps(seg.file_index);
        full_path = fullfile(file_info.folder, file_info.filename);
        D.FileMaps{k} = matfile(full_path);
    end

    % --- UI SETUP ---
    D.ax_trace = subplot(4, 1, 1);
    plot(D.time, D.trace, 'k-', 'LineWidth', 1); hold on;
    for k = 1:length(Concat.file_segments)
        x = D.time(Concat.file_segments(k).start_frame);
        xline(x, 'r-');
    end
    D.xline = xline(D.time(1), 'b-', 'LineWidth', 2);
    title('Trace (Arrow Keys to Navigate)');
    xlabel('Time (s)'); axis tight;
    set(D.ax_trace, 'ButtonDownFcn', @(s,e) traceClick(s,e,h));

    D.ax_movie = subplot(4, 1, [2, 3, 4]);
    D.img_h = imagesc(zeros(512, 512));
    axis image off; colormap jet; colorbar;
    D.title_h = title('Initializing...');
    
    % --- NEW FILTERS PANEL ---
    panel_filt = uipanel('Parent', h, 'Title', '2D Spatial Filters', ...
                         'Position', [0.75, 0.02, 0.20, 0.12], 'BackgroundColor', 'w');
                     
    D.chk_blur = uicontrol('Parent', panel_filt, 'Style', 'checkbox', ...
                           'String', 'Spatial Blur (Denoise)', ...
                           'Units', 'normalized', 'Position', [0.1, 0.6, 0.8, 0.3], ...
                           'BackgroundColor', 'w', 'Callback', @(s,e) updateFrameDisplay(h, D.curr_global_frame));
                       
    % D.chk_thresh = uicontrol('Parent', panel_filt, 'Style', 'checkbox', ...
    %                          'String', 'Hide Weak Signals (<0.5 SD)', ...
    %                          'Units', 'normalized', 'Position', [0.1, 0.2, 0.8, 0.3], ...
    %                          'BackgroundColor', 'w', 'Callback', @(s,e) updateFrameDisplay(h, D.curr_global_frame));

    % Slider
    D.slider = uicontrol('Style', 'slider', 'Min', 1, 'Max', D.total_frames, ...
                         'Value', 1, 'Units', 'normalized', ...
                         'Position', [0.1, 0.02, 0.6, 0.03], ...
                         'Callback', @(s,e) sliderMove(s,e,h));
    
    % Store data and update
    guidata(h, D);
    updateFrameDisplay(h, 1);
    set(h, 'KeyPressFcn', @(s,e) keyPressHandler(s,e,h));
end

function updateFrameDisplay(h, global_frame_idx)
    D = guidata(h);
    
    % Validate bounds
    global_frame_idx = max(1, min(round(global_frame_idx), D.total_frames));
    
    % 1. Find which file this frame belongs to
    seg_idx = find([D.Concat.file_segments.start_frame] <= global_frame_idx & ...
                   [D.Concat.file_segments.end_frame] >= global_frame_idx, 1);
    
    if isempty(seg_idx), return; end
    seg = D.Concat.file_segments(seg_idx);
    
    % 2. DIRECT DISK READ
    local_frame = global_frame_idx - seg.start_frame + 1;
    m = D.FileMaps{seg_idx};
    
    try
        frame_data = m.reconstructed_movie(:,:,local_frame);
        
        % Polarity check
        if isfield(seg, 'polarity') && strcmp(seg.polarity, 'FLIPPED')
            frame_data = -frame_data;
        end
        
        % --- APPLY 2D SPATIAL FILTERS ON THE FLY ---
        
        % Filter 1: Spatial Blur (Low-Pass)
        % This removes single-pixel "salt and pepper" noise
        if get(D.chk_blur, 'Value')
            % Sigma=1.5 is usually a sweet spot for 512x512 images
            frame_data = imgaussfilt(frame_data, 1.5); 
        end
        
        % % Filter 2: Noise Thresholding (Morphological-ish)
        % % This hides any pixel that is effectively "background noise"
        % if get(D.chk_thresh, 'Value')
        %     % Assuming data is Z-Scored or dF/F. 
        %     % We hide anything below 1.0 (weak signal) to see only strong events
        %     frame_data(frame_data < 0.1) = 0; 
        % end
        
        set(D.img_h, 'CData', frame_data);
        
    catch ME
        title(sprintf('Read Error: %s', ME.message)); return;
    end
    
    % 3. Update UI
    set(D.xline, 'Value', D.time(global_frame_idx));
    set(D.title_h, 'String', sprintf('Time: %.3fs | File %d/%d (%s)', ...
        D.time(global_frame_idx), seg_idx, D.Concat.num_files, seg.filename));
    set(D.slider, 'Value', global_frame_idx);
    
    D.curr_global_frame = global_frame_idx;
    guidata(h, D);
end

function sliderMove(src, ~, h)
    val = round(get(src, 'Value'));
    updateFrameDisplay(h, val);
end

function traceClick(~, event, h)
    D = guidata(h);
    t_click = event.IntersectionPoint(1);
    [~, frame_idx] = min(abs(D.time - t_click));
    updateFrameDisplay(h, frame_idx);
end

function keyPressHandler(~, event, h)
    D = guidata(h);
    current = D.curr_global_frame;
    
    switch event.Key
        case 'rightarrow'
            target = current + 1;
        case 'leftarrow'
            target = current - 1;
        case 'uparrow'
            target = current + 10;
        case 'downarrow'
            target = current - 10;
        otherwise
            return; % Ignore other keys
    end
    
    % Update display (function handles boundary checks)
    updateFrameDisplay(h, target);
end

%% ======================== STANDARD ANALYZER (Single File) ========================
function createStandardAnalyzer(mObj, Meta)
    h = figure('Name', Meta.filename, 'Position', [150, 150, 1000, 700], ...
               'Color', 'w', 'MenuBar', 'none');
    
    % Data storage for standard viewer
    D = struct();
    D.mObj = mObj;
    D.Meta = Meta;
    [~,~,frames] = size(mObj, 'reconstructed_movie');
    D.total_frames = frames;
    D.curr_global_frame = 1;
    D.is_single = true;

    subplot(4,1,1); 
    D.trace_h = plot(Meta.time_axis, Meta.trace, 'b-'); 
    D.xline = xline(Meta.time_axis(1), 'r-');
    axis tight; title('Trace (Arrow Keys Enabled)');
    
    subplot(4,1,[2,3,4]);
    frame1 = mObj.reconstructed_movie(:,:,1);
    D.img_h = imagesc(frame1); axis image off; colormap jet; colorbar;
    D.title_h = title('Frame 1');
    
    D.slider = uicontrol('Style', 'slider', 'Min', 1, 'Max', frames, 'Value', 1, ...
                       'Units', 'normalized', 'Position', [0.1, 0.02, 0.8, 0.03], ...
                       'Callback', @(s,e) singleFileUpdate(s,e,h));
                   
    guidata(h, D);
    set(h, 'KeyPressFcn', @(s,e) singleFileKeyHandler(s,e,h));
end

function singleFileUpdate(src, ~, h)
    D = guidata(h);
    f = round(get(src, 'Value'));
    
    % Read direct
    frame_data = D.mObj.reconstructed_movie(:,:,f);
    
    set(D.img_h, 'CData', frame_data);
    set(D.title_h, 'String', sprintf('Frame %d (%.2f s)', f, D.Meta.time_axis(f)));
    set(D.xline, 'Value', D.Meta.time_axis(f));
    
    D.curr_global_frame = f;
    guidata(h, D);
end

function singleFileKeyHandler(~, event, h)
    D = guidata(h);
    current = D.curr_global_frame;
    
    switch event.Key
        case 'rightarrow', target = current + 1;
        case 'leftarrow', target = current - 1;
        case 'uparrow', target = current + 10;
        case 'downarrow', target = current - 10;
        otherwise, return;
    end
    
    target = max(1, min(target, D.total_frames));
    set(D.slider, 'Value', target);
    singleFileUpdate(D.slider, [], h);
end