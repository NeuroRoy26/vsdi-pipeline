%% --- 1. Load Your Averaged Data ---
 h5_file = 'C:/Roy/MSc/Thesis/Scripts/data/averaged_movie_E0B0-E0B3.h5';
% h5_file = 'C:/Roy/MSc/Thesis/Scripts/data/led_E0B3_dff.h5';

dff_averaged = h5read(h5_file, '/functional_dff');
[H, W, T] = size(dff_averaged); % T should be 150

%% --- 2. Define Grid and Time Parameters ---
grid_size = 5; % As requested, a 5x5 grid

% --- Timing Parameters ---
stim_onset_frame = 76; % Binned frame 76
ms_per_binned_frame = 10.0; % 2.0 ms/frame * 5 frame bin
time_ms = (0:T-1) * ms_per_binned_frame;
stim_onset_ms = (stim_onset_frame - 1) * ms_per_binned_frame; % 750 ms

% --- Grid Parameters ---
sq_height = floor(H / grid_size);
sq_width = floor(W / grid_size);

fprintf('Generating 5x5 grid of activity traces...\n');

%% --- 3. Create the 5x5 Figure ---
figure(1);
set(gcf, 'Color', 'w'); % White background

% Determine the min/max signal for consistent Y-axis scaling
% This makes the plots comparable. From activitytrace.jpg
plot_y_min = -0.004; % From your baseline noise
plot_y_max = 0.006;  % Just above your peak

%% --- 4. Loop Through Each Grid Square and Plot ---
plot_index = 1;
for i = 1:grid_size % Rows (Y)
    for j = 1:grid_size % Columns (X)
        
        % --- a. Define the current ROI ---
        y_start = (i-1) * sq_height + 1;
        y_end   = i * sq_height;
        x_start = (j-1) * sq_width + 1;
        x_end   = j * sq_width;
        
        % --- b. Extract the time trace for this ROI ---
        roi_slab = dff_averaged(y_start:y_end, x_start:x_end, :);
        trace = squeeze(mean(mean(roi_slab, 1, 'omitnan'), 2, 'omitnan'));
        
        % --- c. Create the subplot ---
        subplot(grid_size, grid_size, plot_index);
        plot(time_ms, trace, 'k', 'LineWidth', 1.5);
        hold on;
        
        % --- d. Add Stimulus Line ---
 %       xline(stim_onset_ms, 'r--', 'LineWidth', 0.5);
        
        % --- e. Format the plot ---
        ylim([plot_y_min, plot_y_max]); % Use consistent Y-axis
        
        % Add title only to the top row
        if i == 1
            title(sprintf('X Grid %d', j));
        end
        % Add Y label only to the first column
        if j == 1
            ylabel(sprintf('Y Grid %d', i));
        end
        
        % Clean up axes
        set(gca, 'FontSize', 8);
        if plot_index < 21 % Hide X-axis labels for top 4 rows
            set(gca, 'XTickLabel', []);
        end
        if j > 1 % Hide Y-axis labels for columns 2-5
            set(gca, 'YTickLabel', []);
        end
        
        plot_index = plot_index + 1;
    end
end

% Add a main title to the entire figure
sgtitle('5x5 Grid of Activity Traces (Averaged \DeltaF/F)');

fprintf('Plot generation complete.\n');