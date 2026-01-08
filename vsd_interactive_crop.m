function vsd_interactive_crop(input_file)
% VSD_INTERACTIVE_CROP
% Loads a VSD HDF5 file, opens a GUI for interactive cropping,
% and saves a new file with the suffix "_cropped.h5".
%
% Usage:
%   vsd_interactive_crop('path/to/file.h5')
%   vsd_interactive_crop() % Opens file browser

    %% 1. Select Input File
    if nargin < 1 || isempty(input_file)
        [file, path] = uigetfile('*.h5;*.hdf5', 'Select VSD HDF5 File');
        if isequal(file, 0)
            disp('User cancelled.');
            return;
        end
        input_file = fullfile(path, file);
    end

    [~, baseName, ~] = fileparts(input_file);
    fprintf('Processing: %s\n', input_file);

    %% 2. Load Data (Smart Loading)
    % We attempt to find the correct dataset name automatically
    info = h5info(input_file);
    
    % Look for common VSD dataset names, or pick the largest one
    possible_names = {'image_stack', 'data', 'images'};
    dataset_name = '';
    
    % Check heuristics
    for i = 1:length(info.Datasets)
        if ismember(info.Datasets(i).Name, possible_names)
            dataset_name = info.Datasets(i).Name;
            break;
        end
    end
    % Fallback: just take the first one if we couldn't guess
    if isempty(dataset_name)
        dataset_name = info.Datasets(1).Name;
    end
    
    fprintf('Reading dataset: /%s ...\n', dataset_name);
    full_data = h5read(input_file, ['/' dataset_name]);
    
    % --- Reorientation Logic (Matches your previous script) ---
    sz = size(full_data);
    % Heuristic: If dim 1 is ~1500, it's likely frames-first. 
    % We want [Height, Width, Frames]
    if sz(1) > 500 && sz(1) < 5000 && sz(1) > sz(2) && sz(1) > sz(3)
         % This is a loose heuristic based on your previous script's "1500" check
         full_data = permute(full_data, [2, 3, 1]);
         fprintf('Reoriented data to Frames-Last format.\n');
    elseif sz(2) > sz(1) && sz(2) > sz(3) && sz(2) > 500
         full_data = permute(full_data, [1, 3, 2]);
         fprintf('Reoriented data to Frames-Last format.\n');
    end
    
    [H, W, T] = size(full_data);
    fprintf('Original Dimensions: %d x %d (Frames: %d)\n', H, W, T);

    %% 3. GUI Interaction
    % Use the average of the first 10 frames for better visibility of structure
    preview_frame = mean(full_data(:, :, 1:min(10, T)), 3);
    
    hFig = figure('Name', ['Crop Tool: ' baseName], 'NumberTitle', 'off');
    imshow(preview_frame, []);
    title({'Draw a rectangle to crop.', 'Double-click inside the box to confirm.', 'Close window to cancel.'});
    
    % Maximize window for easier selection
    set(hFig, 'WindowState', 'maximized');

    % Create the interactive rectangle
    % We initialize it to the full image size minus a small margin
    margin = 20;
    rect_roi = drawrectangle('Position', [margin, margin, W-2*margin, H-2*margin], ...
                             'Color', 'r', 'LineWidth', 2);
    
    % Wait for user to double-click the ROI
    customWait(rect_roi);
    
    if ~isvalid(hFig)
        disp('Window closed. Operation cancelled.');
        return;
    end
    
    % Get position [x, y, w, h]
    pos = round(rect_roi.Position);
    close(hFig);
    
    %% 4. Validate Coordinates
    % Ensure crop is within bounds
    x_start = max(1, pos(1));
    y_start = max(1, pos(2));
    width   = pos(3);
    height  = pos(4);
    
    x_end = min(W, x_start + width - 1);
    y_end = min(H, y_start + height - 1);
    
    fprintf('Cropping to X: %d-%d, Y: %d-%d\n', x_start, x_end, y_start, y_end);

    %% 5. Apply Crop
    cropped_data = full_data(y_start:y_end, x_start:x_end, :);
    
    %% 6. Save Output
    output_filename = fullfile(fileparts(input_file), [baseName '_cropped.h5']);
    if exist(output_filename, 'file')
        delete(output_filename); 
    end
    
    fprintf('Saving to %s ...\n', output_filename);
    
    % We use the same dataset name as input for consistency
    h5create(output_filename, ['/' dataset_name], size(cropped_data), 'Datatype', class(cropped_data));
    h5write(output_filename, ['/' dataset_name], cropped_data);
    
    fprintf('Done! New dimensions: %d x %d x %d\n', size(cropped_data));

end

function customWait(hROI)
% Listens for double-click on the ROI to resume execution
    l = addlistener(hROI, 'ROIClicked', @clickCallback);
    uiwait;
    delete(l);
    function clickCallback(~, evt)
        if strcmp(evt.SelectionType, 'double')
            uiresume;
        end
    end
end