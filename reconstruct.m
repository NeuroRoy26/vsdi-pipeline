% ICA_reconstruct.m

fprintf('=== ICA RECONSTRUCTION SCRIPT ===\n\n');
sign_ass = +1; % chagne to -1 for sign inversion
%% ------------------------------------------------------------
% Check required variables
% FIX: Added check for 'Fs' to prevent crashes during plotting
if ~exist('ica_maps', 'var') || ~exist('ica_timecourses', 'var') || ~exist('Fs', 'var')
    error(['Required variables not found!\n' ...
           'Run PCA_ICA_decomp.m first or load variables:\n' ...
           'ica_maps, ica_timecourses, H, W, T, Fs']);
end

[H, W, num_ICs] = size(ica_maps);
T = size(ica_timecourses, 1);

fprintf('Found %d ICA components\n', num_ICs);
fprintf('Dimensions: %d x %d pixels, %d frames\n\n', H, W, T);

%% ------------------------------------------------------------
% 2. Component selection
fprintf('--- COMPONENT SELECTION ---\n');
fprintf('  1. Reconstruct ALL components\n');
fprintf('  2. Reconstruct SELECTED components\n');
fprintf('  3. EXCLUDE specific components\n');
fprintf('  4. Single component only\n\n');

choice = input('Enter your choice (1-4): ');

switch choice
    case 1
        selected_ICs = 1:num_ICs;

    case 2
        selected_ICs = input('Enter component numbers (e.g. [1 3 5]): ');

    case 3
        excluded = input('Enter components to EXCLUDE: ');
        selected_ICs = setdiff(1:num_ICs, excluded);

    case 4
        selected_ICs = input('Component number: ');

    otherwise
        error('Invalid choice.');
end

% Validate selection
selected_ICs = unique(selected_ICs(:))';
selected_ICs(selected_ICs < 1 | selected_ICs > num_ICs) = [];

if isempty(selected_ICs)
    error('Selection invalid or empty.');
end

fprintf('Using components: %s\n', mat2str(selected_ICs));

%% ------------------------------------------------------------
% 3. Vectorized reconstruction
fprintf('\n--- RECONSTRUCTION ---\n');
fprintf('Vectorized reconstruction from %d component(s)...\n', length(selected_ICs));

