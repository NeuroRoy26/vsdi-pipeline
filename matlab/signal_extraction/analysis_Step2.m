% analysis_Step2.m
% INTERACTIVE VIEWER: Batch Experiment Browser & Movie Analyzer
% WITH POSITIVE-ONLY RECTIFICATION PATCH
clear; clc; close all;

%% ======================== INITIALIZATION ========================
SUMMARY_FILE = 'All_Experiments_Summary.mat';
if ~exist(SUMMARY_FILE, 'file')
    error(['Summary file not found!\n' ...
           'Please run analysis_Step1.m first to generate: %s'], SUMMARY_FILE);
end
fprintf('Loading sweeps summary...\n');
load(SUMMARY_FILE, 'All_Experiments');
num_experiments = length(All_Experiments);
fprintf('✓ Loaded %d sweep(s)\n\n', num_experiments);

%% ======================== MAIN GUI CREATION ========================
f = figure('Name', 'Batch Sweep Viewer', ...
           'Position', [50, 50, 1400, 800], ...
           'Color', 'w', ...
           'MenuBar', 'none', ...
           'NumberTitle', 'off', ...
           'Resize', 'on');

%% --- LEFT PANEL: File List & Info ---
panel_left = uipanel('Parent', f, ...
                     'Position', [0.01, 0.02, 0.18, 0.96], ...
                     'Title', 'Sweeps', ...
                     'FontWeight', 'bold', ...
                     'BackgroundColor', 'w');

uicontrol('Parent', panel_left, 'Style', 'text', ...
          'Units', 'normalized', 'Position', [0.05, 0.92, 0.9, 0.05], ...
          'String', sprintf('Total: %d files', num_experiments), ...
          'HorizontalAlignment', 'left', 'FontWeight', 'bold', 'BackgroundColor', 'w');

file_list = {All_Experiments.filename};
lst_box = uicontrol('Parent', panel_left, 'Style', 'listbox', ...
                    'Units', 'normalized', 'Position', [0.05, 0.50, 0.9, 0.40], ...
                    'String', file_list, 'FontName', 'Consolas', 'FontSize', 9, ...
                    'Callback', @updateView);

txt_info = uicontrol('Parent', panel_left, 'Style', 'text', ...
                     'Units', 'normalized', 'Position', [0.05, 0.02, 0.9, 0.25], ...
                     'String', 'Select an experiment...', ...
                     'HorizontalAlignment', 'left', ...
                     'BackgroundColor', [0.95, 0.95, 0.95], ...
                     'FontName', 'Consolas', 'FontSize', 9);

btn_flip = uicontrol('Parent', panel_left, ...
                     'Style', 'pushbutton', ...
                     'Units', 'normalized', ...
                     'Position', [0.05, 0.40, 0.9, 0.06], ...
                     'String', 'GLOBAL POLARITY FLIP', ...
                     'FontSize', 9, ...
                     'FontWeight', 'bold', ...
                     'BackgroundColor', [0.9, 0.5, 0.3], ...
                     'ForegroundColor', 'w', ...
                     'Callback', @flipPolarityCallback, ...
                     'TooltipString', 'Permanently flips BOTH trace and movie data');

btn_flip_trace = uicontrol('Parent', panel_left, ...
                     'Style', 'pushbutton', ...
                     'Units', 'normalized', ...
                     'Position', [0.05, 0.32, 0.9, 0.06], ...
                     'String', 'FLIP TRACE ONLY', ...
                     'FontSize', 9, ...
                     'FontWeight', 'bold', ...
                     'BackgroundColor', [0.6, 0.6, 0.9], ...
                     'ForegroundColor', 'w', ...
                     'Callback', @flipTraceOnlyMainCallback, ...
                     'TooltipString', 'Permanently flips ONLY the 1D trace (Movie remains unchanged)');

