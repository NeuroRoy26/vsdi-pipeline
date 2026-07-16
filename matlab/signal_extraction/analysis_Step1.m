% analysis_Step1.m
% BATCH PROCESSOR: Step 1 - Signal Extraction & Polarity Correction
% 
% DESCRIPTION:
%   Processes optical mapping reconstruction files to extract temporal traces,
%   apply filtering, and correct signal polarity based on 2nd half analysis.
%
% LOGIC:
%   - Polarity check focuses on the 2nd half of the recording (T/2 -> End)
%   - Assumes physiological activity is concentrated in the 2nd half
%   - Uses skewness to determine spike orientation (upward vs downward)
%
% OUTPUT:
%   All_Experiments_Summary.mat containing processed data structure

clear; clc; close all;

%% ======================== CONFIGURATION ========================
CONFIG.bandpass_freq = [0.1, 75];    % Hz - Bandpass filter range
CONFIG.filter_order = 4;              % Butterworth filter order
CONFIG.default_fs = 500;              % Hz - Default sampling frequency
CONFIG.output_file = 'All_Experiments_Summary.mat';

%% ======================== FILE SELECTION ========================
fprintf('========================================\n');
fprintf(' BATCH PROCESSOR - Signal Extraction\n');
fprintf('========================================\n\n');

fprintf('Please select your reconstruction files...\n');
[files, path_name] = uigetfile('*.mat', ...
    'Select One or More Reconstruction Files', ...
    'MultiSelect', 'on');

if isequal(files, 0)
    fprintf('Selection canceled by user.\n'); 
    return; 
end

% Ensure files is a cell array
if ischar(files)
    files = {files}; 
end

num_files = length(files);
fprintf('Selected %d file(s). Starting extraction...\n\n', num_files);

%% ======================== PROCESSING LOOP ========================
All_Experiments = struct();

for k = 1:num_files
    fname = files{k};
    full_path = fullfile(path_name, fname);
    
    fprintf('[%d/%d] Processing: %s\n', k, num_files, fname);
    
    try
        %% --- LOAD DATA ---
        D = load(full_path, 'reconstructed_movie', 'Fs');
        
        if ~isfield(D, 'reconstructed_movie')
            warning('  ⚠ No reconstructed_movie field found. Skipping...');
            All_Experiments(k).filename = fname;
            All_Experiments(k).error = 'Missing reconstructed_movie field';
            continue;
        end
        
        mov = D.reconstructed_movie;
        [height, width, num_frames] = size(mov);
        
        %% --- DETERMINE SAMPLING FREQUENCY ---
        if isfield(D, 'Fs')
            Fs = D.Fs;
        else
            % Try to extract from filename pattern '_XXX_'
            tok = regexp(fname, '_(\d+)_', 'tokens', 'once');
            if ~isempty(tok)
                Fs = str2double(tok{1});
                fprintf('  ℹ Fs extracted from filename: %d Hz\n', Fs);
            else
                Fs = CONFIG.default_fs;
                fprintf('  ℹ Using default Fs: %d Hz\n', Fs);
            end
        end
        
        %% --- EXTRACT SPATIAL AVERAGE TRACE ---
        raw_trace = squeeze(mean(mean(mov, 1), 2));
        
        %% --- BANDPASS FILTERING ---
        nyq = Fs / 2;
        [b, a] = butter(CONFIG.filter_order, CONFIG.bandpass_freq / nyq, 'bandpass');
        clean_trace = filtfilt(b, a, raw_trace);
        
        %% --- POLARITY CORRECTION (2ND HALF ANALYSIS) ---
        % Rationale: Physiological activity is concentrated in 2nd half
        % We determine spike orientation from this region
        
        half_idx = floor(num_frames / 2);
        second_half_trace = clean_trace(half_idx:end);
        
        % Calculate skewness of 2nd half
        % Positive skew → spikes point upward (correct orientation)
        % Negative skew → spikes point downward (needs flip)
        sk_2nd_half = skewness(second_half_trace);
        
        if sk_2nd_half < 0
            final_trace = -clean_trace;
            polarity_action = 'FLIPPED';
        else
            final_trace = clean_trace;
            polarity_action = 'KEPT';
        end
        
        fprintf('  ✓ Polarity: %s (2nd half skewness = %.3f)\n', ...
                polarity_action, sk_2nd_half);
        
        %% --- GENERATE PREVIEW IMAGE ---
        preview_img = max(mov, [], 3);  % Maximum intensity projection
        
        %% --- STORE RESULTS ---
        All_Experiments(k).filename       = fname;
        All_Experiments(k).folder         = path_name;
        All_Experiments(k).fs             = Fs;
        All_Experiments(k).dimensions     = [height, width, num_frames];
        All_Experiments(k).trace          = final_trace;
        All_Experiments(k).raw_trace      = raw_trace;  % Keep original for reference
        All_Experiments(k).skewness_2nd   = sk_2nd_half;
        All_Experiments(k).polarity       = polarity_action;
        All_Experiments(k).preview_img    = preview_img;
        All_Experiments(k).time_axis      = (0:length(final_trace)-1) / Fs;
        All_Experiments(k).processing_date = datestr(now);
        
        fprintf('  ✓ Successfully processed (%d frames, %.2f sec)\n', ...
                num_frames, num_frames/Fs);
        
    catch ME
        fprintf('  ✗ ERROR: %s\n', ME.message);
        fprintf('    Stack: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
        
        All_Experiments(k).filename = fname;
        All_Experiments(k).error = ME.message;
        All_Experiments(k).error_stack = ME.stack;
    end
    
    % Memory cleanup
    clear D mov raw_trace clean_trace final_trace preview_img second_half_trace;
    fprintf('\n');
end

%% ======================== SAVE RESULTS ========================
fprintf('========================================\n');
fprintf('Saving results to: %s\n', CONFIG.output_file);

save(CONFIG.output_file, 'All_Experiments', 'CONFIG');

% Summary statistics
num_success = sum(~arrayfun(@(x) isfield(x, 'error'), All_Experiments));
num_failed = num_files - num_success;

fprintf('========================================\n');
fprintf('PROCESSING COMPLETE\n');
fprintf('  ✓ Successful: %d/%d\n', num_success, num_files);
if num_failed > 0
    fprintf('  ✗ Failed: %d/%d\n', num_failed, num_files);
end
fprintf('========================================\n');