% Flatten maps for faster computation
maps_flat = reshape(ica_maps, H*W, num_ICs);   % [P x K]
maps_sel = maps_flat(:, selected_ICs);         % [P x S]
tc_sel   = ica_timecourses(:, selected_ICs);   % [T x S]
% Reconstruct movie: X = spatial * time'
% change sign_ass to fix sign assignment
Xrec = sign_ass * (maps_sel * tc_sel.');             % [P x T]
reconstructed_movie = reshape(Xrec, H, W, T);  % [H x W x T]

fprintf('Reconstruction complete (Check Sign assignment).\n');

%% ------------------------------------------------------------
% 4. Compute "variance explained"
fprintf('\n--- STATISTICS ---\n');

% Full reconstruction using all ICs (vectorized)
% Also applying sign inversion to full reconstruction for consistency
Xfull = sign_ass * (maps_flat * ica_timecourses.');   % [P x T]
full_reconstruction = reshape(Xfull, H, W, T);

var_full = var(Xfull(:));
var_sel  = var(Xrec(:));
variance_explained = (var_sel / var_full) * 100;

fprintf('Variance explained by selected components: %.2f%%\n', variance_explained);

%% ------------------------------------------------------------
% 5. Visualization
fprintf('\n--- GENERATING VISUALIZATIONS ---\n');

display_frames = round(linspace(1, T, 6));

figure('Name','Reconstructed Movie - Frames','Color','w',...
       'Position',[50 50 1200 400]);

for i = 1:length(display_frames)
    t = display_frames(i);
    frame = reconstructed_movie(:,:,t);

    subplot(2,3,i);
    clim = [prctile(frame(:),1) prctile(frame(:),99)];
    imagesc(frame,clim);
    axis image off;
    colormap jet;
    title(sprintf('Frame %d (%.2fs)', t, t/Fs));
    colorbar;
end

sgtitle(sprintf('Reconstructed from ICs: %s', mat2str(selected_ICs)));

%% ------------------------------------------------------------
% 6. Mean projections
figure('Name','Mean Projection','Color','w','Position',[100 100 1000 400]);

subplot(1,3,1);
mfull = mean(full_reconstruction,3);
imagesc(mfull,[prctile(mfull(:),1) prctile(mfull(:),99)]);
axis image off; colormap jet; colorbar;
title('Full Reconstruction');

subplot(1,3,2);
msel = mean(reconstructed_movie,3);
imagesc(msel,[prctile(msel(:),1) prctile(msel(:),99)]);
axis image off; colormap jet; colorbar;
title('Selected Components');

subplot(1,3,3);
diffimg = mfull - msel;
imagesc(diffimg, max(abs(diffimg(:))) * [-1 1]);
axis image off; colormap jet; colorbar;
title('Difference (Removed Signal)');

%% ------------------------------------------------------------
% 7. ROI temporal traces
roi_h = round(H/2-10):round(H/2+10);
roi_w = round(W/2-10):round(W/2+10);

time_vec = (1:T)/Fs;
trace_full = squeeze(mean(mean(full_reconstruction(roi_h,roi_w,:),1),2));
trace_sel  = squeeze(mean(mean(reconstructed_movie(roi_h,roi_w,:),1),2));

figure('Name','Temporal Dynamics','Color','w','Position',[150 150 800 400]);

subplot(2,1,1);
h1 = plot(time_vec, trace_full, 'k', 'LineWidth', 1.5); hold on;
% FIX: Corrected typo 'trace_selected' -> 'trace_sel'
h2 = plot(time_vec, trace_sel, 'r', 'LineWidth', 1.5);

legend([h1 h2], {'Full','Selected'});
grid on; axis tight;
xlabel('Time (s)'); ylabel('Mean Intensity');
title('ROI Time Course');

subplot(2,1,2);
plot(time_vec, trace_full-trace_sel,'b','LineWidth',1.4);
grid on; axis tight;
title('Removed Signal');

%% ------------------------------------------------------------
% 8. Save movie
fprintf('\n--- SAVE OPTIONS ---\n');
save_choice = input('Save reconstructed movie? (y/n): ','s');

if strcmpi(save_choice,'y')
    ic_string = sprintf('%d_', selected_ICs);
    ic_string = ic_string(1:end-1);
    
    % FIX: Create data directory if it doesn't exist
    if ~exist('data', 'dir')
        mkdir('data');
    end
    
    outfile = sprintf('data/reconstructed_ICs_%s.mat', ic_string);

    save(outfile,'reconstructed_movie','selected_ICs',...
        'H','W','T','Fs','variance_explained');

    fprintf('Saved to: %s\n', outfile);
end

%% ------------------------------------------------------------
% 9. Component contribution analysis (vectorized)
fprintf('\n--- COMPONENT CONTRIBUTIONS ---\n');

% Each IC's standalone reconstruction:
% single = map(:,k) * tc(:,k)'  → magnitude measure = var(vec)
mag = zeros(num_ICs,1);
for k = 1:num_ICs
    % Note: Sign doesn't affect variance, so no need to invert here for calculation
    comp = maps_flat(:,k) * ica_timecourses(:,k).';
    mag(k) = var(comp(:));
end

pct = 100 * mag / sum(mag);

figure('Name','Component Contributions','Color','w');
bar(1:num_ICs, pct); hold on;
bar(selected_ICs, pct(selected_ICs),'r');
xlabel('Component #'); ylabel('Percent contribution');
title('Component Contribution (Relative Variance)'); 
grid on;

for k = 1:num_ICs
    tag = '';
    if ismember(k,selected_ICs), tag='[SELECTED]'; end
    fprintf('IC %d: %.2f%% %s\n', k, pct(k), tag);
end

fprintf('\n=== RECONSTRUCTION COMPLETE ===\n');
fprintf('Used %d / %d components\n', length(selected_ICs), num_ICs);
fprintf('Variance explained: %.2f%%\n', variance_explained);