%% --- RIGHT PANEL: Visualization ---
panel_right = uipanel('Parent', f, ...
                      'Position', [0.20, 0.02, 0.79, 0.96], ...
                      'Title', 'Signal Visualization', ...
                      'FontWeight', 'bold', ...
                      'BackgroundColor', 'w');

ax_trace = axes('Parent', panel_right, ...
                'Position', [0.08, 0.40, 0.88, 0.55]); 
title('1D Trace'); 
xlabel('Time (s)'); 
ylabel('ΔF/F (a.u.)');
grid on; box on;

ax_img = axes('Parent', panel_right, ...
              'Position', [0.72, 0.05, 0.24, 0.30]); 
axis off; 
title('Preview');

btn_load = uicontrol('Parent', panel_right, ...
                     'Style', 'pushbutton', ...
                     'Units', 'normalized', ...
                     'Position', [0.45, 0.15, 0.25, 0.10], ...
                     'String', 'OPEN ANALYZER', ...
                     'FontSize', 10, ...
                     'FontWeight', 'bold', ...
                     'BackgroundColor', [0.3, 0.7, 0.9], ...
                     'ForegroundColor', 'w', ...
                     'Callback', @loadFullMovieAnalyzer);

%% --- STORE GUI DATA ---
gui_data = struct();
gui_data.all_data = All_Experiments;
gui_data.ax_trace = ax_trace;
gui_data.ax_img = ax_img;
gui_data.txt_info = txt_info;
gui_data.current_idx = 1;
gui_data.summary_file = SUMMARY_FILE;
gui_data.lst_box = lst_box;

guidata(f, gui_data);
set(lst_box, 'Value', 1);
updateView(lst_box, []);

fprintf('✓ Viewer ready. Select a sweep to begin.\n');

%% ======================== CALLBACK FUNCTIONS ========================

function updateView(src, ~)
    fig = ancestor(src, 'figure');
    G = guidata(fig);
    idx = get(src, 'Value');
    
    if idx > length(G.all_data), return; end
    
    S = G.all_data(idx);
    G.current_idx = idx;
    
    axes(G.ax_trace); cla;
    plot(S.time_axis, S.trace, 'k-', 'LineWidth', 1.2); 
    hold on; grid on; box on; axis tight;
    
    status_msg = '';
    if isfield(S, 'polarity_flipped') && S.polarity_flipped
        status_msg = [status_msg ' [Global Flip]'];
    end
    if isfield(S, 'trace_only_flipped') && S.trace_only_flipped
        status_msg = [status_msg ' [Trace Flip]'];
    end
    
    title(sprintf('Trace: %s%s', S.filename, status_msg), 'Interpreter', 'none', 'FontSize', 10);
    xlabel('Time (s)', 'FontSize', 9); ylabel('ΔF/F (a.u.)', 'FontSize', 9);
    
    axes(G.ax_img); cla;
    if isfield(S, 'preview_img') && ~isempty(S.preview_img)
        imagesc(S.preview_img); 
        colormap(G.ax_img, jet); 
        axis image off;
        title('Preview', 'FontSize', 9);
        colorbar('FontSize', 8);
    else
        text(0.5, 0.5, 'No Preview', 'HorizontalAlignment', 'center');
        axis off;
    end
    
    info_lines = {
        sprintf('File: %s', S.filename),
        sprintf('Duration: %.2f s', S.time_axis(end)),
        sprintf('Frames: %d', length(S.trace)),
        '',
        sprintf('Global Flip: %s', iif(isfield(S, 'polarity_flipped') && S.polarity_flipped, 'YES', 'No')),
        sprintf('Trace Only Flip: %s', iif(isfield(S, 'trace_only_flipped') && S.trace_only_flipped, 'YES', 'No'))
    };
    set(G.txt_info, 'String', strjoin(info_lines, newline));
    
    guidata(fig, G);
end

