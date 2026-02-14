% Review_Fix_Save_Final.m
% 
% PURPOSE: 
%   1. Separates 2 mixed components (SVD+ICA).
%   2. FIXED: Robust Play/Pause button.
%   3. TWO Polarity Buttons:
%       - Flip EVERYTHING (Trace + Map)
%       - Flip MAP ONLY (Keep Trace, Invert Colors)
%   4. Smart Saving.

clear; clc; close all;

%% ======================== CONFIGURATION ========================
CONFIG.bandpass_freq = [0.1, 75];     
CONFIG.filter_order = 4;
CONFIG.default_fs = 500;              

%% ======================== 1. LOAD DATA ========================
fprintf('========================================\n');
fprintf('   ADVANCED IC REVIEW & FIX TOOL\n');
fprintf('========================================\n');

[filename, pathname] = uigetfile('*.mat', 'Select Your 2-Component File');
if isequal(filename, 0), return; end
full_path = fullfile(pathname, filename);

fprintf('Loading: %s ...\n', filename);
D = load(full_path);
mov = D.reconstructed_movie;
[h, w, num_frames] = size(mov);
num_pixels = h * w;

if isfield(D, 'Fs'), Fs = D.Fs; else, Fs = CONFIG.default_fs; end

%% ======================== 2. PRE-PROCESSING ========================
fprintf('Reshaping and Filtering...\n');
X = reshape(mov, num_pixels, num_frames);
mean_X = mean(X, 2);
X_centered = X - mean_X;

