import h5py
import cv2
import numpy as np
from tqdm import tqdm
import os

# --- Main Configuration ---
# 1. Path to your input HDF5 file
input_h5_path = 'converted__500/led_E1B0.h5'

# 2. Name of the dataset inside the HDF5 file
dataset_name = 'image_stack' 

# --- Video Output Configuration ---
# 3. Path for the output video file
output_video_path = 'data/Histogram_Equilization/E1B0_comparison.mp4'

# 4. Desired frames per second for the output video
output_fps = 500.67 

# --- New Configuration for HDF5 Output ---
# 5. Set to True if you want to save the processed frames to a new HDF5 file
SAVE_TO_HDF5 = True

# 6. Path for the new HDF5 file
output_h5_path = 'data/Histogram_Equilization/E1B0_histo_equali.h5'

# 7. Name for the dataset in the new HDF5 file
output_dataset_name = 'equalized_data'
# --- End of Configuration ---


def create_comparison_video(h5_path, dset_name, video_path, fps):
    """
    Applies histogram equalization and creates a side-by-side comparison video.
    (This is the same function as before)
    """
    print("--- Creating Comparison Video ---")
    # ... (Code from the previous response is largely the same, condensed here for brevity)
    with h5py.File(h5_path, 'r') as f:
        if dset_name not in f:
            print(f"Error: Dataset '{dset_name}' not found.")
            return
        frames = f[dset_name][:]

    num_frames, height, width = frames.shape
    min_val, max_val = frames.min(), frames.max()
    if max_val == min_val: max_val += 1e-6
    frames_8bit = ((frames - min_val) / (max_val - min_val) * 255).astype(np.uint8)

    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(video_path, fourcc, fps, (width * 2, height), isColor=False)

    for i in tqdm(range(0, num_frames - 1, 2), desc="Creating Video"):
        odd_eq = cv2.equalizeHist(frames_8bit[i])
        even_eq = cv2.equalizeHist(frames_8bit[i+1])
        side_by_side_frame = np.hstack([odd_eq, even_eq])
        out.write(side_by_side_frame)
        
    out.release()
    print(f"✅ Video creation complete! Saved to '{video_path}'")


def save_equalized_to_hdf5(h5_path, dset_name, output_h5_path, output_dset_name):
    """
    Applies histogram equalization and saves the result to a new HDF5 file.
    """
    print("\n--- Saving Processed Data to HDF5 ---")
    print("Step 1: Loading HDF5 data...")
    with h5py.File(h5_path, 'r') as f:
        if dset_name not in f:
            print(f"Error: Dataset '{dset_name}' not found.")
            return
        frames = f[dset_name][:]
    
    print("Step 2: Normalizing and applying histogram equalization...")
    min_val, max_val = frames.min(), frames.max()
    if max_val == min_val: max_val += 1e-6
    frames_8bit = ((frames - min_val) / (max_val - min_val) * 255).astype(np.uint8)

    # Prepare an empty array to store the equalized frames
    equalized_frames = np.zeros_like(frames_8bit)

    # Apply equalization to every single frame
    for i in tqdm(range(frames_8bit.shape[0]), desc="Applying Equalization"):
        equalized_frames[i] = cv2.equalizeHist(frames_8bit[i])

    print(f"Step 3: Writing processed data to '{output_h5_path}'...")
    with h5py.File(output_h5_path, 'w') as f:
        f.create_dataset(
            output_dset_name, 
            data=equalized_frames,
            compression='gzip' # Use compression to save space
        )
    
    print(f"✅ HDF5 saving complete! Processed data saved in '{output_h5_path}'")


if __name__ == '__main__':
    if not os.path.exists(input_h5_path):
        print(f"Error: Input file not found at '{input_h5_path}'")
    else:
        # 1. Always create the visualization video
        create_comparison_video(input_h5_path, dataset_name, output_video_path, output_fps)

        # 2. Optionally save the processed data to a new HDF5 file
        if SAVE_TO_HDF5:
            save_equalized_to_hdf5(input_h5_path, dataset_name, output_h5_path, output_dataset_name)