function flipTraceOnlyMainCallback(src, ~)
    fig = ancestor(src, 'figure');
    G = guidata(fig);
    idx = G.current_idx;
    
    if idx > length(G.all_data), return; end
    S = G.all_data(idx);
    
    is_flipped = isfield(S, 'trace_only_flipped') && S.trace_only_flipped;
    
    if is_flipped
        action_str = 'RESTORE original trace';
    else
        action_str = 'FLIP trace only';
    end
    
    answer = questdlg(sprintf(['%s for:\n%s\n\n' ...
                               'This will permanently modify the 1D trace in the Summary file.\n' ...
                               '(Movie data will NOT be touched)\n\n' ...
                               'Continue?'], action_str, S.filename), ...
                      'Confirm Trace Flip', 'Yes', 'Cancel', 'Cancel');
    
    if ~strcmp(answer, 'Yes'), return; end
    
    set(src, 'String', 'SAVING...', 'Enable', 'off'); drawnow;
    
    try
        S.trace = -S.trace;
        S.trace_only_flipped = ~is_flipped;
        
        if ~isfield(G.all_data, 'trace_only_flipped')
             [G.all_data.trace_only_flipped] = deal(false);
        end
        
        G.all_data(idx) = S;
        All_Experiments = G.all_data;
        
        save(G.summary_file, 'All_Experiments');
        fprintf('✓ Updated summary file (Trace Flip): %s\n', G.summary_file);
        
        guidata(fig, G);
        updateView(G.lst_box, []);
        
    catch ME
        errordlg(sprintf('Error flipping trace:\n%s', ME.message), 'Error');
    end
    
    set(src, 'String', 'FLIP TRACE ONLY', 'Enable', 'on');
end

function flipPolarityCallback(src, ~)
    fig = ancestor(src, 'figure');
    G = guidata(fig);
    idx = G.current_idx;
    
    if idx > length(G.all_data), return; end
    S = G.all_data(idx);
    
    is_flipped = isfield(S, 'polarity_flipped') && S.polarity_flipped;
    
    if is_flipped, action_str = 'RESTORE original global polarity';
    else, action_str = 'FLIP global polarity (Trace + Movie)'; end
    
    answer = questdlg(sprintf(['%s for:\n%s\n\n' ...
                               'This permanently modifies:\n' ...
                               '- 1D trace in summary\n' ...
                               '- Full movie in original .mat file\n\n' ...
                               'Continue?'], action_str, S.filename), ...
                      'Confirm Global Flip', 'Yes', 'Cancel', 'Cancel');
    
    if ~strcmp(answer, 'Yes'), return; end
    
    set(src, 'String', 'PROCESSING...', 'Enable', 'off'); drawnow;
    
    try
        S.trace = -S.trace;
        if isfield(S, 'preview_img') && ~isempty(S.preview_img)
            S.preview_img = -S.preview_img;
        end
        S.polarity_flipped = ~is_flipped;
        
        if ~isfield(G.all_data, 'polarity_flipped')
             [G.all_data.polarity_flipped] = deal(false);
        end
        
        G.all_data(idx) = S;
        All_Experiments = G.all_data;
        
        save(G.summary_file, 'All_Experiments');
        
        full_path = fullfile(S.folder, S.filename);
        if ~exist(full_path, 'file'), full_path = fullfile('data', S.filename); end
        
        if exist(full_path, 'file')
            D_load = load(full_path, 'reconstructed_movie');
            if isfield(D_load, 'reconstructed_movie')
                reconstructed_movie = -D_load.reconstructed_movie;
                save(full_path, 'reconstructed_movie', '-append');
            end
        end
        
        guidata(fig, G);
        updateView(G.lst_box, []);
        msgbox(sprintf('Global Polarity updated for:\n%s', S.filename), 'Success');
        
    catch ME
        errordlg(sprintf('Error:\n%s', ME.message), 'Error');
    end
    set(src, 'String', 'GLOBAL POLARITY FLIP', 'Enable', 'on');
end

