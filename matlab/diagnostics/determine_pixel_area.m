% determine_pixel_area.m
% -------------------------------------------------------------------------
% Inspect and determine pixel physical area for a VSD dataset (MATLAB).
% - Attempts to read pixel calibration from HDF5 metadata.
% - If metadata isn't available, will auto-fill calibration when it detects
%   the known ROI crop size (540 x 516) and uses the lab's full-sensor FOV.
% - Otherwise it offers interactive/manual calibration options.
% - Saves calibration to data/pixel_calibration.mat by default.
%
% Usage:
%   determine_pixel_area();                % uses default HDF5 path
%   determine_pixel_area('path/to/file.h5');
% -------------------------------------------------------------------------
% the dataset i am using has:- Pixel size: ~10.7 µm per pixel
% Pixel area: ~1.1 × 10⁻⁴ mm² per pixel

function determine_pixel_area(h5file)
if nargin < 1 || isempty(h5file)
    h5file = 'data/averaged_movie_E0B0-B3.h5';
end

fprintf('Pixel area inspector\n');
fprintf('HDF5 file: %s\n\n', h5file);

% Default output calibration file
out_mat = 'data/pixel_calibration.mat';
if ~exist('data','dir')
    mkdir('data');
end

% Known sensor and FOV parameters (adjust if your lab notes differ)
% Full sensor resolution and field-of-view (from lab logs / notes)
full_sensor_width_px  = 1392;   % sensor width in pixels
full_sensor_height_px = 1082;   % sensor height in pixels
full_fov_width_mm  = 6.2;       % mm
full_fov_height_mm = 5.1;       % mm

% Known ROI sizes that imply a crop (common values)
known_roi_sizes = [540, 516];   % width x height (as reported)

%% 1) Try to read calibration from HDF5 metadata/datasets
found = false;
pixel_size_um = []; pixel_area_mm2 = [];

try
    info = h5info(h5file);
    % Search attributes at root
    rootAttrs = info.Attributes;
    names_try = {'pixel_size_um','pixel_size_um_x','pixel_size_x_um','pixel_spacing_um',...
                 'pixelsize','pixel_size','px_um','um_per_pixel','microns_per_pixel','XResolution'};
    for k = 1:numel(rootAttrs)
        aname = lower(rootAttrs(k).Name);
        for n = 1:numel(names_try)
            if contains(aname, lower(names_try{n}))
                val = rootAttrs(k).Value;
                if isnumeric(val) && isfinite(val)
                    pixel_size_um = double(val);
                    found = true;
                    fprintf('Found pixel size attribute "%s" = %g (assumed µm/pixel)\n', rootAttrs(k).Name, pixel_size_um);
                    break;
                end
            end
        end
        if found, break; end
    end
    % Search dataset attributes (e.g., /structural attributes)
    if ~found
        for di = 1:numel(info.Datasets)
            try
                ds = info.Datasets(di);
                for ai = 1:numel(ds.Attributes)
                    aname = lower(ds.Attributes(ai).Name);
                    for n = 1:numel(names_try)
                        if contains(aname, lower(names_try{n}))
                            val = ds.Attributes(ai).Value;
                            if isnumeric(val) && isfinite(val)
                                pixel_size_um = double(val);
                                found = true;
                                fprintf('Found pixel size attribute "%s" in dataset "%s" = %g (µm/pixel)\n', ...
                                    ds.Attributes(ai).Name, ds.Name, pixel_size_um);
                                break;
                            end
                        end
                    end
                    if found, break; end
                end
            catch; end
            if found, break; end
        end
    end
catch ME
    fprintf('Could not read HDF5 metadata: %s\n', ME.message);
end

% If found in metadata -> compute area & save
if found && ~isempty(pixel_size_um)
    pixel_area_mm2 = (pixel_size_um * 1e-3)^2;
    fprintf('\nComputed pixel area from metadata:\n  pixel_size = %.4f µm/pixel\n  pixel_area = %.6e mm^2/pixel\n\n', pixel_size_um, pixel_area_mm2);
    save(out_mat, 'pixel_size_um', 'pixel_area_mm2');
    fprintf('Saved calibration to %s\n', out_mat);
    return;
end

