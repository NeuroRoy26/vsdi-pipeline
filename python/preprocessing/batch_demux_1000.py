import h5py 
import numpy as np 
import matplotlib.pyplot as plt 
import cv2
from pathlib import Path
import glob
import os

class InterleavedFrameSeparator:
    def __init__(self, original_fps=1001.34):
        """
        Initialize the separator for interleaved frames
        
        Parameters:
        - original_fps: Original frame rate of the interleaved video (1001.34 Hz)
        """
        self.original_fps = original_fps
        self.separated_fps = original_fps / 2  # 500.67 fps for each set
        
    def detect_contrast_order(self, data, sample_size=20):
        """
        Automatically detect which frames are low/high contrast by analyzing variance
        
        Parameters:
        - data: The image stack data
        - sample_size: Number of frame pairs to sample for detection
        
        Returns:
        - (even_is_low, confidence): Tuple of boolean and confidence score
        """
        num_frames = min(len(data), sample_size * 2)
        
        even_variances = []
        odd_variances = []
        
        # Sample frames and calculate variance/std for each set
        for i in range(0, num_frames, 2):
            if i < len(data):
                # Calculate local contrast metric (std dev of pixel values)
                even_frame = data[i].astype(np.float32)
                even_std = np.std(even_frame)
                even_variances.append(even_std)
                
            if i + 1 < len(data):
                odd_frame = data[i + 1].astype(np.float32)
                odd_std = np.std(odd_frame)
                odd_variances.append(odd_std)
        
        # Calculate mean variance for each set
        mean_even_var = np.mean(even_variances)
        mean_odd_var = np.mean(odd_variances)
        
        # Determine which has lower contrast (lower variance)
        even_is_low = mean_even_var < mean_odd_var
        
        # Calculate confidence (ratio of variances)
        if mean_even_var > 0 and mean_odd_var > 0:
            ratio = max(mean_even_var, mean_odd_var) / min(mean_even_var, mean_odd_var)
            confidence = min((ratio - 1) * 100, 100)  # Convert to percentage
        else:
            confidence = 0
        
        print(f"\nContrast Detection Results:")
        print(f"  Even frames avg std dev: {mean_even_var:.2f}")
        print(f"  Odd frames avg std dev: {mean_odd_var:.2f}")
        print(f"  Even frames are: {'LOW' if even_is_low else 'HIGH'} contrast")
        print(f"  Confidence: {confidence:.1f}%")
        
        return even_is_low, confidence
    
    def separate_interleaved_frames(self, frame_indices, even_is_low=True):
        """
        Separate interleaved frames into two sets based on parity
        
        Parameters:
        - frame_indices: List of frame indices to process
        - even_is_low: If True, even indices are low contrast, odd are high
        
        Returns:
        - (low_contrast_frames, high_contrast_frames): Tuple of frame lists
        """
        low_contrast_frames = []
        high_contrast_frames = []
        
        for idx in frame_indices:
            if idx % 2 == 0:  # Even frame
                if even_is_low:
                    low_contrast_frames.append(idx)
                else:
                    high_contrast_frames.append(idx)
            else:  # Odd frame
                if even_is_low:
                    high_contrast_frames.append(idx)
                else:
                    low_contrast_frames.append(idx)
                    
        return low_contrast_frames, high_contrast_frames
    
    def export_separated_video(self, data, frame_indices, output_path, 
                              contrast_type="low", normalize=True, add_frame_info=True):
        """
        Export separated frames to MP4 video at 250.335 fps
        
        Parameters:
        - data: The image stack data
        - frame_indices: List of frame indices to export
        - output_path: Output video file path
        - contrast_type: "low" or "high" for labeling
        - normalize: Whether to normalize intensity for better contrast
        - add_frame_info: Whether to overlay frame number and timestamp
        """
        
        if not frame_indices:
            print(f"No frames to export for {contrast_type} contrast")
            return
            
        print(f"Exporting {len(frame_indices)} {contrast_type} contrast frames to {output_path}")
        
        # Ensure output directory exists
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        
        # Get frame dimensions
        height, width = data[0].shape
        
        # Add padding for text if needed
        text_padding = 60 if add_frame_info else 0
        video_height = height + text_padding
        
        # Define codec and create VideoWriter for Motion JPEG AVI
        fourcc = cv2.VideoWriter_fourcc(*'MJPG')
        out = cv2.VideoWriter(output_path, fourcc, self.separated_fps, (width, video_height))
        
        if not out.isOpened():
            print(f"Error: Could not open video writer for {output_path}")
            return
        
        print(f"Output FPS: {self.separated_fps:.3f}")
        
        for i, frame_idx in enumerate(frame_indices):
            if i % 100 == 0:
                print(f"  Processing frame {i+1}/{len(frame_indices)}")
                
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
                # Scale to 8-bit if needed
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
                
                # Calculate timestamps
                original_time_ms = frame_idx / self.original_fps * 1000
                separated_time_ms = i / self.separated_fps * 1000
                
                # Choose color based on contrast type
                label_color = (255, 0, 0) if contrast_type.lower() == "low" else (0, 255, 0)
                
                text1 = f"Frame: {frame_idx:4d} ({contrast_type.upper()} Contrast)"
                text2 = f"Orig: {original_time_ms:6.2f}ms | Sep: {separated_time_ms:6.2f}ms"
                text3 = f"Mean: {np.mean(data[frame_idx]):6.1f} | Std: {np.std(data[frame_idx]):6.1f}"
                
                cv2.putText(frame_with_text, text1, (10, 20), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, label_color, 1)
                cv2.putText(frame_with_text, text2, (10, 40), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
                cv2.putText(frame_with_text, text3, (10, 55), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
                
                frame_rgb = frame_with_text
            
            out.write(frame_rgb)
        
        out.release()
        print(f"  Video saved: {output_path}")
        print(f"  Total frames: {len(frame_indices)}")
        print(f"  Duration: {len(frame_indices) / self.separated_fps:.2f} seconds")

    def process_single_file(self, input_path, output_dir="data/separated_frames", 
                           max_frames=1500, start_frame=0, auto_detect=True):
        """
        Process a single H5 file and separate interleaved frames
        
        Parameters:
        - input_path: Path to the H5 file
        - output_dir: Directory to save output videos
        - max_frames: Maximum number of frames to process
        - start_frame: Starting frame index
        - auto_detect: Whether to auto-detect contrast order
        """
        try:
            # Load data
            print(f"\n{'='*60}")
            print(f"Processing: {input_path}")
            print(f"{'='*60}")
            
            with h5py.File(input_path, 'r') as hf:
                data = hf['image_stack'][:]
            
            print(f"Loaded data shape: {data.shape}")
            
            # Auto-detect contrast order if requested
            if auto_detect:
                even_is_low, confidence = self.detect_contrast_order(data)
                if confidence < 20:
                    print(f"Warning: Low confidence in contrast detection ({confidence:.1f}%)")
                    print("Consider manual verification of results")
            else:
                even_is_low = True  # Default assumption
                print("Using default: even frames = low contrast")
            
            # Generate frame indices
            available_frames = len(data) - start_frame
            frames_to_process = min(max_frames, available_frames)
            frame_indices = list(range(start_frame, start_frame + frames_to_process))
            
            # Separate frames
            low_frames, high_frames = self.separate_interleaved_frames(frame_indices, even_is_low)
            
            print(f"\nFrame separation:")
            print(f"  Total frames to process: {len(frame_indices)}")
            print(f"  Low contrast frames: {len(low_frames)}")
            print(f"  High contrast frames: {len(high_frames)}")
            
            # Create output filenames
            input_filename = Path(input_path).stem
            low_output = Path(output_dir) / f"{input_filename}_LOW_CONTRAST_500fps.avi"
            high_output = Path(output_dir) / f"{input_filename}_HIGH_CONTRAST_500fps.avi"
            
            # Export both sets of frames
            print(f"\nExporting low contrast frames...")
            self.export_separated_video(data, low_frames, str(low_output), 
                                       contrast_type="low", add_frame_info=True)
            
            print(f"\nExporting high contrast frames...")
            self.export_separated_video(data, high_frames, str(high_output), 
                                       contrast_type="high", add_frame_info=True)
            
            return True
            
        except Exception as e:
            print(f"Error processing {input_path}: {str(e)}")
            import traceback
            traceback.print_exc()
            return False

    def batch_process(self, input_pattern, output_dir="data/separated_frames", 
                     max_frames=1500, start_frame=0, auto_detect=True):
        """
        Batch process multiple H5 files
        
        Parameters:
        - input_pattern: Glob pattern for input files
        - output_dir: Directory to save output videos
        - max_frames: Maximum number of frames to process per file
        - start_frame: Starting frame index
        - auto_detect: Whether to auto-detect contrast order for each file
        """
        # Find all matching files
        h5_files = sorted(glob.glob(input_pattern))
        
        if not h5_files:
            print(f"No files found matching pattern: {input_pattern}")
            return
        
        print(f"\n{'='*60}")
        print(f"BATCH PROCESSING: Found {len(h5_files)} H5 files")
        print(f"{'='*60}")
        for file in h5_files:
            print(f"  - {file}")
        
        # Create output directory
        Path(output_dir).mkdir(parents=True, exist_ok=True)
        
        # Process each file
        successful = 0
        failed = 0
        
        for i, h5_file in enumerate(h5_files, 1):
            print(f"\n[{i}/{len(h5_files)}] Processing file...")
            success = self.process_single_file(h5_file, output_dir, 
                                              max_frames, start_frame, auto_detect)
            if success:
                successful += 1
            else:
                failed += 1
        
        print(f"\n{'='*60}")
        print(f"BATCH PROCESSING COMPLETE")
        print(f"{'='*60}")
        print(f"Successfully processed: {successful} files")
        print(f"Failed: {failed} files")
        print(f"Output directory: {output_dir}")
        print(f"Output FPS: {self.separated_fps:.3f} fps for each contrast set")


# Usage examples:
if __name__ == "__main__":
    # Create separator with original interleaved fps
    separator = InterleavedFrameSeparator(original_fps=1001.34)
    
    # Process all H5 files in converted__500 directory with auto-detection
    print("Processing all files with automatic contrast detection...")
    separator.batch_process(
        input_pattern="converted__1000/*.h5",
        output_dir="data/all_files_1000hz_demultiplexed",
        max_frames=1500,
        start_frame=0,
        auto_detect=True  # Automatically detect which frames are low/high contrast
    )