function loadFullMovieAnalyzer(src, ~)
    fig = ancestor(src, 'figure');
    G = guidata(fig);
    idx = G.current_idx;
    
    if idx > length(G.all_data), return; end
    
    S = G.all_data(idx);
    fname = S.filename;
    full_path = fullfile(S.folder, fname);
    if ~exist(full_path, 'file')
        full_path = fullfile('data', fname);
        if ~exist(full_path, 'file')
            full_path = fname;
            if ~exist(full_path, 'file')
                errordlg(sprintf('Cannot find movie file:\n%s', fname), 'File Not Found');
                return; 
            end
        end
    end
    
    fprintf('Loading full movie: %s\n', fname);
    set(src, 'String', 'LOADING...', 'Enable', 'off', 'BackgroundColor', [0.8, 0.8, 0.8]);
    drawnow;
    
    try
        D_load = load(full_path, 'reconstructed_movie');
        if ~isfield(D_load, 'reconstructed_movie')
            error('No reconstructed_movie field found in file.');
        end
        
        h_analyzer = figure('Name', sprintf('Analyzer: %s', fname), ...
                           'Position', [100, 100, 1300, 900], ...
                           'Color', 'w', ...
                           'MenuBar', 'none', ...
                           'NumberTitle', 'off');
        
        analyzer_data = struct();
        analyzer_data.movie_original = D_load.reconstructed_movie;
        analyzer_data.movie = D_load.reconstructed_movie;
        analyzer_data.trace_original = S.trace;
        analyzer_data.trace = S.trace;
        analyzer_data.time = S.time_axis;
        analyzer_data.fs = S.fs;
        analyzer_data.frames = size(D_load.reconstructed_movie, 3);
        analyzer_data.curr_frame = 1;
        
        % Processing state flags (Step 1 Integration)
        analyzer_data.bkg_subtract_active = false;
        analyzer_data.spatial_lowpass_active = false;
        analyzer_data.pos_only_active = false; 
        
        % ROI and baseline storage
        analyzer_data.bkg_roi = [];
        analyzer_data.bkg_trace = [];
        
        mov_vec = analyzer_data.movie(:);
        analyzer_data.clim_global = [min(mov_vec), prctile(mov_vec, 99.9)];
        
        % --- Trace Panel ---
        ax_trace_h = subplot(3, 1, 1);
        analyzer_data.ax_trace_h = ax_trace_h; 
        
        analyzer_data.trace_line = plot(S.time_axis, S.trace, 'k-', 'LineWidth', 1.5); 
        hold on;
        analyzer_data.xline = xline(S.time_axis(1), 'b-', 'LineWidth', 2.5);
        
        title_str = 'Summed Fractional change - 1D trace (4ms/frame) (invreted polraity)';
        if isfield(S, 'trace_only_flipped') && S.trace_only_flipped
            title_str = [title_str ' (Trace Flipped)'];
        end
        
        analyzer_data.trace_title = title(title_str, 'FontSize', 11);
        xlabel('Time (s)'); ylabel('ΔF/F (a.u.)');
        grid on; box on; axis tight;
        set(ax_trace_h, 'ButtonDownFcn', @(s,e) traceClickCallback(s, e, h_analyzer));
        
        % --- Movie Panel ---
        ax_movie = subplot(3, 1, [2, 3]);
        analyzer_data.ax_movie = ax_movie; 
        analyzer_data.img_handle = imagesc(analyzer_data.movie(:,:,1)); 
        colormap(ax_movie, jet); 
        axis image off; 
        colorbar;
        
        analyzer_data.title_h = title(sprintf('Frame 1 / %d', analyzer_data.frames), 'FontSize', 11);
        
        analyzer_data.txt_frame = uicontrol('Style', 'text', ...
            'String', sprintf('Frame: 1\nTime: %.1f ms', S.time_axis(1)*1000), ...
            'Units', 'normalized', ...
            'Position', [0.12, 0.50, 0.12, 0.10], ...
            'FontSize', 18, ...
            'FontWeight', 'bold', ...
            'FontName', 'Courier New', ...
            'HorizontalAlignment', 'center', ...
            'BackgroundColor', 'w', ...
            'ForegroundColor', [0.8, 0.2, 0.2]);
        
        % --- Controls Panel ---
        analyzer_data.slider = uicontrol('Style', 'slider', ...
            'Min', 1, 'Max', analyzer_data.frames, 'Value', 1, ...
            'Units', 'normalized', 'Position', [0.08, 0.02, 0.50, 0.025], ...
            'Callback', @(s,e) analyzerSliderCallback(s, e, h_analyzer));
        
        uicontrol('Style', 'text', ...
                 'String', '← → Arrow keys  |  Click trace to jump', ...
                 'Units', 'normalized', 'Position', [0.08, 0.048, 0.35, 0.018], ...
                 'BackgroundColor', 'w', 'FontSize', 9, 'HorizontalAlignment', 'left');
        
        % --- PROCESSING BUTTONS ---
        btn_width = 0.13;
        btn_height = 0.04;
        btn_y1 = 0.08;
        
        analyzer_data.btn_bkg = uicontrol('Style', 'pushbutton', ...
                  'String', 'Background Subtract', ...
                  'Units', 'normalized', 'Position', [0.60, btn_y1, btn_width, btn_height], ...
                  'BackgroundColor', [0.4, 0.8, 0.4], 'ForegroundColor', 'k', ...
                  'FontWeight', 'bold', 'FontSize', 9, ...
                  'Callback', @(s,e) backgroundSubtractCallback(s, e, h_analyzer));
        
        analyzer_data.btn_spatial = uicontrol('Style', 'pushbutton', ...
                  'String', 'Spatial Low-Pass', ...
                  'Units', 'normalized', 'Position', [0.74, btn_y1, btn_width, btn_height], ...
                  'BackgroundColor', [0.4, 0.8, 0.4], 'ForegroundColor', 'k', ...
                  'FontWeight', 'bold', 'FontSize', 9, ...
                  'Callback', @(s,e) spatialLowPassCallback(s, e, h_analyzer));

        % Step 2 Integration: Positive Only Button
        analyzer_data.btn_pos = uicontrol('Style', 'pushbutton', ...
                  'String', 'Positive Only', ...
                  'Units', 'normalized', ...
                  'Position', [0.60, btn_y1 - 0.05, btn_width, btn_height], ...
                  'BackgroundColor', [0.4, 0.8, 0.4], ...
                  'FontWeight', 'bold', 'FontSize', 9, ...
                  'Callback', @(s,e) positiveOnlyCallback(s, e, h_analyzer), ...
                  'TooltipString', 'Keep positive ΔF/F only');
        
        % --- UTILITY BUTTONS ---
        uicontrol('Style', 'pushbutton', 'String', 'Mark Trigger', ...
                  'Units', 'normalized', 'Position', [0.88, btn_y1, 0.10, btn_height], ...
                  'BackgroundColor', [0.9, 0.6, 0.6], 'FontWeight', 'bold', 'FontSize', 9, ...
                  'Callback', @(s,e) addTriggerMark(s, e, h_analyzer));
        
        uicontrol('Style', 'pushbutton', 'String', 'RESET ALL', ...
                  'Units', 'normalized', 'Position', [0.88, 0.04, 0.10, btn_height], ...
                  'BackgroundColor', [0.9, 0.4, 0.3], 'ForegroundColor', 'w', ...
                  'FontWeight', 'bold', 'FontSize', 9, ...
                  'Callback', @(s,e) resetAllProcessing(s, e, h_analyzer));
                  
        analyzer_data.chk_norm = uicontrol('Style', 'checkbox', ...
                  'String', 'Global Colormap', ...
                  'Units', 'normalized', 'Position', [0.45, 0.048, 0.12, 0.018], ...
                  'BackgroundColor', 'w', 'FontSize', 8, ...
                  'Value', 0, ... 
                  'Callback', @(s,e) updateAnalyzerFrame(h_analyzer, guidata(h_analyzer)));
        
        guidata(h_analyzer, analyzer_data);
        set(h_analyzer, 'KeyPressFcn', @(s,e) analyzerKeyPress(s, e));
        
        fprintf('   Analyzer window opened\n\n');
        
    catch ME
        errordlg(sprintf('Failed to load movie:\n%s\n\nError: %s', fname, ME.message), 'Error');
    end
    set(src, 'String', 'OPEN ANALYZER', 'Enable', 'on', 'BackgroundColor', [0.3, 0.7, 0.9]);