%% 2) Try to load a preview image (/structural or mean of /functional_dff)
img = [];
img_size = [];
try
    % Prefer structural if present
    try
        structData = h5read(h5file, '/structural');
        if ndims(structData) == 3
            img = double(structData(:,:,1));
        else
            img = double(structData);
        end
        img_size = size(img);
        fprintf('Loaded /structural dataset for calibration preview (size %dx%d).\n', img_size(2), img_size(1));
    catch
        % Try functional_dff mean
        try
            func = h5read(h5file, '/functional_dff');
            img = mean(func(:,:,1:min(20,size(func,3))),3);
            img_size = size(img);
            fprintf('Loaded /functional_dff (mean first frames) for preview (size %dx%d).\n', img_size(2), img_size(1));
        catch
            % Try generic /functional
            try
                func = h5read(h5file, '/functional');
                img = mean(func(:,:,1:min(20,size(func,3))),3);
                img_size = size(img);
                fprintf('Loaded /functional (mean first frames) for preview (size %dx%d).\n', img_size(2), img_size(1));
            catch
                fprintf('No preview dataset found in HDF5. Interactive options remain available but no preview shown.\n');
            end
        end
    end
catch
    fprintf('Unable to inspect HDF5 for preview image.\n');
end

%% 3) Auto-fill by ROI size if it matches known crop (540 x 516)
auto_filled = false;
if ~isempty(img_size)
    % img_size typically [H W] (rows, cols)
    Himg = img_size(1);
    Wimg = img_size(2);
    % Check for match with known ROI (either orientation)
    if (Wimg == known_roi_sizes(1) && Himg == known_roi_sizes(2)) || (Wimg == known_roi_sizes(2) && Himg == known_roi_sizes(1))
        fprintf('\nDetected ROI size: %d x %d px which matches known crop. Auto-filling calibration.\n', Wimg, Himg);
        % Map ROI dims to sensor axes:
        % sensor width in mm -> full_sensor_width_px corresponds to image width axis
        % So pixel size along X = full_fov_width_mm / Wimg
        pixel_size_x_mm = full_fov_width_mm / double(Wimg);
        pixel_size_y_mm = full_fov_height_mm / double(Himg);
        pixel_size_um_x = pixel_size_x_mm * 1e3;
        pixel_size_um_y = pixel_size_y_mm * 1e3;
        % Average to a single isotropic estimate (report both)
        pixel_size_um = mean([pixel_size_um_x, pixel_size_um_y]);
        pixel_area_mm2 = pixel_size_x_mm * pixel_size_y_mm;
        fprintf('  Computed from logs:\n');
        fprintf('    pixel_size_x = %.3f µm/pixel\n', pixel_size_um_x);
        fprintf('    pixel_size_y = %.3f µm/pixel\n', pixel_size_um_y);
        fprintf('    pixel_size_avg = %.3f µm/pixel\n', pixel_size_um);
        fprintf('    pixel_area = %.6e mm^2/pixel\n\n', pixel_area_mm2);
        % Save both per-axis and averaged values
        save(out_mat, 'pixel_size_um', 'pixel_size_um_x', 'pixel_size_um_y', 'pixel_area_mm2');
        fprintf('Saved auto-filled calibration to %s\n', out_mat);
        auto_filled = true;
    end
end

if auto_filled
    return;
end

%% 4) If not auto-filled, present interactive/manual options
fprintf('\nNo metadata or matching ROI found. Choose calibration method:\n');
fprintf('  1) Enter pixel size manually (µm/pixel)\n');
fprintf('  2) Draw a line of known length on the image and enter its real length\n');
fprintf('  3) Draw a polygon around an object of known physical area\n');
fprintf('  4) Load existing calibration .mat file\n');
fprintf('  0) Abort\n');

choice = input('Enter choice number: ');

