input_file = 'converted__500/led_E0B0.h5';
output_dir = 'data/figures';
reference_frames = 70:200;

% Optical Flow Configuration
OF_config = struct(...
    'alpha', 1.0, ...
    'sigma', [2.0, 2.0, 0.2; 1.0, 1.0, 0.1], ...
    'weight', [0.8, 0.2], ...
    'quality_setting', 'quality', ...
    'bin_size', 1, ...
    'buffer_size', 100, ...
    'save_w', true, ...
    'save_meta_info', true, ...
    'verbose', true);

fprintf('--- STARTING EVALUATION: SECTION 4.1 ---\n');
fprintf('Processing File: %s\n', input_file);

% 2. Execute Motion Correction
try
    output_h5 = vsd_motion_correct(input_file, ...
        'DatasetName', 'image_stack', ...
        'OutputFolder', output_dir, ...
        'ReferenceFrames', reference_frames, ...
        'OF', OF_config);
    
    fprintf('Motion correction pipeline completed successfully.\n');
    fprintf('Output saved to: %s\n', output_h5);
    
catch ME
    fprintf('ERROR during motion correction: %s\n', ME.message);
    return;
end

stats_file = fullfile(output_dir, 'statistics.mat');

if exist(stats_file, 'file')
    stats = load(stats_file);
    fprintf('\n--- QUANTITATIVE METRICS FOR THESIS DRAFTING ---\n');
    
    if isfield(stats, 'mean_disp')
        fprintf('Metric: Mean Displacement | Value: %.4f px | SD: %.4f px\n', ...
            mean(stats.mean_disp), std(stats.mean_disp));
    end
    
    if isfield(stats, 'max_disp')
        fprintf('Metric: Maximum Peak Displacement | Value: %.4f px\n', max(stats.max_disp));
    end
    
    if isfield(stats, 'mean_translation')
        fprintf('Metric: Global Translation | Value: %.4f px\n', mean(stats.mean_translation));
    end
else
    fprintf('Warning: statistics.mat not found. Ensure save_meta_info is true.\n');
end

% 4. Visualization (Triggers the plots for the PDF)
% If you have motion_comp_figure_generator.m, we call it here.
% Otherwise, we can plot the displacement vectors directly.
if exist('motion_comp_figure_generator.m', 'file') && exist('stats', 'var')
    fprintf('Generating validation figures...\n');
    motion_comp_figure_generator(stats); 
else
    % Fallback plot if figure generator is missing
    if exist('stats', 'var') && isfield(stats, 'mean_disp')
        figure('Name', 'Displacement Over Time');
        plot(stats.mean_disp, 'LineWidth', 1.5);
        title('Mean Displacement Magnitude per Frame');
        xlabel('Frame Number');
        ylabel('Displacement (pixels)');
        grid on;
    end
end

fprintf('\n--- END OF EVALUATION ---\n');