end

%% ======================== PROCESSING FUNCTIONS ========================

function resetAllProcessing(~, ~, h_analyzer)
    D = guidata(h_analyzer);
    if isempty(D), return; end
    
    % Restore original data
    D.movie = D.movie_original;
    D.trace = D.trace_original;
    
    % Reset all flags (Step 6 Integration)
    D.bkg_subtract_active = false;
    D.spatial_lowpass_active = false;
    D.pos_only_active = false;
    
    % Clear stored data
    D.bkg_roi = [];
    D.bkg_trace = [];
    
    % Reset buttons
    set(D.btn_bkg, 'String', 'Background Subtract', 'BackgroundColor', [0.4, 0.8, 0.4]);
    set(D.btn_spatial, 'String', 'Spatial Low-Pass', 'BackgroundColor', [0.4, 0.8, 0.4]);
    set(D.btn_pos, 'String', 'Positive Only', 'BackgroundColor', [0.4, 0.8, 0.4]);
    
    % Update trace
    set(D.trace_line, 'YData', D.trace);
    axes(D.ax_trace_h);
    title_str = get(D.trace_title, 'String');
    title_str = regexprep(title_str, ' \[.*?\]', '');
    set(D.trace_title, 'String', title_str);
    axis tight;
    
    % Recalc colormap
    mov_vec = D.movie(:);
    D.clim_global = [min(mov_vec), prctile(mov_vec, 99.9)];
    
    guidata(h_analyzer, D);
    updateAnalyzerFrame(h_analyzer, D);
    fprintf('   ✓ All processing RESET\n');