switch choice
    case 0
        fprintf('Aborted by user.\n');
        return;
    case 1
        answ = inputdlg({'Pixel size (µm/pixel):'}, 'Manual pixel size', 1, {'10.7'});
        if isempty(answ)
            fprintf('No value entered. Aborting.\n'); return;
        end
        pixel_size_um = str2double(answ{1});
        if isnan(pixel_size_um) || pixel_size_um <= 0
            error('Invalid pixel size entered.');
        end
        pixel_area_mm2 = (pixel_size_um * 1e-3)^2;
        fprintf('\nManual entry:\n  pixel_size = %.4f µm/pixel\n  pixel_area = %.6e mm^2/pixel\n\n', pixel_size_um, pixel_area_mm2);
        save(out_mat, 'pixel_size_um', 'pixel_area_mm2');
        fprintf('Saved calibration to %s\n', out_mat);
        return;
        
    case 2
        if isempty(img)
            error('No preview image available to draw on. Provide a preview dataset in the HDF5 (e.g., /structural).');
        end
        hFig = figure('Name','Draw a line of known length and press Enter','NumberTitle','off');
        imagesc(img); axis image; colormap gray; title('Draw line of known length (double-click/return to finish)');
        try
            hLine = drawline();
            pos = wait(hLine); % returns [x1 y1; x2 y2]
            delete(hLine);
        catch
            h = imdistline;
            pos = wait(h);
            try pos = getPosition(h); delete(h); catch; end
        end
        close(hFig);
        if isempty(pos) || size(pos,1) < 2
            error('Line drawing failed or aborted.');
        end
        dx = pos(2,1) - pos(1,1);
        dy = pos(2,2) - pos(1,2);
        length_pixels = sqrt(dx^2 + dy^2);
        fprintf('Line length in pixels: %.3f px\n', length_pixels);
        dlg = inputdlg({'Enter real-world length (numeric):','Units (um / mm):'}, 'Physical length', 1, {'100','um'});
        if isempty(dlg), error('No physical length entered.'); end
        phys_val = str2double(dlg{1});
        phys_unit = lower(strtrim(dlg{2}));
        if isnan(phys_val) || phys_val <= 0, error('Invalid physical length.'); end
        if strcmp(phys_unit, 'mm')
            phys_um = phys_val * 1000;
        elseif strcmp(phys_unit, 'um') || strcmp(phys_unit,'µm')
            phys_um = phys_val;
        else
            error('Unknown unit. Use "um" or "mm".');
        end
        pixel_size_um = phys_um / length_pixels;
        pixel_area_mm2 = (pixel_size_um * 1e-3)^2;
        fprintf('\nCalibration from line:\n  pixel_size = %.4f µm/pixel\n  pixel_area = %.6e mm^2/pixel\n\n', pixel_size_um, pixel_area_mm2);
        save(out_mat, 'pixel_size_um', 'pixel_area_mm2');
        fprintf('Saved calibration to %s\n', out_mat);
        return;
        
    case 3
        if isempty(img)
            error('No preview image available to draw on. Provide a preview dataset in the HDF5 (e.g., /structural).');
        end
        hFig = figure('Name','Draw polygon around object of known area and double-click to finish','NumberTitle','off');
        imagesc(img); axis image; colormap gray; title('Draw polygon of known physical area');
        try
            hPoly = drawpolygon();
            mask = createMask(hPoly);
            polypos = hPoly.Position;
            delete(hPoly);
        catch
            mask = roipoly;
            polypos = [];
        end
        close(hFig);
        if ~isempty(polypos)
            area_pixels = polyarea(polypos(:,1), polypos(:,2));
        else
            area_pixels = sum(mask(:));
        end
        fprintf('Polygon area estimate: %.2f pixel^2\n', area_pixels);
        dlg = inputdlg({'Enter real-world area (numeric):','Units (um^2 / mm^2):'}, 'Physical area', 1, {'10000','um^2'});
        if isempty(dlg), error('No physical area entered.'); end
        phys_area_val = str2double(dlg{1});
        phys_area_unit = lower(strtrim(dlg{2}));
        if isnan(phys_area_val) || phys_area_val <= 0, error('Invalid physical area.'); end
        if strcmp(phys_area_unit, 'um^2') || strcmp(phys_area_unit,'µm^2')
            phys_area_mm2 = phys_area_val * 1e-6;
        elseif strcmp(phys_area_unit, 'mm^2')
            phys_area_mm2 = phys_area_val;
        else
            error('Unknown unit. Use "um^2" or "mm^2".');
        end
        pixel_area_mm2 = phys_area_mm2 / area_pixels;
        pixel_size_um = sqrt(pixel_area_mm2) * 1e3;
        fprintf('\nCalibration from polygon:\n  pixel_area = %.6e mm^2/pixel\n  pixel_size = %.4f µm/pixel\n\n', pixel_area_mm2, pixel_size_um);
        save(out_mat, 'pixel_size_um', 'pixel_area_mm2');
        fprintf('Saved calibration to %s\n', out_mat);
        return;
        
    case 4
        [f,p] = uigetfile('*.mat','Select calibration .mat file');
        if isequal(f,0)
            fprintf('No file selected. Aborting.\n'); return;
        end
        load(fullfile(p,f),'pixel_size_um','pixel_area_mm2','pixel_size_um_x','pixel_size_um_y');
        if exist('pixel_size_um','var') && exist('pixel_area_mm2','var')
            fprintf('Loaded calibration from %s\n', fullfile(p,f));
            fprintf('  pixel_size = %.4f µm/pixel\n  pixel_area = %.6e mm^2/pixel\n', pixel_size_um, pixel_area_mm2);
            if exist('pixel_size_um_x','var') && exist('pixel_size_um_y','var')
                fprintf('  pixel_size_x = %.4f µm/pixel, pixel_size_y = %.4f µm/pixel\n', pixel_size_um_x, pixel_size_um_y);
            end
            save(out_mat, 'pixel_size_um', 'pixel_area_mm2', 'pixel_size_um_x', 'pixel_size_um_y');
            fprintf('Saved calibration to %s\n', out_mat);
            return;
        else
            error('Selected MAT file does not contain pixel_size_um and pixel_area_mm2 variables.');
        end
    otherwise
        error('Unknown choice.');
end

end