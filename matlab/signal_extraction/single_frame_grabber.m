function single_frame_grabber(h5file, start_frame)
    % Frame viewer for HDF5 3D image data.
    % Inputs:-
    %   h5file: path to the .h5 file (string)
    %   start_frame: frame number to start viewing (integer)
    % Usage example:- single_frame_grabber('data/preprocessing/averaged_movie_E0B0-B3.h5', 7);

    img = h5read(h5file, '/structural');
    num_frames = size(img, 3);
    frame_number = start_frame;
    while true
        frame = img(:, :, frame_number);
        frame_norm = mat2gray(frame);
        imshow(frame_norm);
        title(sprintf('Frame %d of %d', frame_number, num_frames));
        fprintf(['Choose an action:\n' ...
            '1: Save this frame\n' ...
            '2: Next frame\n' ...
            '3: Previous frame\n' ...
            '4: Exit\n' ...
            '5: Jump to specific frame\n']);
        choice = input('Enter your choice (1-5): ');
        
        switch choice
            case 1  % Save frame
                imwrite(frame_norm, sprintf('frame_%d.png', frame_number));
                fprintf('Frame %d saved as frame_%d.png\n', frame_number, frame_number);
                
            case 2  % Next frame
                if frame_number < num_frames
                    frame_number = frame_number + 1;
                else
                    fprintf('Already at the last frame.\n');
                end
                
            case 3  % Previous frame
                if frame_number > 1
                    frame_number = frame_number - 1;
                else
                    fprintf('Already at the first frame.\n');
                end
                
            case 4  % Exit
                fprintf('Exiting frame viewer.\n');
                close;
                break;
                
            case 5  % Jump to specific frame
                jump_frame = input(sprintf('Enter frame number (1 to %d): ', num_frames));
                if isnumeric(jump_frame) && jump_frame >= 1 && jump_frame <= num_frames && mod(jump_frame,1)==0
                    frame_number = jump_frame;
                else
                    fprintf('Invalid frame number.\n');
                end
                
            otherwise
                fprintf('Invalid choice, please enter a number between 1 and 5.\n');
        end
    end
end