end

function positiveOnlyCallback(src, ~, h_analyzer)
    D = guidata(h_analyzer);
    if isempty(D), return; end
    
    % Toggle through modes: OFF -> Positive Only -> Negative Only (Inverted)
    if ~isfield(D, 'signal_mode'), D.signal_mode = 0; end % 0:Off, 1:Pos, 2:Neg
    
    D.signal_mode = mod(D.signal_mode + 1, 3);
    
    switch D.signal_mode
        case 0
            set(src, 'String', 'Positive Only', 'BackgroundColor', [0.4, 0.8, 0.4]);
            D.pos_only_active = false;
            D.neg_only_inverted = false;
        case 1
            set(src, 'String', 'Show POS Only', 'BackgroundColor', [0.3, 0.6, 0.9]);
            D.pos_only_active = true;
            D.neg_only_inverted = false;
        case 2
            set(src, 'String', 'Show NEG (Inverted)', 'BackgroundColor', [0.9, 0.5, 0.2]);
            D.pos_only_active = false;
            D.neg_only_inverted = true;
    end
    
    set(D.chk_norm, 'Value', 1); % Auto-enable global colormap for better visualization
    guidata(h_analyzer, D);
    applyAllProcessing(h_analyzer);
end

function backgroundSubtractCallback(~, ~, h_analyzer)
    D = guidata(h_analyzer);
    if isempty(D), return; end
    
    if D.bkg_subtract_active
        D.bkg_subtract_active = false;
        D.bkg_roi = [];
        D.bkg_trace = [];
        set(D.btn_bkg, 'String', 'Background Subtract', 'BackgroundColor', [0.4, 0.8, 0.4]);
        guidata(h_analyzer, D);
        applyAllProcessing(h_analyzer);
        fprintf('   Background subtraction OFF\n');
        return;
    end
    
    fprintf('   Select background ROI...\n');
    axes(D.ax_movie);
    title('Draw rectangle around BACKGROUND region');
    
    try
        h_rect = drawrectangle('Color', 'r', 'LineWidth', 2, 'Label', 'Background');
        wait(h_rect);
        roi_pos = h_rect.Position;
        delete(h_rect);
        
        x_start = max(1, round(roi_pos(1)));
        y_start = max(1, round(roi_pos(2)));
        x_end = min(size(D.movie_original, 2), round(roi_pos(1) + roi_pos(3)));
        y_end = min(size(D.movie_original, 1), round(roi_pos(2) + roi_pos(4)));
        
        D.bkg_roi = [y_start, y_end, x_start, x_end];
        bkg_region = D.movie_original(y_start:y_end, x_start:x_end, :);
        D.bkg_trace = squeeze(mean(mean(bkg_region, 1), 2));
        
        D.bkg_subtract_active = true;
        set(D.btn_bkg, 'String', 'Remove Bkg Sub', 'BackgroundColor', [0.9, 0.4, 0.4]);
        
        guidata(h_analyzer, D);
        applyAllProcessing(h_analyzer);
        fprintf('   ✓ Background subtraction ON\n');
    catch
        fprintf('   ROI selection canceled\n');
    end
