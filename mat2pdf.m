%% MATLAB/Python Script to PDF Converter (Sanitized Version)
% This script converts .m, .mlx, and .py files to PDF.
% It includes a sanitization step to fix "invalid or illegal XML character" errors
% caused by non-ASCII symbols in comments or strings.

clear; clc;

% 1. Let the user pick the folder
targetDir = uigetdir(pwd, 'Select Folder containing scripts (.m, .mlx, .py)');

if isequal(targetDir, 0)
    fprintf('Operation cancelled by user.\n');
    return;
end

% 2. Setup output directory: data/pdf
outputPdfDir = fullfile(targetDir, 'data', 'pdf');
if ~exist(outputPdfDir, 'dir')
    mkdir(outputPdfDir);
end

% 3. Get file list
mFiles   = dir(fullfile(targetDir, '*.m'));
mlxFiles = dir(fullfile(targetDir, '*.mlx'));
pyFiles  = dir(fullfile(targetDir, '*.py'));

allFiles = [mFiles; mlxFiles; pyFiles];

if isempty(allFiles)
    fprintf('No supported files found in: %s\n', targetDir);
    return;
end

fprintf('Found %d files. Starting batch conversion with character sanitization...\n\n', numel(allFiles));

% 4. Loop through files
for i = 1:numel(allFiles)
    fileName = allFiles(i).name;
    if strcmp(fileName, 'convert_matlab_to_pdf.m'), continue; end
    
    fullPath = fullfile(targetDir, fileName);
    [~, nameOnly, ext] = fileparts(fileName);
    pdfName = fullfile(outputPdfDir, [nameOnly, '.pdf']);
    
    fprintf('Processing [%d/%d]: %s... ', i, numel(allFiles), fileName);
    
    try
        if strcmpi(ext, '.mlx')
            export(fullPath, pdfName);
        else
            % SANITIZATION STEP for .m and .py
            % Read as raw bytes to avoid encoding issues
            fid = fopen(fullPath, 'r', 'n', 'UTF-8');
            if fid == -1, fid = fopen(fullPath, 'r'); end % Fallback
            rawContent = fread(fid, '*char')';
            fclose(fid);
            
            % Filter: Keep only standard printable ASCII (32-126) + Newlines/Tabs
            % This removes "illegal XML characters" like nulls or high-bit symbols
            validChars = (rawContent >= 32 & rawContent <= 126) | ...
                         rawContent == 10 | rawContent == 13 | rawContent == 9;
            cleanContent = rawContent(validChars);
            
            % Create a temporary sanitized file
            tempFileName = fullfile(targetDir, ['temp_sanitize_', nameOnly, '.m']);
            fid = fopen(tempFileName, 'w', 'n', 'UTF-8');
            
            if strcmpi(ext, '.py')
                % Format Python as comments for MATLAB publisher
                fprintf(fid, '%%%% Python Script: %s\n%%\n', fileName);
                lines = splitlines(cleanContent);
                for l = 1:numel(lines)
                    fprintf(fid, '%% %s\n', lines{l});
                end
            else
                % Standard .m content
                fprintf(fid, '%s', cleanContent);
            end
            fclose(fid);
            
            % Publish the sanitized temp file
            opts.format = 'pdf';
            opts.outputDir = outputPdfDir;
            opts.showCode = true;
            opts.evalCode = false;
            
            publish(tempFileName, opts);
            
            % Cleanup and Rename
            delete(tempFileName);
            genPdfPath = fullfile(outputPdfDir, ['temp_sanitize_', nameOnly, '.pdf']);
            if exist(genPdfPath, 'file')
                movefile(genPdfPath, pdfName);
            end
        end
        fprintf('Done.\n');
    catch ME
        fprintf('FAILED.\n Error: %s\n', ME.message);
    end
end

fprintf('\nConversion complete. Files are in: %s\n', outputPdfDir);