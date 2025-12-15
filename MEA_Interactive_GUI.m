function MEA_Interactive_GUI()
    % INTERACTIVE_MEA_OVERLAY
    % Launches a GUI to align the FlexMEA72 grid over your VSD data.
    %
    % UPDATES:
    % - Checks for 'data/MEA_Map.mat' on startup to resume alignment.
    % - Saves alignment parameters (offsets/rotation) so they can be reloaded.
    
    % --- CONFIGURATION ---
    pixel_size_um = 4.7 * 2;   
    mea_pitch_x_um = 625;
    mea_pitch_y_um = 750;
    stim_frame_idx = 376; 
    
    % File path for saving/loading
    save_dir = 'data';
    save_file = fullfile(save_dir, 'MEA_Map.mat');
    
    % --- GET DATA FROM WORKSPACE ---
    try
        M = evalin('base', 'M_smooth');
        [H, W, ~] = size(M);
        img = M(:,:,stim_frame_idx);
        
        try, bg_rgb = evalin('base', 'structural_rgb'); catch, bg_rgb = []; end
        try, floor_val = evalin('base', 'floor_val'); catch, floor_val = min(img(:)); end
        try, sat_val = evalin('base', 'sat_val'); catch, sat_val = max(img(:)); end
        
    catch
        error('Data not found! Please run your reconstruction script first to load ''M_smooth''.');
    end

    % --- DEFINE GRID & LABELS ---
    cols = 8; rows = 9; 
    row_chars = 'ABCDEFGHJ'; 
    valid_mask = true(rows, cols);
    labels_cell = cell(rows, cols);
    
    % Mask GND/REF (Datasheet specs)
    valid_mask(1, [4, 5]) = false; % A4, A5
    valid_mask(2, [4, 5]) = false; % B4, B5
    valid_mask(8, [1, 8]) = false; % H1, H8
    valid_mask(9, [1, 8]) = false; % J1, J8
    
    for r = 1:rows
        for c = 1:cols
            if valid_mask(r,c)
                labels_cell{r,c} = [row_chars(r), num2str(c)];
            end
        end
    end

    % --- STARTUP: LOAD OR NEW? ---
    % Default initialization
    init_x = 0; 
    init_y = 0; 
    init_rot = 0;
    
    if exist(save_file, 'file')
        choice = questdlg('Existing alignment found. Load it or start fresh?', ...
            'Startup Mode', 'Load Existing', 'Start New', 'Load Existing');
        
        if strcmp(choice, 'Load Existing')
            try
                loaded_data = load(save_file);
                if isfield(loaded_data, 'AlignmentParams')
                    init_x = loaded_data.AlignmentParams.off_x;
                    init_y = loaded_data.AlignmentParams.off_y;
                    init_rot = loaded_data.AlignmentParams.rot_deg;
                    fprintf('Loaded alignment: X=%.2f, Y=%.2f, Rot=%.1f\n', init_x, init_y, init_rot);
                else
                    warndlg('File exists but contains no alignment parameters (old version?). Starting new.', 'Load Failed');
                end
            catch
                warndlg('Error loading file. Starting new.', 'Load Error');
            end
        end
    end

    % --- GUI SETUP ---
    img_display = img;
    img_display(img < floor_val) = floor_val;
    
    f = figure('Name', 'FlexMEA72 Aligner v5 (Load/Save)', 'Color', 'w', 'Position', [100 100 1000 850]);
    ax = axes('Parent', f, 'Position', [0.05 0.3 0.9 0.65]);
    
    % Draw Background
    if ~isempty(bg_rgb), image(bg_rgb, 'Parent', ax); end
    hold(ax, 'on');
    
    % Draw Heatmap
    h_heatmap = imagesc(img_display, 'Parent', ax);
    if ~isempty(bg_rgb)
        alpha_data = (img_display - floor_val) / (sat_val - floor_val);
        alpha_data(alpha_data < 0) = 0; alpha_data(alpha_data > 1) = 1;
        set(h_heatmap, 'AlphaData', alpha_data.^1.5);
    end
    
    colormap(ax, jet(256));
    caxis(ax, [floor_val, sat_val]);
    axis(ax, 'image', 'off');
    title(ax, 'Align MEA -> Click Export (Saves to data/MEA_Map.mat)');
    
    % --- PLOT OBJECTS ---
    h_grid_pts = plot(ax, NaN, NaN, 'o', 'MarkerSize', 11, ...
        'MarkerEdgeColor', 'k', 'LineWidth', 1.2, 'MarkerFaceColor', 'none');
    
    num_elecs = sum(valid_mask(:));
    h_texts = gobjects(num_elecs, 1);
    idx = 1;
    for r = 1:rows
        for c = 1:cols
            if valid_mask(r,c)
                h_texts(idx) = text(ax, 0, 0, labels_cell{r,c}, ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                    'FontSize', 8, 'FontWeight', 'bold', 'Color', 'k'); 
                idx = idx + 1;
            end
        end
    end
    
    % --- CONTROLS ---
    p = uipanel('Parent', f, 'Position', [0.05 0.02 0.9 0.25], 'BackgroundColor', 'w');
    
    % Helper to sanitize slider inputs (in case loaded values are out of bounds)
    safe_x = max(min(init_x, 5), -5);
    safe_y = max(min(init_y, 5), -5);
    safe_rot = max(min(init_rot, 180), -180);

    % Sliders (Initialized with safe_x/y/rot)
    uicontrol('Parent', p, 'Style', 'text', 'String', 'X Offset (mm)', 'Position', [50 160 100 20], 'BackgroundColor', 'w');
    sld_x = uicontrol('Parent', p, 'Style', 'slider', 'Min', -5, 'Max', 5, 'Value', safe_x, 'Position', [50 130 250 20], 'Callback', @update_grid);
    txt_x = uicontrol('Parent', p, 'Style', 'text', 'String', sprintf('%.2f', safe_x), 'Position', [310 130 50 20], 'BackgroundColor', 'w');
        
    uicontrol('Parent', p, 'Style', 'text', 'String', 'Y Offset (mm)', 'Position', [50 100 100 20], 'BackgroundColor', 'w');
    sld_y = uicontrol('Parent', p, 'Style', 'slider', 'Min', -5, 'Max', 5, 'Value', safe_y, 'Position', [50 70 250 20], 'Callback', @update_grid);
    txt_y = uicontrol('Parent', p, 'Style', 'text', 'String', sprintf('%.2f', safe_y), 'Position', [310 70 50 20], 'BackgroundColor', 'w');
        
    uicontrol('Parent', p, 'Style', 'text', 'String', 'Rotation (deg)', 'Position', [450 160 100 20], 'BackgroundColor', 'w');
    sld_rot = uicontrol('Parent', p, 'Style', 'slider', 'Min', -180, 'Max', 180, 'Value', safe_rot, 'Position', [450 130 250 20], 'Callback', @update_grid);
    txt_rot = uicontrol('Parent', p, 'Style', 'text', 'String', sprintf('%.1f', safe_rot), 'Position', [710 130 50 20], 'BackgroundColor', 'w');
    
    % Toggles
    chk_heat = uicontrol('Parent', p, 'Style', 'checkbox', 'String', 'Show Heatmap', 'Value', 1, ...
        'Position', [450 90 150 20], 'BackgroundColor', 'w', 'Callback', @update_grid);
    
    chk_lbl = uicontrol('Parent', p, 'Style', 'checkbox', 'String', 'Show Labels', 'Value', 1, ...
        'Position', [600 90 150 20], 'BackgroundColor', 'w', 'Callback', @update_grid);
        
    % EXPORT BUTTON
    uicontrol('Parent', p, 'Style', 'pushbutton', 'String', 'SAVE & EXPORT', ...
        'FontWeight', 'bold', 'FontSize', 12, 'BackgroundColor', [0.8 1 0.8], ...
        'Position', [450 20 300 40], 'Callback', @export_data);
        
    % Initial Update
    update_grid();
    
    % --- CALCULATION LOGIC ---
    function [X_final, Y_final] = calculate_positions(off_x, off_y, rot_deg)
        px_spacing_x = mea_pitch_x_um / pixel_size_um;
        px_spacing_y = mea_pitch_y_um / pixel_size_um;
        dx_px = (off_x * 1000) / pixel_size_um;
        dy_px = (off_y * 1000) / pixel_size_um;
        
        grid_w = (cols-1) * px_spacing_x;
        grid_h = (rows-1) * px_spacing_y;
        x_base = ((1:cols) - 1) * px_spacing_x - grid_w/2;
        y_base = ((1:rows) - 1) * px_spacing_y - grid_h/2;
        [X, Y] = meshgrid(x_base, y_base);
        
        theta = deg2rad(rot_deg);
        X_rot = X * cos(theta) - Y * sin(theta);
        Y_rot = X * sin(theta) + Y * cos(theta);
        
        X_final = X_rot + W/2 + dx_px;
        Y_final = Y_rot + H/2 + dy_px;
    end

    % --- UPDATE DISPLAY ---
    function update_grid(~, ~)
        off_x = sld_x.Value;
        off_y = sld_y.Value;
        rot_deg = sld_rot.Value;
        
        txt_x.String = sprintf('%.2f', off_x);
        txt_y.String = sprintf('%.2f', off_y);
        txt_rot.String = sprintf('%.1f', rot_deg);
        
        if chk_heat.Value, set(h_heatmap, 'Visible', 'on'); else, set(h_heatmap, 'Visible', 'off'); end
        if chk_lbl.Value, set(h_texts, 'Visible', 'on'); else, set(h_texts, 'Visible', 'off'); end
        
        [X_final, Y_final] = calculate_positions(off_x, off_y, rot_deg);
        
        set(h_grid_pts, 'XData', X_final(valid_mask), 'YData', Y_final(valid_mask));
        
        X_flat = X_final'; Y_flat = Y_final'; mask_flat = valid_mask';
        X_valid = X_flat(mask_flat); Y_valid = Y_flat(mask_flat);
        
        for k = 1:length(h_texts)
            set(h_texts(k), 'Position', [X_valid(k) Y_valid(k) 0]);
        end
    end

    % --- EXPORT FUNCTION ---
    function export_data(~, ~)
        off_x = sld_x.Value; off_y = sld_y.Value; rot_deg = sld_rot.Value;
        [X_final, Y_final] = calculate_positions(off_x, off_y, rot_deg);
        
        % 1. Create Table
        Labels = {}; X_px = []; Y_px = []; In_Image = [];
        count_in = 0;
        
        for r = 1:rows
            for c = 1:cols
                if valid_mask(r,c)
                    xx = X_final(r,c);
                    yy = Y_final(r,c);
                    is_inside = (xx >= 1 && xx <= W && yy >= 1 && yy <= H);
                    
                    Labels{end+1,1} = labels_cell{r,c}; %#ok<AGROW>
                    X_px(end+1,1) = xx; %#ok<AGROW>
                    Y_px(end+1,1) = yy; %#ok<AGROW>
                    In_Image(end+1,1) = is_inside; %#ok<AGROW>
                    
                    if is_inside, count_in = count_in + 1; end
                end
            end
        end
        MEA_Map = table(Labels, X_px, Y_px, logical(In_Image));
        
        % 2. Create Parameter Struct (For resuming later)
        AlignmentParams.off_x = off_x;
        AlignmentParams.off_y = off_y;
        AlignmentParams.rot_deg = rot_deg;
        
        % 3. Save to Base Workspace & File
        assignin('base', 'MEA_Map', MEA_Map);
        
        if ~exist(save_dir, 'dir'), mkdir(save_dir); end
        save(save_file, 'MEA_Map', 'AlignmentParams');
        
        fprintf('\n=== MEA EXPORT ===\n');
        fprintf('Total Electrodes: %d\n', length(Labels));
        fprintf('Saved "MEA_Map" and params to: %s\n', save_file);
        msgbox(sprintf('Saved to %s\n%d electrodes inside.', save_file, count_in), 'Success');
    end
end