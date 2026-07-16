function result = vsd_sanity_check(h5file, varargin)
% VSD_SANITY_CHECK  Quick fluorescence sanity check on 750-frame recordings.
%
% Usage:
%   global_fluorescence_check = vsd_sanity_check('file_vsd_corrected.h5', 'Dataset','functional');
%
% Assumes:
%   - total frames = 750
%   - frames 1:375 = pre-stimulus
%   - frames 376:750 = stimulus
%
% Output:
%   result is a struct with fields:
%     .F_all, .F_pre, .F_stim, .dFF_pre, .dFF_stim

p = inputParser;
addRequired(p,'h5file',@(s)ischar(s)||isstring(s));
addParameter(p,'Dataset','functional',@(s)ischar(s)||isstring(s));
parse(p,h5file,varargin{:});
dataset = char(p.Results.Dataset);

% Load data
X = h5read(h5file, ['/' dataset]); % H x W x T
X = double(X);
[~,~,T] = size(X);

if T ~= 750
    warning('Expected 750 frames, got %d. Splitting in half.', T);
    half = floor(T/2);
    pre_idx = 1:half;
    stim_idx = half+1:T;
else
    pre_idx = 1:375;
    stim_idx = 376:750;
end

% Compute means
F_all  = mean(X(:));
F_pre  = mean(X(:,:,pre_idx), 'all');
F_stim = mean(X(:,:,stim_idx), 'all');

% Fractional changes relative to global mean
dFF_pre  = (F_pre  - F_all) / F_all;
dFF_stim = (F_stim - F_all) / F_all;

% Package results
result = struct('F_all',F_all, ...
                'F_pre',F_pre, ...
                'F_stim',F_stim, ...
                'dFF_pre',dFF_pre, ...
                'dFF_stim',dFF_stim);

% Print summary
fprintf('Global mean   = %.4f\n', F_all);
fprintf('Pre  mean     = %.4f | ΔF/F_pre  = %.4f\n', F_pre, dFF_pre);
fprintf('Stim mean     = %.4f | ΔF/F_stim = %.4f\n', F_stim, dFF_stim);

% Plot
figure('Color','w');
bar(1, dFF_pre, 'b'); hold on;
bar(2, dFF_stim, 'r');
yline(0,'k--');
set(gca,'XTick',[1 2],'XTickLabel',{'Pre','Stim'});
ylabel('ΔF/F relative to global mean');
title(sprintf('Sanity check: %s/%s', h5file, dataset), 'Interpreter','none');
end
