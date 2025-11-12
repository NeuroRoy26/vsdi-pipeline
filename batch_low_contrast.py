# batch_low_contrast.py
import h5py 
import numpy as np 
import matplotlib.pyplot as plt 
import cv2
from pathlib import Path
import glob
import os

class LowContrastBatchExtractor:
    def __init__(self, original_fps=500.67):
        self.original_fps = original_fps
        
    def get_low_contrast_frames(self, frame_indices):
        """
        only low contrast frames (even indices: 0, 2, 4, ...)
        
        Parameters:
        - frame_indices: List of frame indices to filter
        
        Returns:
        - low_contrast_frames: Even indices only
        """
        low_contrast_frames = []
        
        for idx in frame_indices:
            if idx % 2 == 0:  # Even frames - low contrast
                low_contrast_frames.append(idx)
                
        return low_contrast_frames
    
    def export_low_contrast_video(self, data, frame_indices, output_path, target_fps=500.67, 
                                  normalize=True, add_frame_info=True):
        """
        Export ONLY low contrast frames to MP4 video
        
        Parameters:
        - data: The image stack data
        - frame_indices: List of frame indices to process
        - output_path: Output video file path
        - target_fps: Target FPS for output video (default 500.67)
        - normalize: Whether to normalize intensity for better contrast
        - add_frame_info: Whether to overlay frame number and timestamp
        """
        
        # Get only low contrast frames
        low_frames = self.get_low_contrast_frames(frame_indices)
        
        if not low_frames:
            print(f"No low contrast frames found in the given range")
            return
            
        print(f"Found {len(low_frames)} low contrast frames out of {len(frame_indices)} total frames")
        
        # Ensure output directory exists
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        
        # Get frame dimensions
        height, width = data[0].shape
        
        # Add padding for text if needed
        text_padding = 60 if add_frame_info else 0
        video_height = height + text_padding
        
        # Define codec and create VideoWriter
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(output_path, fourcc, target_fps, (width, video_height))
        
        if not out.isOpened():
            print(f"Error: Could not open video writer for {output_path}")
            return
        
        print(f"Exporting {len(low_frames)} low contrast frames to {output_path}")
        print(f"Target FPS: {target_fps}")
        
        for i, frame_idx in enumerate(low_frames):
            if i % 100 == 0:
                print(f"Processing frame {i+1}/{len(low_frames)}")
                
            # Get frame data
            frame_data = data[frame_idx].astype(np.float32)
            
            # Normalize for better visualization
            if normalize:
                frame_min, frame_max = frame_data.min(), frame_data.max()
                if frame_max > frame_min:
                    frame_data = (frame_data - frame_min) / (frame_max - frame_min)
                    frame_data = (frame_data * 255).astype(np.uint8)
                else:
                    frame_data = np.zeros_like(frame_data, dtype=np.uint8)
            else:
                # Scale 16-bit to 8-bit if needed
                if frame_data.max() > 255:
                    frame_data = (frame_data / (frame_data.max() / 255)).astype(np.uint8)
                else:
                    frame_data = frame_data.astype(np.uint8)
            
            # Convert to RGB (OpenCV uses BGR)
            frame_rgb = cv2.cvtColor(frame_data, cv2.COLOR_GRAY2BGR)
            
            # Add text overlay if requested
            if add_frame_info:
                # Create larger frame with text area
                frame_with_text = np.zeros((video_height, width, 3), dtype=np.uint8)
                frame_with_text[text_padding:, :] = frame_rgb
                
                # Add frame info
                timestamp_ms = frame_idx / self.original_fps * 1000
                
                text1 = f"Frame: {frame_idx:4d} (Low Contrast)"
                text2 = f"Time: {timestamp_ms:6.2f}ms"
                text3 = f"Mean: {np.mean(data[frame_idx]):6.1f}"
                
                cv2.putText(frame_with_text, text1, (10, 20), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 0, 0), 1)
                cv2.putText(frame_with_text, text2, (10, 40), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)
                cv2.putText(frame_with_text, text3, (200, 20), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)
                
                frame_rgb = frame_with_text
            
            out.write(frame_rgb)
        
        out.release()
        print(f"Low contrast video saved: {output_path}")
        print(f"Total frames exported: {len(low_frames)}")

    def process_single_file(self, input_path, output_dir="data/low_contrast_animations", 
                           max_frames=1500, start_frame=0):
        """
        Process a single H5 file and extract low contrast frames
        
        Parameters:
        - input_path: Path to the H5 file
        - output_dir: Directory to save output videos
        - max_frames: Maximum number of frames to process
        - start_frame: Starting frame index
        """
        try:
            # Load data
            print(f"\nProcessing: {input_path}")
            with h5py.File(input_path, 'r') as hf:
                data = hf['image_stack'][:]
            
            print(f"Loaded data shape: {data.shape}")
            
            # Generate frame indices
            available_frames = len(data) - start_frame
            frames_to_process = min(max_frames, available_frames)
            frame_indices = list(range(start_frame, start_frame + frames_to_process))
            
            # Create output filename
            input_filename = Path(input_path).stem
            output_path = Path(output_dir) / f"{input_filename}_LOW_CONTRAST_ONLY_500_67fps.mp4"
            
            # Export low contrast frames only
            self.export_low_contrast_video(data, frame_indices, str(output_path), 
                                           target_fps=500.67, add_frame_info=True)
            
            return True
            
        except Exception as e:
            print(f"Error processing {input_path}: {str(e)}")
            return False

    def batch_process(self, input_pattern, output_dir="data/low_contrast_animations", 
                     max_frames=1500, start_frame=0):
        """
        Batch process multiple H5 files
        
        Parameters:
        - input_pattern: Glob pattern for input files (e.g., "converted__500/*.h5" or "data/*.h5")
        - output_dir: Directory to save output videos
        - max_frames: Maximum number of frames to process per file
        - start_frame: Starting frame index
        """
        # Find all matching files
        h5_files = glob.glob(input_pattern)
        
        if not h5_files:
            print(f"No files found matching pattern: {input_pattern}")
            return
        
        print(f"Found {len(h5_files)} H5 files to process:")
        for file in h5_files:
            print(f"  - {file}")
        
        # Create output directory
        Path(output_dir).mkdir(parents=True, exist_ok=True)
        
        # Process each file
        successful = 0
        failed = 0
        
        for h5_file in h5_files:
            success = self.process_single_file(h5_file, output_dir, max_frames, start_frame)
            if success:
                successful += 1
            else:
                failed += 1
        
        print(f"\n=== BATCH PROCESSING COMPLETE ===")
        print(f"Successfully processed: {successful} files")
        print(f"Failed: {failed} files")
        print(f"Output directory: {output_dir}")


# Usage:
if __name__ == "__main__":
    # Create extractor
    extractor = LowContrastBatchExtractor(original_fps=500.67)
    
    ## Process all H5 files in converted__500 directory
    print("Processing all files in converted__500/...")
    extractor.batch_process(
        input_pattern="converted__500/*.h5",
        output_dir="data/all_files_low_contrast",
        max_frames=1500,
        start_frame=0
    )
    
    
    ## Process specific files
    # specific_files = [
    #     "converted__500/led_E1B1.h5",
    #     "converted__500/led_E1B2.h5",
    #     "converted__500/led_E1B3.h5"
    # ]
    # 
    # for file_path in specific_files:
    #     if os.path.exists(file_path):
    #         extractor.process_single_file(file_path, "data/low_contrast_animations")
    #     else:
    #         print(f"File not found: {file_path}")
    
    ## Process with custom settings
    # extractor.batch_process(
    #     input_pattern="your_directory/*.h5",
    #     output_dir="custom_output_dir",
    #     max_frames=1000,  # Process only first 1000 frames
    #     start_frame=100   # Start from frame 100
    # )