end

function spatialLowPassCallback(~, ~, h_analyzer)
    D = guidata(h_analyzer);
    if isempty(D), return; end
    
    if D.spatial_lowpass_active
        D.spatial_lowpass_active = false;
        set(D.btn_spatial, 'String', 'Spatial Low-Pass', 'BackgroundColor', [0.4, 0.8, 0.4]);
        guidata(h_analyzer, D);
        applyAllProcessing(h_analyzer);
        fprintf('   Spatial low-pass OFF\n');
        return;
    end
    
    D.spatial_lowpass_active = true;
    set(D.btn_spatial, 'String', 'Remove Spatial LP', 'BackgroundColor', [0.9, 0.4, 0.4]);
    guidata(h_analyzer, D);
    applyAllProcessing(h_analyzer);
    fprintf('   ✓ Spatial low-pass ON\n');
end

%% ======================== PROCESSING PIPELINE ========================

function applyAllProcessing(h_analyzer)
    D = guidata(h_analyzer);
    if isempty(D), return; end
    
    movie_proc = D.movie_original;
    status_tags = {};
    
    % --- STEP 1: DYNAMIC BASELINE NORMALIZATION ---
    % Subtracting the average of pre-stimulus frames sets the resting state to zero.
    % This ensures the "bell curve" starts from a flat baseline[cite: 1081].
    pre_stim_idx = D.time < 0.1; % Adjust based on your actual stimulus onset
    if any(pre_stim_idx)
        baseline_map = mean(movie_proc(:,:,pre_stim_idx), 3);
        for t = 1:D.frames
            movie_proc(:,:,t) = movie_proc(:,:,t) - baseline_map;
        end
        status_tags{end+1} = 'BASE';
    end

    % --- STEP 2: SPATIAL MODULAR SMOOTHING ---
    % Gaussian filtering helps define the "peaks" by reducing pixel-level noise,
    % similar to how modular domains appear in published figures.
    if D.spatial_lowpass_active
        h_filt = fspecial('gaussian', [9 9], 2); 
        for t = 1:D.frames
            movie_proc(:,:,t) = imfilter(movie_proc(:,:,t), h_filt, 'replicate');
        end
        status_tags{end+1} = 'SMOOTH';
    end
    
    % --- STEP 3: POSITIVE PEAK RECTIFICATION ---
    % This is the "Bell Curve" logic: all values < 0 are clipped to zero.
    % It isolates the excitatory hotspots (depolarization)[cite: 107, 1089].
    movie_proc(movie_proc < 0) = 0; 
    status_tags{end+1} = 'PEAKS-ONLY';
    
    % --- STEP 4: INTENSITY THRESHOLDING (Optional but Recommended) ---
    % Standard VSDI maps often use a threshold to show only high-amplitude spiking areas[cite: 107].
    max_val = max(movie_proc(:));
    movie_proc(movie_proc < 0.1 * max_val) = 0; % Cleans up the "base" of the curves
    
    % Update data and colormap
    D.movie = movie_proc;
    D.trace = squeeze(mean(mean(D.movie, 1), 2));
    
    % Force the colormap to start at 0 to emphasize activation peaks[cite: 1085].
    D.clim_global = [0, prctile(D.movie(:), 99.9)]; 
    
    % UI Updates
    set(D.trace_line, 'YData', D.trace);
    axes(D.ax_trace_h);
    title_str = regexprep(get(D.trace_title, 'String'), ' \[.*?\]', '');
    set(D.trace_title, 'String', [title_str ' [' strjoin(status_tags, '+') ']']);
    axis tight;
    
    guidata(h_analyzer, D);
    updateAnalyzerFrame(h_analyzer, D);
