function vsd_interactive_contrast(input_file)
% VSD_INTERACTIVE_CONTRAST_V3
% 1. Scroll through frames to ignore dark start/shutter lag.
% 2. Identify Structural/Functional pattern visually.
% 3. Tune contrast for each channel independently.
% 4. Save processed file.

    %% 1. Input Handling
    if nargin < 1 || isempty(input_file)
        [file, path] = uigetfile('*.h5;*.hdf5', 'Select Cropped VSD File');
        if isequal(file, 0), return; end
        input_file = fullfile(path, file);
    end
    [~, base, ~] = fileparts(input_file);
    
    % Load Data
    info = h5info(input_file);
    dataset_name = info.Datasets(1).Name;
    fprintf('Loading %s ...\n', base);
    data = h5read(input_file, ['/' dataset_name]);
    
    sz = size(data);
    if sz(1) > 500 && sz(1) > sz(3) 
        data = permute(data, [2, 3, 1]);
    end
    [H, W, T] = size(data);

    %% 2. Auto-Contrast Range
    % Calculate range from the middle of the stack (where light is definitely on)
    mid_frames = data(:, :, floor(T/2):min(T, floor(T/2)+20));
    global_min = double(min(mid_frames(:)));
    global_max = double(max(mid_frames(:)));
    fprintf('Estimated active range: %.0f - %.0f\n', global_min, global_max);

    %% 3. GUI Step 1: Pattern Explorer
    % This window lets you scroll until you see the data
    hFigPhase = figure('Name', 'Step 1: Find the Pattern', ...
        'Units', 'normalized', 'Position', [0.2 0.3 0.6 0.5]);
    
    % Axes
    axP = axes('Position', [0.05 0.25 0.9 0.65]);
    hImg = imshow(data(:,:,1), [global_min global_max]);
    title('Scroll to find active frames. Look for "Bright" (Struct) vs "Dim" (Func).');
    
    % Slider to scroll frames
    sldFrame = uicontrol('Style','slider', 'Units','normalized', 'Position',[0.2 0.15 0.6 0.05], ...
        'Min',1, 'Max',min(200, T), 'Value', 1, 'SliderStep', [1/200 10/200], ...
        'Callback', @updateFrame);
    
    lblFrame = uicontrol('Style','text', 'Units','normalized', 'Position',[0.05 0.15 0.1 0.05], 'String', 'Frame: 1');
    
    % Buttons
    uicontrol('Style', 'pushbutton', 'String', 'Current Frame is STRUCTURAL', ...
        'Units', 'normalized', 'Position', [0.1 0.02 0.35 0.1], ...
        'BackgroundColor', [0.8 0.9 1], ...
        'Callback', @(s,e) setPattern(true));
        
    uicontrol('Style', 'pushbutton', 'String', 'Current Frame is FUNCTIONAL', ...
        'Units', 'normalized', 'Position', [0.55 0.02 0.35 0.1], ...
        'BackgroundColor', [1 0.9 0.8], ...
        'Callback', @(s,e) setPattern(false));

    % State
    current_frame_idx = 1;
    idx_struct = [];
    idx_func = [];
    
    waitfor(hFigPhase);
    
    if isempty(idx_struct)
        disp('Cancelled.');
        return;
    end

    %% 4. GUI Step 2: Contrast Tuning (Same as before)
    fprintf('Opening Contrast Tuner...\n');
    
    % Sample averages (ignore the first 10 frames of the stack to avoid shutter noise)
    offset = 20; 
    valid_struct = idx_struct(idx_struct > offset);
    valid_func   = idx_func(idx_func > offset);
    
    s_sample = mean(double(data(:,:,valid_struct(1:min(10,end)))), 3);
    f_sample = mean(double(data(:,:,valid_func(1:min(10,end)))), 3);

    hFig = figure('Name', ['Step 2: Tune Contrast (' base ')'], ...
        'Units', 'normalized', 'Position', [0.1 0.1 0.8 0.6]);
    
    % STRUCTURAL (Left)
    axS = axes('Position', [0.05 0.4 0.4 0.55]);
    imshow(s_sample, [global_min global_max]); title('Structural');
    
    sldS_Low = uicontrol('Style','slider', 'Units','normalized', 'Position',[0.05 0.2 0.4 0.05], ...
        'Min',0, 'Max',65535, 'Value', global_min, 'Callback', @updateS);
    sldS_High = uicontrol('Style','slider', 'Units','normalized', 'Position',[0.05 0.1 0.4 0.05], ...
        'Min',0, 'Max',65535, 'Value', global_max, 'Callback', @updateS);
    
    % FUNCTIONAL (Right)
    axF = axes('Position', [0.55 0.4 0.4 0.55]);
    imshow(f_sample, [global_min global_max]); title('Functional');
    
    sldF_Low = uicontrol('Style','slider', 'Units','normalized', 'Position',[0.55 0.2 0.4 0.05], ...
        'Min',0, 'Max',65535, 'Value', global_min, 'Callback', @updateF);
    sldF_High = uicontrol('Style','slider', 'Units','normalized', 'Position',[0.55 0.1 0.4 0.05], ...
        'Min',0, 'Max',65535, 'Value', global_max, 'Callback', @updateF);
        
    uicontrol('Style','pushbutton', 'String', 'APPLY & SAVE', ...
        'Units','normalized', 'Position', [0.4 0.02 0.2 0.06], ...
        'BackgroundColor', 'g', 'Callback', @saveData);
        
    guidata(hFig, struct('s',s_sample, 'f',f_sample));

    %% Nested Functions (Step 1)
    function updateFrame(src, ~)
        val = round(src.Value);
        current_frame_idx = val;
        set(lblFrame, 'String', sprintf('Frame: %d', val));
        set(hImg, 'CData', data(:,:,val));
    end

    function setPattern(is_struct)
        if is_struct
            % Current is Structural -> Odd/Even based on current index
            if mod(current_frame_idx, 2) ~= 0 % Odd
                idx_struct = 1:2:T; idx_func = 2:2:T;
            else % Even
                idx_struct = 2:2:T; idx_func = 1:2:T;
            end
        else
            % Current is Functional
            if mod(current_frame_idx, 2) ~= 0 % Odd
                idx_func = 1:2:T; idx_struct = 2:2:T;
            else % Even
                idx_func = 2:2:T; idx_struct = 1:2:T;
            end
        end
        fprintf('Pattern set based on Frame %d.\n', current_frame_idx);
        close(hFigPhase);
    end

    %% Nested Functions (Step 2)
    function updateS(~,~)
        d = guidata(hFig);
        low = get(sldS_Low, 'Value'); high = get(sldS_High, 'Value');
        if low>=high, low=high-1; end
        set(axS, 'CLim', [low high]);
    end

    function updateF(~,~)
        d = guidata(hFig);
        low = get(sldF_Low, 'Value'); high = get(sldF_High, 'Value');
        if low>=high, low=high-1; end
        set(axF, 'CLim', [low high]);
    end

    function saveData(~,~)
        s_min = get(sldS_Low, 'Value'); s_max = get(sldS_High, 'Value');
        f_min = get(sldF_Low, 'Value'); f_max = get(sldF_High, 'Value');
        close(hFig);
        
        fprintf('Processing and Saving...\n');
        data_out = data;
        
        % Structural
        S = double(data(:,:,idx_struct));
        S = (S - s_min) ./ (s_max - s_min);
        S(S<0)=0; S(S>1)=1;
        data_out(:,:,idx_struct) = cast(S * 65535, class(data));
        
        % Functional
        F = double(data(:,:,idx_func));
        F = (F - f_min) ./ (f_max - f_min);
        F(F<0)=0; F(F>1)=1;
        data_out(:,:,idx_func) = cast(F * 65535, class(data));
        
        out_file = fullfile(fileparts(input_file), [base '_contrast.h5']);
        if exist(out_file,'file'), delete(out_file); end
        
        h5create(out_file, ['/' dataset_name], size(data_out), 'Datatype', class(data_out));
        h5write(out_file, ['/' dataset_name], data_out);
        fprintf('Saved: %s\n', out_file);
    end
end