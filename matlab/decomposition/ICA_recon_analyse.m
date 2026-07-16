% ICA_recon_analyse_simplified.m
% ICA component reconstruction and interactive analysis
% run after PCA_ICA_decomp.m
% Simplified version: no trigger detection, with colormap normalization

fprintf('=== ICA RECONSTRUCTION & INTERACTIVE VIEWER ===\n\n');

%% 1. LOAD ICA DATA
if ~exist('ica_maps', 'var') || ~exist('ica_timecourses', 'var') || ~exist('Fs', 'var')
    error(['Required variables not found!\n' ...
           'Run PCA_ICA_decomp.m first or load variables:\n' ...
           'ica_maps, ica_timecourses, H, W, T, Fs']);
end

[H, W, num_ICs] = size(ica_maps);
T = size(ica_timecourses, 1);

fprintf('Found %d ICA components\n', num_ICs);
fprintf('Dimensions: %d x %d pixels, %d frames\n\n', H, W, T);

%% 2. SELECT COMPONENTS FOR RECONSTRUCTION
fprintf('--- COMPONENT SELECTION ---\n');
fprintf('Enter component numbers to reconstruct separately (e.g., [1 3 5])\n');
selected_ICs = input('Components: ');

% Validate selection
selected_ICs = unique(selected_ICs(:))';
selected_ICs(selected_ICs < 1 | selected_ICs > num_ICs) = [];

if isempty(selected_ICs)
    error('Selection invalid or empty.');
end

fprintf('Selected components: %s\n', mat2str(selected_ICs));

% Sign assignment
sign_ass = input('Sign assignment (+1 or -1, default=1): ');
if isempty(sign_ass), sign_ass = 1; end

%% 3. RECONSTRUCT EACH COMPONENT SEPARATELY
fprintf('\n--- RECONSTRUCTING INDIVIDUAL COMPONENTS ---\n');

maps_flat = reshape(ica_maps, H*W, num_ICs);
num_selected = length(selected_ICs);

% Store individual reconstructions
individual_movies = cell(num_selected, 1);
individual_traces = zeros(T, num_selected);

