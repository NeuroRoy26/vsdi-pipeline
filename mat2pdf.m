%% MATLAB Script/Live Script to PDF Converter
% This script allows you to select a directory and converts all .m and .mlx 
% files found directly in that folder into PDF format.
%
% The PDFs are saved in a subfolder: data/pdf/
%
% Note: This script ignores subfolders during the search.

clear; clc;

% 1. Let the user pick the folder
targetDir = uigetdir(pwd, 'Select Folder containing .m and .mlx files');

% Check if the user cancelled the dialog
if isequal(targetDir, 0)
    fprintf('Operation cancelled by user.\n');
    return;
end

% 2. Setup the output directory structure: data/pdf
outputPdfDir = fullfile(targetDir, 'data', 'pdf');
if ~exist(outputPdfDir, 'dir')
    mkdir(outputPdfDir);
    fprintf('Created output directory: %s\n', outputPdfDir);
end

% 3. Get list of all .m and .mlx files in that folder
mFiles = dir(fullfile(targetDir, '*.m'));
mlxFiles = dir(fullfile(targetDir, '*.mlx'));

allFiles = [mFiles; mlxFiles];

if isempty(allFiles)
    fprintf('No .m or .mlx files found in: %s\n', targetDir);
    return;
end

fprintf('Found %d files. Starting conversion...\n\n', numel(allFiles));

% 4. Loop through files and convert
for i = 1:numel(allFiles)
    fileName = allFiles(i).name;
    fullPath = fullfile(targetDir, fileName);
    [~, nameOnly, ext] = fileparts(fileName);
    
    % Define the specific output PDF path
    pdfName = fullfile(outputPdfDir, [nameOnly, '.pdf']);
    
    fprintf('Processing [%d/%d]: %s... ', i, numel(allFiles), fileName);
    
    try
        if strcmpi(ext, '.mlx')
            % For Live Scripts (.mlx), use export
            export(fullPath, pdfName);
        else
            % For standard scripts (.m), use publish
            options.format = 'pdf';
            options.outputDir = outputPdfDir; 
            options.showCode = true;
            
            % CRITICAL: Set evalCode to false to prevent the script from 
            % running and triggering interactive prompts (like uigetfile).
            options.evalCode = false; 
            
            publish(fullPath, options);
        end
        fprintf('Done.\n');
    catch ME
        fprintf('FAILED.\n Error: %s\n', ME.message);
    end
end

fprintf('\nConversion process complete. Files are in: %s\n', outputPdfDir);