% Filter
nyq = Fs / 2;
[b, a] = butter(CONFIG.filter_order, CONFIG.bandpass_freq / nyq, 'bandpass');
X_filt = filtfilt(b, a, X_centered')'; 

%% ======================== 3. SMART DECOMPOSITION ========================
fprintf('Separating Components...\n');
[U, S, V] = svds(X_filt, 2); 
Z = S * V'; 

try
    [ica_sig, A_ica, ~] = fastica(Z, 'verbose', 'off', 'displayMode', 'off');
    spatial_maps = U * A_ica;
    time_traces = ica_sig;
catch
    spatial_maps = U * S;
    time_traces = V';
end

%% ======================== 4. COMPONENT SELECTION ========================
f_sel = figure('Name', 'Select Component', 'Color', 'w', 'Position', [200, 200, 1000, 500]);
time_ax = (0:num_frames-1)/Fs;

for i = 1:2
    subplot(2, 2, (i-1)*2 + 1);
    imagesc(reshape(spatial_maps(:, i), h, w)); axis image off; colormap jet; title(sprintf('Map %d', i));
    subplot(2, 2, (i-1)*2 + 2);
    plot(time_ax, time_traces(i, :), 'k'); axis tight; grid on; title(sprintf('Trace %d', i));
end

choice = input('Which component do you want to KEEP? (Enter 1 or 2): ');
if ~ismember(choice, [1, 2]), close(f_sel); error('Invalid selection.'); end
close(f_sel);

%% ======================== 5. RECONSTRUCTION ========================
fprintf('Reconstructing Component #%d...\n', choice);
Map_sel = spatial_maps(:, choice);
Trace_sel = time_traces(choice, :);
X_recon_2d = (Map_sel * Trace_sel); % No mean added yet (easier to flip)
mov_recon = reshape(X_recon_2d, h, w, num_frames);

% Prepare Trace for Viewer
raw_trace = squeeze(mean(mean(mov_recon, 1), 2));
trace_norm = (raw_trace - mean(raw_trace)) / std(raw_trace);

%% ======================== 6. INTERACTIVE VIEWER GUI ========================
% Initialize Viewer Data
V = struct();
V.mov = mov_recon;        % Base movie (Zero Mean)
V.mean_img = reshape(mean_X, h, w); % Saved Mean Image
V.trace = trace_norm;     % Base trace
V.time = time_ax;
V.num_frames = num_frames;
V.curr_frame = 1;

% STATE FLAGS
V.pol_global = 1; % 1 = Normal, -1 = Invert Everything
V.pol_map = 1;    % 1 = Normal, -1 = Invert Map Only

V.is_playing = false;
V.filename = filename;
V.pathname = pathname;
V.choice = choice;
V.Fs = Fs;

% Create Figure
f_gui = figure('Name', ['Review: ' filename], 'Position', [100, 100, 1000, 800], 'Color', 'w');

% --- AXES 1: TRACE ---
V.ax_trace = axes('Parent', f_gui, 'Position', [0.1, 0.75, 0.8, 0.2]);
V.plot_trace = plot(V.time, V.trace, 'b'); hold on;
V.line_cursor = xline(V.time(1), 'r', 'LineWidth', 2);
title('Global Signal (Z-Score)'); grid on; axis tight;

% --- AXES 2: MOVIE ---
V.ax_movie = axes('Parent', f_gui, 'Position', [0.1, 0.25, 0.8, 0.4]);
V.h_img = imagesc(V.mov(:,:,1));
axis image off; colormap jet; colorbar;
title('Component Movie');
clim_max = max(abs(V.mov(:))) * 0.8;
set(V.ax_movie, 'CLim', [-clim_max, clim_max]);

% --- CONTROLS ---
% Slider
V.slider = uicontrol('Style', 'slider', 'Min', 1, 'Max', num_frames, 'Value', 1, ...
    'Units', 'normalized', 'Position', [0.1, 0.15, 0.8, 0.05], ...
    'Callback', @(s,e) slider_callback(s));

% Play/Pause
V.btn_play = uicontrol('Style', 'pushbutton', 'String', 'PLAY', ...
    'Units', 'normalized', 'Position', [0.05, 0.05, 0.15, 0.08], ...
    'FontSize', 12, 'Callback', @(s,e) play_callback(s));

% 1. Flip EVERYTHING
V.btn_flip_all = uicontrol('Style', 'pushbutton', 'String', 'FLIP TRACE & MAP', ...
    'Units', 'normalized', 'Position', [0.25, 0.05, 0.2, 0.08], ...
    'FontSize', 10, 'BackgroundColor', [0.9 0.9 0.9], ...
    'Callback', @(s,e) flip_all_callback(s));

% 2. Flip MAP ONLY
V.btn_flip_map = uicontrol('Style', 'pushbutton', 'String', 'FLIP MAP ONLY', ...
    'Units', 'normalized', 'Position', [0.50, 0.05, 0.2, 0.08], ...
    'FontSize', 10, 'BackgroundColor', [0.9 0.9 0.9], ...
    'Callback', @(s,e) flip_map_callback(s));

% Save Button
V.btn_save = uicontrol('Style', 'pushbutton', 'String', 'SAVE & EXIT', ...
    'Units', 'normalized', 'Position', [0.75, 0.05, 0.2, 0.08], ...
    'FontSize', 12, 'BackgroundColor', [0.6 1 0.6], 'FontWeight', 'bold', ...
    'Callback', @(s,e) save_callback(s));

% Store data in figure
guidata(f_gui, V);

%% ======================== CALLBACK FUNCTIONS ========================

    function slider_callback(src)
        fig = ancestor(src, 'figure');
        V = guidata(fig);
        
        % Dragging slider stops playback
        V.is_playing = false; 
        set(V.btn_play, 'String', 'PLAY');
        
        idx = round(get(src, 'Value'));
        V.curr_frame = idx;
        
        update_display(fig, V);
        guidata(fig, V);
    end

    function flip_all_callback(src)
        fig = ancestor(src, 'figure');
        V = guidata(fig);
        
        V.pol_global = V.pol_global * -1;
        
        % Color feedback
        if V.pol_global == -1, set(src, 'BackgroundColor', [1 0.6 0.6]); 
        else, set(src, 'BackgroundColor', [0.9 0.9 0.9]); end
        
        guidata(fig, V);
        update_display(fig, V);
    end

    function flip_map_callback(src)
        fig = ancestor(src, 'figure');
        V = guidata(fig);
        
        V.pol_map = V.pol_map * -1;
        
        % Color feedback
        if V.pol_map == -1, set(src, 'BackgroundColor', [0.6 0.6 1]); 
        else, set(src, 'BackgroundColor', [0.9 0.9 0.9]); end
        
        guidata(fig, V);
        update_display(fig, V);
    end

    function play_callback(src)
        fig = ancestor(src, 'figure');
        V = guidata(fig);
        
        if V.is_playing
            % --- PAUSE ACTION ---
            V.is_playing = false;
            set(src, 'String', 'PLAY');
            guidata(fig, V);
        else
            % --- PLAY ACTION ---
            V.is_playing = true;
            set(src, 'String', 'PAUSE');
            guidata(fig, V);
            
            % Play Loop
            while true
                % 1. Check if figure is still open
                if ~isvalid(fig), break; end
                
                % 2. Reload Data (Check if user clicked Pause or Slider)
                V = guidata(fig);
                if ~V.is_playing, break; end 
                
                % 3. Check for end of movie
                if V.curr_frame >= V.num_frames
                    V.is_playing = false;
                    set(src, 'String', 'PLAY');
                    guidata(fig, V);
                    break;
                end
                
                % 4. Advance Frame
                V.curr_frame = V.curr_frame + 1;
                set(V.slider, 'Value', V.curr_frame);
                
                % 5. Update Screen
                update_display(fig, V);
                
                % 6. Save State
                guidata(fig, V);
                
                % 7. FLUSH EVENTS (Allows Pause button click to register)
                drawnow; 
                % Optional: Add pause(0.01) if it's still too fast
            end
        end
    end

    function update_display(fig, V)
        % If V is not passed, load it
        if nargin < 2, V = guidata(fig); end
        
        % 1. TRACE (Global Polarity Only)
        current_trace = V.trace * V.pol_global;
        set(V.plot_trace, 'YData', current_trace);
        set(V.line_cursor, 'Value', V.time(V.curr_frame));
        
        % 2. MOVIE (Global * Map Polarity)
        combined_polarity = V.pol_global * V.pol_map;
        frame_data = V.mov(:,:,V.curr_frame) * combined_polarity; 
        set(V.h_img, 'CData', frame_data);
        
        title(V.ax_movie, sprintf('Frame %d / %d (%.2fs)', V.curr_frame, V.num_frames, V.time(V.curr_frame)));
    end

    function save_callback(src)
        fig = ancestor(src, 'figure');
        V = guidata(fig);
        
        fprintf('Applying Changes...\n');
        
        % Combine Polarities
        final_polarity = V.pol_global * V.pol_map;
        
        % Apply to Movie (Zero Mean)
        final_movie = V.mov * final_polarity;
        
        % Add Mean Back
        final_movie = final_movie + repmat(V.mean_img, [1 1 V.num_frames]);
        
        % Smart Naming
        [~, f, ext] = fileparts(V.filename);
        if contains(f, '_2comp'), new_f = strrep(f, '_2comp', sprintf('_Comp%d', V.choice));
        elseif contains(f, '2comp'), new_f = strrep(f, '2comp', sprintf('Comp%d', V.choice));
        else, new_f = sprintf('%s_Comp%d', f, V.choice); end
        
        save_name = [new_f, ext];
        save_path = fullfile(V.pathname, save_name);
        
        reconstructed_movie = final_movie;
        Fs = V.Fs;
        save(save_path, 'reconstructed_movie', 'Fs');
        
        msgbox(['Saved: ' save_name], 'Success');
        close(fig);
    end