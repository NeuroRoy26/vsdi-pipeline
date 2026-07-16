% MEA_coordinate.m
% This script asks user to selects a picture, pick out 4 points corresponding
% to the MEA array and then it strecthes the plane atlas as per the MEA
% This was made before me, originally part of the SEP_Project

file = uigetfile({'*.*'});

disp(file)

try
    img = imread(file);
catch
    error('Could not read selected file');
end

imshow(img);
roi = drawpolygon();
while size(roi.Position, 1) ~= 4
    warning('size polygon must contain 4 corners!')
    roi.delete;
    roi = drawpolygon();
end
points = roi.Position;

[n, m] = size(img, 1:2);
coordinates = [0, 0; m, 0; m, n; 0, n];

tform = fitgeotrans(points, coordinates, 'projective');

img_out = imwarp(img, tform, 'OutputView', imref2d(size(img, 1:2)));

img_out = mat2gray(mat2gray(img_out(:, :, 1)) + mat2gray(img_out(:, :, 2)));


% Hier die Werte aus dem Atlas eintragen:
x = [0, 1];
y = [0, 1.25];
figure;
imagesc(x, y, img_out(end:-1:1, :));
ylabel('\mum')
xlabel('\mum')
set(gca,'YDir','normal')
colormap gray
axis image