for i = 1:num_selected
    ic_idx = selected_ICs(i);
    fprintf('Reconstructing IC %d...\n', ic_idx);
    
    % Single component reconstruction
    Xrec = sign_ass * (maps_flat(:, ic_idx) * ica_timecourses(:, ic_idx)');
    individual_movies{i} = reshape(Xrec, H, W, T);
    
    % Extract mean trace
    individual_traces(:, i) = squeeze(mean(mean(individual_movies{i}, 1), 2));
end

fprintf('Individual reconstructions complete.\n');

%% 4. SELECT NUMBER OF COMPONENTS TO DISPLAY
fprintf('\n--- DISPLAY CONFIGURATION ---\n');
fprintf('How many components to display in interactive viewer?\n');
num_display = input(sprintf('Enter number (1-%d, default=all): ', num_selected));
if isempty(num_display) || num_display < 1 || num_display > num_selected
    num_display = num_selected;
end

display_indices = 1:num_display;

%% 5. CREATE INTERACTIVE GUI
f = figure('Name', 'ICA Interactive Viewer', ...
           'Color', 'w', 'Position', [50 50 1400 900], ...
           'KeyPressFcn', @keyPress);

% Calculate subplot layout
n_cols = min(3, num_display);
n_rows = ceil(num_display / n_cols);

% Shared data structure
gui_data = struct();
gui_data.current_frame = 1;
gui_data.max_frames = T;
gui_data.movies = individual_movies;
gui_data.traces = individual_traces;
gui_data.selected_ICs = selected_ICs;
gui_data.time_axis = (1:T) / Fs;
gui_data.Fs = Fs;
gui_data.display_indices = display_indices;
gui_data.n_rows = n_rows;
gui_data.n_cols = n_cols;
gui_data.normalize_colormap = false;

% Total subplot rows: 1 (trace) + n_rows (spatial maps)
total_rows = 1 + n_rows;

% --- TOP: Signal Traces (all selected components) ---
gui_data.ax1 = subplot(total_rows, n_cols, 1:n_cols);
hold on;
gui_data.trace_lines = cell(num_display, 1);
colors = lines(num_display);

for i = 1:num_display
    idx = display_indices(i);
    ic_num = selected_ICs(idx);
    
    gui_data.trace_lines{i} = plot(gui_data.time_axis, individual_traces(:, idx), ...
        'Color', colors(i,:), 'LineWidth', 1.2, 'DisplayName', sprintf('IC %d', ic_num));
end

gui_data.click_line = xline(gui_data.time_axis(1), 'b-', 'LineWidth', 2, 'DisplayName', 'Current Frame');
title('Component Signal Traces (Click to view frame)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Fluorescence (a.u.)'); 
xlabel('Time (s)');
legend('Location', 'best');
grid on; axis tight;
set(gca, 'ButtonDownFcn', @clickTrace);

% --- SPATIAL MAPS: Display selected components ---
gui_data.img_handles = cell(num_display, 1);
gui_data.ax_maps = cell(num_display, 1);
gui_data.clims = cell(num_display, 1);

for i = 1:num_display
    idx = display_indices(i);
    ic_num = selected_ICs(idx);
    
    row = ceil(i / n_cols);
    col = mod(i - 1, n_cols) + 1;
    
    % Calculate linear index: skip first row (n_cols positions)
    linear_idx = n_cols + (row-1)*n_cols + col;
    
    gui_data.ax_maps{i} = subplot(total_rows, n_cols, linear_idx);
    
    gui_data.img_handles{i} = imagesc(individual_movies{idx}(:,:,1));
    colormap(gui_data.ax_maps{i}, jet); 
    colorbar; 
    axis image off;
    
    % Store global color limits for this component
    all_data = individual_movies{idx}(:);
    gui_data.clims{i} = [min(all_data), max(all_data)];
    
    title(sprintf('IC %d | Frame 1 / %d', ic_num, T), ...
          'FontSize', 10, 'FontWeight', 'bold');
end

% --- BOTTOM: Slider and Controls ---
% Normalize colormap checkbox
gui_data.normalize_checkbox = uicontrol('Style', 'checkbox', ...
    'String', 'Normalize Colormap (per frame)', ...
    'Value', 0, ...
    'Units', 'normalized', 'Position', [0.1 0.07 0.2 0.02], ...
    'BackgroundColor', 'w', 'FontSize', 9, ...
    'Callback', @normalizeCallback);

% Slider
gui_data.slider = uicontrol('Style', 'slider', ...
    'Min', 1, 'Max', T, 'Value', 1, ...
    'Units', 'normalized', 'Position', [0.1 0.04 0.8 0.02], ...
    'SliderStep', [1/(T-1), 10/(T-1)], ...
    'Callback', @sliderCallback);

% Instructions
uicontrol('Style', 'text', 'String', ...
    '← → Arrow Keys: Navigate frames  |  Click on trace: Jump to time  |  Slider: Smooth navigation', ...
    'Units', 'normalized', 'Position', [0.1 0.01 0.8 0.02], ...
    'BackgroundColor', 'w', 'FontSize', 9, 'FontWeight', 'bold');

% Store data in figure
guidata(f, gui_data);

fprintf('\n>>> INTERACTIVE MODE <<<\n');
fprintf('  • Arrow Keys (←/→): Move one frame\n');
fprintf('  • Click on trace: Jump to that time\n');
fprintf('  • Slider: Smooth navigation\n');
fprintf('  • Checkbox: Toggle colormap normalization\n');
fprintf('  • Close window to exit\n\n');
fprintf('Displaying %d component(s): %s\n', num_display, mat2str(selected_ICs(display_indices)));

%% CALLBACK FUNCTIONS

    function keyPress(src, event)
        data = guidata(src);
        
        switch event.Key
            case 'rightarrow'
                data.current_frame = min(data.current_frame + 1, data.max_frames);
                updateFrame(src, data);
            case 'leftarrow'
                data.current_frame = max(data.current_frame - 1, 1);
                updateFrame(src, data);
        end
    end

    function sliderCallback(src, ~)
        fig = ancestor(src, 'figure');
        data = guidata(fig);
        data.current_frame = round(get(src, 'Value'));
        updateFrame(fig, data);
    end

    function clickTrace(src, event)
        fig = ancestor(src, 'figure');
        data = guidata(fig);
        
        click_pos = event.IntersectionPoint(1);
        frame_idx = round(click_pos * data.Fs);
        frame_idx = max(1, min(frame_idx, data.max_frames));
        
        data.current_frame = frame_idx;
        updateFrame(fig, data);
    end

    function normalizeCallback(src, ~)
        fig = ancestor(src, 'figure');
        data = guidata(fig);
        data.normalize_colormap = get(src, 'Value');
        guidata(fig, data);
        updateFrame(fig, data);
    end

    function updateFrame(fig, data)
        current_time = data.time_axis(data.current_frame);
        
        % Update all spatial maps
        for i = 1:length(data.display_indices)
            idx = data.display_indices(i);
            ic_num = data.selected_ICs(idx);
            
            current_img = data.movies{idx}(:,:,data.current_frame);
            set(data.img_handles{i}, 'CData', current_img);
            
            % Set color limits based on normalization setting
            if data.normalize_colormap
                % Per-frame normalization
                caxis(data.ax_maps{i}, [min(current_img(:)), max(current_img(:))]);
            else
                % Global normalization (across all frames)
                caxis(data.ax_maps{i}, data.clims{i});
            end
            
            title(data.ax_maps{i}, sprintf('IC %d | Frame %d / %d | t=%.3fs', ...
                  ic_num, data.current_frame, data.max_frames, current_time), ...
                  'FontSize', 10, 'FontWeight', 'bold');
        end
        
        % Update vertical line on trace
        set(data.click_line, 'Value', current_time);
        
        % Update slider
        set(data.slider, 'Value', data.current_frame);
        
        guidata(fig, data);
    end

fprintf('\n=== ANALYSIS COMPLETE ===\n');

%% 6. SIGNAL PREPROCESSING METRICS & DIAGNOSTICS
fprintf('\n=================================================================================\n');
fprintf('                     DIAGNOSTIC METRICS FOR SELECTED COMPONENTS                  \n');
fprintf('=================================================================================\n');
fprintf('Use these metrics to decide if you need to Detrend, Invert, or Normalize.\n\n');
fprintf('%-5s | %-8s | %-8s | %-8s | %-8s | %-12s | %-15s\n', ...
        'IC#', 'Range', 'Skewness', 'Kurtosis', 'Drift(%)', 'Noise(Est)', 'Action Suggestion');
fprintf('---------------------------------------------------------------------------------\n');

% Loop through the selected components
for i = 1:num_selected
    ic_num = selected_ICs(i);
    trace = individual_traces(:, i);
    
    % --- 1. SIGNAL SHAPE (Skew & Kurtosis) ---
    sk = skewness(trace);
    ku = kurtosis(trace);
    
    % --- 2. DRIFT ANALYSIS ---
    x_axis = (1:length(trace))';
    p = polyfit(x_axis, trace, 1); 
    linear_trend = polyval(p, x_axis);
    
    trace_range = max(trace) - min(trace);
    total_drift_amt = abs(linear_trend(end) - linear_trend(1));
    drift_percent = (total_drift_amt / trace_range) * 100;
    
    % --- 3. NOISE ESTIMATION ---
    sorted_vals = sort(trace);
    noise_est = std(sorted_vals(1:round(end*0.5)));
    
    % --- 4. ACTION SUGGESTION ---
    suggestions = {};
    
    if sk < -0.2
        suggestions{end+1} = 'INVERT';
    elseif sk >= -0.2 && sk <= 0.2 && ku < 3.5
        suggestions{end+1} = 'NOISE?';
    end
    
    if drift_percent > 15
        suggestions{end+1} = 'DETREND';
    end
    
    if trace_range > 1000 || trace_range < 0.1
        suggestions{end+1} = 'RESCALE';
    end
    
    if isempty(suggestions)
        suggestion_str = 'OK';
    else
        suggestion_str = strjoin(suggestions, '+');
    end

    % --- 5. PRINT ROW ---
    fprintf('%-5d | %-8.2f | %-8.2f | %-8.2f | %-8.1f%%    | %-12.4f | %-15s\n', ...
            ic_num, trace_range, sk, ku, drift_percent, noise_est, suggestion_str);
end

fprintf('---------------------------------------------------------------------------------\n');
fprintf('INTERPRETATION GUIDE:\n');
fprintf('1. SKEWNESS:  If negative (e.g., -1.5), your spikes are pointing DOWN. -> Multiply by -1.\n');
fprintf('2. KURTOSIS:  If low (~3.0), the component is likely just Gaussian noise.\n');
fprintf('3. DRIFT(%%):  If high (>15%%), the baseline is wandering. -> Use `detrend(trace)`.\n');
fprintf('4. NOISE:     If Noise(Est) is very close to Std(Total), the SNR is very poor.\n');
fprintf('=================================================================================\n');