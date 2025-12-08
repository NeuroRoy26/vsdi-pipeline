function MEA_Interactive_GUI
    % MEA_INTERACTIVE_GUI
    % Interactive tool to align FlexMEA72 layout over Structural Anatomy.
    % 
    % CONTROLS:
    %   - Scale Slider: Adjusts microns per pixel (zooms grid in/out).
    %   - Rotation Slider: Rotates the grid.
    %   - X/Y Offset Sliders: Moves the grid.
    %   - Export Button: Prints the final numbers to the command window.

    clear; clc; close all;

    %% 1. LOAD DATA & STRUCTURAL BACKGROUND
    % =====================================================================
    fprintf('Initializing...\n');
    
    % --- A. Try Loading Structural Anatomy (Your Snippet) ---
    input_file = 'data/averaged_movie_E0B0-B3_unbinned.h5';
    dataset_name = '/structural';
    bg_img = [];
    
    if exist(input_file, 'file')
        try
            fprintf('Loading structural movie from %s...\n', input_file);
            mov_struct = h5read(input_file, dataset_name);
            bg = mean(mov_struct, 3);
            bg = double(bg);
            % Normalize to 0-1 for RGB display
            bg_norm = (bg - min(bg(:))) / (max(bg(:)) - min(bg(:)));
            bg_img = cat(3, bg_norm, bg_norm, bg_norm); % Create RGB (Gray)
            fprintf('✓ Structural background loaded successfully.\n');
        catch
            fprintf('! Warning: Structural load failed. Attempting fallback...\n');
        end
    else
        fprintf('! Warning: Structural file not found (%s).\n', input_file);
    end

    % --- B. Load Functional Data (Fallback if Structural missing) ---
    % We still need 'H' and 'W' to set slider limits properly
    data = [];
    if evalin('base', 'exist(''reconstructed_movie'', ''var'')')
        data = evalin('base', 'reconstructed_movie');
    elseif evalin('base', 'exist(''mov_recon'', ''var'')')
        data = evalin('base', 'mov_recon');
    elseif evalin('base', 'exist(''mov'', ''var'')')
        data = evalin('base', 'mov');
    elseif exist('data/reconstructed_ICs_001.mat', 'file') % Example fallback
         % Try to load first available mat file in data/ if workspace is empty
         files = dir('data/reconstructed_ICs_*.mat');
         if ~isempty(files)
            ld = load(fullfile('data', files(1).name));
            fnames = fieldnames(ld);
            data = ld.(fnames{1});
         end
    end

    % Determine Dimensions
    if ~isempty(bg_img)
        [H, W, ~] = size(bg_img);
    elseif ~isempty(data)
        [H, W, ~] = size(data);
        % If we have data but no structural image, make a background from data
        if isempty(bg_img)
            fprintf('Using functional data average as background.\n');
            bg_raw = mean(double(data), 3);
            bg_norm = (bg_raw - min(bg_raw(:))) / (max(bg_raw(:)) - min(bg_raw(:)));
            bg_img = cat(3, bg_norm, bg_norm, bg_norm);
        end
    else
        % Absolute fallback (Dummy)
        fprintf('! No Data found. Using Dummy Size (400x400).\n');
        H = 400; W = 400;
        bg_img = zeros(H, W, 3); 
    end

    %% 2. INITIAL PARAMETERS (FlexMEA72)
    % =====================================================================
    % Specs from FlexMEA72 Layout PDF
    params.pitch_x_um = 625;   
    params.pitch_y_um = 750;   
    params.rows = 9;           % A-J
    params.cols = 8;           % 1-8
    
    % Initial State (Adjust these if you want different starting values)
    state.scale = 15.0;        % Microns per pixel
    state.rotation = 0;        % Degrees
    state.off_x = 0;           % Pixels
    state.off_y = 0;           % Pixels

    %% 3. SETUP FIGURE & GUI
    % =====================================================================
    f = figure('Name', 'FlexMEA72 Alignment Tool', ...
               'Color', 'w', 'Position', [50 50 1000 700], ...
               'NumberTitle', 'off', 'MenuBar', 'none');

    % --- Main Axes ---
    ax = axes('Parent', f, 'Position', [0.05 0.3 0.9 0.65]);
    
    % Display the Structural Image
    imagesc(ax, bg_img); 
    axis(ax, 'image', 'off');
    hold(ax, 'on');

    % --- Plot Objects (MEA Grid) ---
    % We plot empty placeholders now, updated via sliders later
    % Recording Electrodes (Black Circles)
    h_rec = plot(ax, NaN, NaN, 'o', 'MarkerSize', 8, ...
        'LineWidth', 1.5, 'Color', 'k', 'MarkerFaceColor', 'none'); 
    
    % A1 Indicator (Yellow text to help orientation)
    h_lbl = text(ax, NaN, NaN, 'A1', 'Color', 'y', 'FontWeight', 'bold', 'FontSize', 12);
    
    % Center crosshair (Red +)
    plot(ax, W/2, H/2, 'r+', 'MarkerSize', 20, 'LineWidth', 1);

    % --- GUI Controls Panel ---
    pnl = uipanel('Parent', f, 'Position', [0.05 0.02 0.9 0.25], ...
                  'Title', 'FlexMEA72 Alignment Controls', 'BackgroundColor', 'w');

    % Slider 1: Scale (Microns per Pixel)
    uicontrol(pnl, 'Style', 'text', 'Position', [20 130 150 20], 'String', 'Scale (um/px):', 'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
    sld_scale = uicontrol(pnl, 'Style', 'slider', 'Position', [20 110 300 20], 'Min', 1, 'Max', 60, 'Value', state.scale);
    txt_scale = uicontrol(pnl, 'Style', 'text', 'Position', [330 110 50 20], 'String', num2str(state.scale), 'BackgroundColor', 'w');

    % Slider 2: Rotation (Degrees)
    uicontrol(pnl, 'Style', 'text', 'Position', [20 80 150 20], 'String', 'Rotation (Deg):', 'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
    sld_rot = uicontrol(pnl, 'Style', 'slider', 'Position', [20 60 300 20], 'Min', -180, 'Max', 180, 'Value', state.rotation);
    txt_rot = uicontrol(pnl, 'Style', 'text', 'Position', [330 60 50 20], 'String', num2str(state.rotation), 'BackgroundColor', 'w');

    % Slider 3: X Offset
    uicontrol(pnl, 'Style', 'text', 'Position', [450 130 150 20], 'String', 'X Offset (px):', 'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
    sld_x = uicontrol(pnl, 'Style', 'slider', 'Position', [450 110 300 20], 'Min', -W/1.5, 'Max', W/1.5, 'Value', state.off_x);
    txt_x = uicontrol(pnl, 'Style', 'text', 'Position', [760 110 50 20], 'String', num2str(state.off_x), 'BackgroundColor', 'w');

    % Slider 4: Y Offset
    uicontrol(pnl, 'Style', 'text', 'Position', [450 80 150 20], 'String', 'Y Offset (px):', 'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
    sld_y = uicontrol(pnl, 'Style', 'slider', 'Position', [450 60 300 20], 'Min', -H/1.5, 'Max', H/1.5, 'Value', state.off_y);
    txt_y = uicontrol(pnl, 'Style', 'text', 'Position', [760 60 50 20], 'String', num2str(state.off_y), 'BackgroundColor', 'w');

    % Export Button
    uicontrol(pnl, 'Style', 'pushbutton', 'Position', [900 90 150 40], ...
        'String', 'PRINT SETTINGS', 'FontWeight', 'bold', 'FontSize', 10, ...
        'Callback', @print_settings);

    % Store handles
    handles.h_rec = h_rec;
    handles.h_lbl = h_lbl;
    handles.txt_scale = txt_scale;
    handles.txt_rot = txt_rot;
    handles.txt_x = txt_x;
    handles.txt_y = txt_y;
    handles.W = W;
    handles.H = H;
    handles.params = params;

    % Callbacks & Listeners
    addlistener(sld_scale, 'Value', 'PostSet', @(~,~) update_wrapper(sld_scale, sld_rot, sld_x, sld_y, handles));
    addlistener(sld_rot, 'Value', 'PostSet', @(~,~) update_wrapper(sld_scale, sld_rot, sld_x, sld_y, handles));
    addlistener(sld_x, 'Value', 'PostSet', @(~,~) update_wrapper(sld_scale, sld_rot, sld_x, sld_y, handles));
    addlistener(sld_y, 'Value', 'PostSet', @(~,~) update_wrapper(sld_scale, sld_rot, sld_x, sld_y, handles));

    % Trigger initial update
    update_wrapper(sld_scale, sld_rot, sld_x, sld_y, handles);

    %% 4. NESTED FUNCTIONS
    % =====================================================================
    
    function update_wrapper(s_scale, s_rot, s_x, s_y, h)
        update_mea(get(s_scale,'Value'), get(s_rot,'Value'), get(s_x,'Value'), get(s_y,'Value'), h);
    end

    function update_mea(v_scale, v_rot, v_x, v_y, h)
        % Update Text
        set(h.txt_scale, 'String', sprintf('%.1f', v_scale));
        set(h.txt_rot, 'String', sprintf('%.0f', v_rot));
        set(h.txt_x, 'String', sprintf('%.0f', v_x));
        set(h.txt_y, 'String', sprintf('%.0f', v_y));

        % --- GENERATE GEOMETRY ---
        [gx, gy] = meshgrid(1:h.params.cols, 1:h.params.rows);
        
        % Mask GND/REF (FlexMEA72 Page 2 Layout)
        mask = true(h.params.rows, h.params.cols);
        mask(1, 4:5) = false; % A4, A5 (GND)
        mask(2, 4:5) = false; % B4, B5 (REF)
        mask(7, 1) = false; mask(7, 8) = false; % G1, G8 (REF)
        mask(9, 1) = false; mask(9, 8) = false; % J1, J8 (GND)

        % Convert to Microns (Centered on array center)
        % Center of 8 cols is 4.5; Center of 9 rows is 5.0
        px_um = (gx - 4.5) * h.params.pitch_x_um;
        py_um = (gy - 5.0) * h.params.pitch_y_um;

        % Scale to Pixels
        px_px = px_um / v_scale;
        py_px = py_um / v_scale;

        % Rotation
        th = deg2rad(v_rot);
        R = [cos(th), -sin(th); sin(th), cos(th)];
        
        pts = [px_px(:)'; py_px(:)'];
        rot_pts = R * pts;
        
        rx = reshape(rot_pts(1,:), size(gx));
        ry = reshape(rot_pts(2,:), size(gy));

        % Translation (Center of Image + Offset)
        fx = rx + (h.W/2) + v_x;
        fy = ry + (h.H/2) + v_y;

        % Filter Valid Electrodes
        fx_rec = fx(mask);
        fy_rec = fy(mask);

        % Update Plots
        set(h.h_rec, 'XData', fx_rec, 'YData', fy_rec);
        
        % Update Label A1 (Index 1 is (1,1))
        set(h.h_lbl, 'Position', [fx(1,1), fy(1,1), 0]);
    end

    function print_settings(~, ~)
         v_scale = get(sld_scale, 'Value');
         v_rot = get(sld_rot, 'Value');
         v_x = get(sld_x, 'Value');
         v_y = get(sld_y, 'Value');
         
         fprintf('\n%% --- PASTE THIS INTO YOUR ANALYSIS SCRIPT ---\n');
         fprintf('MEA_CENTER_X = (W/2) + %.1f; %% Offset X\n', v_x);
         fprintf('MEA_CENTER_Y = (H/2) + %.1f; %% Offset Y\n', v_y);
         fprintf('MEA_ROTATION = %.1f;\n', v_rot);
         fprintf('um_per_pixel = %.2f;\n', v_scale);
         fprintf('%% --------------------------------------------\n');
    end
end