end

%% ======================== ANALYZER CALLBACKS ========================

function updateAnalyzerFrame(h_analyzer, D)
    f = max(1, min(round(D.curr_frame), D.frames));
    set(D.img_handle, 'CData', D.movie(:,:,f));
    
    if get(D.chk_norm, 'Value')
        caxis(D.ax_movie, D.clim_global);
    else
        caxis(D.ax_movie, 'auto');
    end
    
    set(D.title_h, 'String', sprintf('Frame %d / %d  (Time: %.3f s)', f, D.frames, D.time(f)));
    set(D.xline, 'Value', D.time(f));
    set(D.slider, 'Value', f);
    set(D.txt_frame, 'String', sprintf('Frame: %d\nTime: %.0f ms', f, D.time(f)*1000));
    D.curr_frame = f;
    guidata(h_analyzer, D);
end

function analyzerSliderCallback(src, ~, h_analyzer)
    D = guidata(h_analyzer);
    if isempty(D), return; end
    D.curr_frame = round(get(src, 'Value'));
    updateAnalyzerFrame(h_analyzer, D);
end

function addTriggerMark(~, ~, h_analyzer)
    D = guidata(h_analyzer);
    if isempty(D), return; end
    curr_t = D.time(round(D.curr_frame));
    axes(D.ax_trace_h); hold on;
    xline(curr_t, 'r--', 'LineWidth', 1.5);
    y_limits = ylim;
    text(curr_t, y_limits(2), sprintf(' %.3fs', curr_t), ...
        'Color', 'r', 'FontSize', 8, 'VerticalAlignment', 'top', 'FontWeight', 'bold');
end

function analyzerKeyPress(src, event)
    D = guidata(src);
    if isempty(D), return; end
    switch event.Key
        case 'rightarrow', D.curr_frame = D.curr_frame + 1;
        case 'leftarrow', D.curr_frame = D.curr_frame - 1;
        case 'uparrow', D.curr_frame = D.curr_frame + 10;
        case 'downarrow', D.curr_frame = D.curr_frame - 10;
    end
    updateAnalyzerFrame(src, D);
end

function traceClickCallback(~, event, h_analyzer)
    D = guidata(h_analyzer);
    if isempty(D), return; end
    t_click = event.IntersectionPoint(1);
    [~, f_idx] = min(abs(D.time - t_click));
    D.curr_frame = f_idx;
    updateAnalyzerFrame(h_analyzer, D);
end

function result = iif(condition, true_val, false_val)
    if condition, result = true_val; else, result = false_val; end
end