# ext_visualization_enhanced.py
import h5py 
import numpy as np 
import matplotlib.pyplot as plt 
import cv2
from pathlib import Path
import warnings

class EfficientVideoExporter:
    def __init__(self, data, original_fps=500.67):
        self.data = data
        self.original_fps = original_fps
        
    def separate_interleaved_frames(self, frame_indices):
        """
        Separate interleaved low/high contrast frames
        
        Parameters:
        - frame_indices: List of frame indices to separate
        
        Returns:
        - low_contrast_frames: Even indices (0, 2, 4, ...)
        - high_contrast_frames: Odd indices (1, 3, 5, ...)
        """
        low_contrast_frames = []
        high_contrast_frames = []
        
        for idx in frame_indices:
            if idx % 2 == 0:  # Even frames - low contrast
                low_contrast_frames.append(idx)
            else:  # Odd frames - high contrast
                high_contrast_frames.append(idx)
                
        return low_contrast_frames, high_contrast_frames
    
    def export_separated_frames(self, frame_indices, output_base_path, target_fps=500.67, 
                               normalize=True, add_frame_info=True, export_both=True):
        """
        Export separated low/high contrast frames
        
        Parameters:
        - frame_indices: List of frame indices to process
        - output_base_path: Base path for output files (will add _low and _high suffixes)
        - target_fps: Target FPS for output video
        - normalize: Whether to normalize intensity for better contrast
        - add_frame_info: Whether to overlay frame number and timestamp
        - export_both: If True, exports both separated and combined videos
        """
        
        # Separate frames
        low_frames, high_frames = self.separate_interleaved_frames(frame_indices)
        
        print(f"Separated {len(frame_indices)} frames:")
        print(f"  Low contrast frames: {len(low_frames)}")
        print(f"  High contrast frames: {len(high_frames)}")
        
        # Export low contrast frames
        if low_frames:
            low_output = output_base_path.replace('.mp4', '_low_contrast.mp4')
            self.export_frames_to_video(low_frames, low_output, target_fps, 
                                      normalize, add_frame_info)
        
        # Export high contrast frames  
        if high_frames:
            high_output = output_base_path.replace('.mp4', '_high_contrast.mp4')
            self.export_frames_to_video(high_frames, high_output, target_fps, 
                                       normalize, add_frame_info)
        
        # Export combined comparison if requested
        if export_both and low_frames and high_frames:
            comparison_output = output_base_path.replace('.mp4', '_comparison.mp4')
            min_len = min(len(low_frames), len(high_frames))
            self.export_comparison_video(low_frames[:min_len], high_frames[:min_len], 
                                       comparison_output, target_fps, side_by_side=True)
    
    def export_frames_to_video(self, frame_indices, output_path, target_fps=500.67, 
                              normalize=True, add_frame_info=True):
        """
        Export frames to MP4 video using OpenCV
        
        Parameters:
        - frame_indices: List of frame indices to export
        - output_path: Output video file path
        - target_fps: Target FPS for output video (default 500.67)
        - normalize: Whether to normalize intensity for better contrast
        - add_frame_info: Whether to overlay frame number and timestamp
        """
        
        # Ensure output directory exists
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        
        # Get frame dimensions
        height, width = self.data[0].shape
        
        # Add padding for text if needed
        text_padding = 60 if add_frame_info else 0
        video_height = height + text_padding
        
        # Define codec and create VideoWriter
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(output_path, fourcc, target_fps, (width, video_height))
        
        if not out.isOpened():
            print(f"Error: Could not open video writer for {output_path}")
            return
        
        print(f"Exporting {len(frame_indices)} frames to {output_path}")
        print(f"Target FPS: {target_fps}, Original FPS: {self.original_fps}")
        
        for i, frame_idx in enumerate(frame_indices):
            if i % 100 == 0:
                print(f"Processing frame {i+1}/{len(frame_indices)}")
                
            # Get frame data
            frame_data = self.data[frame_idx].astype(np.float32)
            
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
                contrast_type = "Low" if frame_idx % 2 == 0 else "High"
                
                text1 = f"Frame: {frame_idx:4d} ({contrast_type})"
                text2 = f"Time: {timestamp_ms:6.2f}ms"
                text3 = f"Mean: {np.mean(self.data[frame_idx]):6.1f}"
                
                cv2.putText(frame_with_text, text1, (10, 20), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)
                cv2.putText(frame_with_text, text2, (10, 40), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)
                cv2.putText(frame_with_text, text3, (200, 20), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)
                
                frame_rgb = frame_with_text
            
            out.write(frame_rgb)
        
        out.release()
        print(f"Video saved: {output_path}")
        
    def export_comparison_video(self, early_frames, later_frames, output_path, 
                               target_fps=500.67, side_by_side=True):
        """
        Export side-by-side comparison video
        """
        if len(early_frames) != len(later_frames):
            min_len = min(len(early_frames), len(later_frames))
            early_frames = early_frames[:min_len]
            later_frames = later_frames[:min_len]
        
        # Ensure output directory exists
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        
        height, width = self.data[0].shape
        
        if side_by_side:
            video_width = width * 2 + 20  # 20px separator
            video_height = height + 80    # 80px for text
        else:
            video_width = width
            video_height = height * 2 + 100  # 100px for text
        
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(output_path, fourcc, target_fps, (video_width, video_height))
        
        print(f"Exporting comparison video: {output_path}")
        
        for i in range(len(early_frames)):
            if i % 50 == 0:
                print(f"Processing comparison frame {i+1}/{len(early_frames)}")
            
            # Get and normalize both frames
            early_data = self.data[early_frames[i]].astype(np.float32)
            later_data = self.data[later_frames[i]].astype(np.float32)
            
            # Normalize each frame independently
            early_min, early_max = early_data.min(), early_data.max()
            if early_max > early_min:
                early_norm = (early_data - early_min) / (early_max - early_min)
            else:
                early_norm = np.zeros_like(early_data)
                
            later_min, later_max = later_data.min(), later_data.max()
            if later_max > later_min:
                later_norm = (later_data - later_min) / (later_max - later_min)
            else:
                later_norm = np.zeros_like(later_data)
            
            early_frame = (early_norm * 255).astype(np.uint8)
            later_frame = (later_norm * 255).astype(np.uint8)
            
            # Convert to RGB
            early_rgb = cv2.cvtColor(early_frame, cv2.COLOR_GRAY2BGR)
            later_rgb = cv2.cvtColor(later_frame, cv2.COLOR_GRAY2BGR)
            
            # Create combined frame
            combined = np.zeros((video_height, video_width, 3), dtype=np.uint8)
            
            if side_by_side:
                # Side by side layout
                combined[80:80+height, :width] = early_rgb
                combined[80:80+height, width+20:] = later_rgb
                
                # Add separating line
                combined[:, width:width+20] = [100, 100, 100]
                
                # Determine contrast types
                early_type = "Low" if early_frames[i] % 2 == 0 else "High"
                later_type = "Low" if later_frames[i] % 2 == 0 else "High"
                
                # Add labels
                cv2.putText(combined, f"{early_type} Contrast Frame {early_frames[i]}", (10, 30), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
                cv2.putText(combined, f"{later_type} Contrast Frame {later_frames[i]}", (width+30, 30), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 100, 255), 2)
                
                # Add timing info
                early_time = early_frames[i] / self.original_fps * 1000
                later_time = later_frames[i] / self.original_fps * 1000
                cv2.putText(combined, f"t={early_time:.2f}ms", (10, 60), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
                cv2.putText(combined, f"t={later_time:.2f}ms", (width+30, 60), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
            
            out.write(combined)
        
        out.release()
        print(f"Comparison video saved: {output_path}")

    def export_all_1500_frames_at_500_67_fps(self, start_frame=0):
        """
        Export all 1500 frames at 500.67 fps with proper separation
        - Original 1500 frames at 500.67 fps
        - 750 low contrast frames (even indices) at 500.67 fps  
        - 750 high contrast frames (odd indices) at 500.67 fps
        """
        # Get all 1500 frames
        max_frames = min(1500, len(self.data) - start_frame)
        all_frame_indices = list(range(start_frame, start_frame + max_frames))
        
        print(f"Processing {len(all_frame_indices)} frames total")
        
        # 1. Export ALL 1500 frames at 500.67 fps
        all_output = "data/animations/E1B1_all_1500_frames_500_67fps.mp4"
        self.export_frames_to_video(all_frame_indices, all_output, target_fps=500.67)
        
        # 2. Separate into low/high contrast
        low_frames, high_frames = self.separate_interleaved_frames(all_frame_indices)
        
        print(f"Separated frames:")
        print(f"  Low contrast frames: {len(low_frames)} (should be 750)")
        print(f"  High contrast frames: {len(high_frames)} (should be 750)")
        
        # 3. Export 750 low contrast frames at 500.67 fps
        if low_frames:
            low_output = "data/animations/E1B1_low_contrast_750_frames_500_67fps.mp4"
            self.export_frames_to_video(low_frames, low_output, target_fps=500.67, add_frame_info=True)
        
        # 4. Export 750 high contrast frames at 500.67 fps
        if high_frames:
            high_output = "data/animations/E1B1_high_contrast_750_frames_500_67fps.mp4"
            self.export_frames_to_video(high_frames, high_output, target_fps=500.67, add_frame_info=True)
        
        # 5. Optional: Create side-by-side comparison of first 375 frames from each
        if low_frames and high_frames:
            comparison_output = "data/animations/E1B1_low_vs_high_contrast_comparison_500_67fps.mp4"
            min_len = min(375, len(low_frames), len(high_frames))  # Compare first 375 of each
            self.export_comparison_video(low_frames[:min_len], high_frames[:min_len],
                                       comparison_output, target_fps=500.67, side_by_side=True)

# Usage:
if __name__ == "__main__":
    # Load your data
    h5_path = "converted__500/led_E1B1.h5"
    #h5_path = "data/led_E1B13.h5"  
    with h5py.File(h5_path, 'r') as hf:
        data = hf['image_stack'][:]
    
    print(f"Loaded data shape: {data.shape}")
    
    # Create exporter with precise FPS
    exporter = EfficientVideoExporter(data, original_fps=500.67)
    
    # Export all 1500 frames at 500.67 fps (as requested)
    exporter.export_all_1500_frames_at_500_67_fps(start_frame=0)
    
    # Additional examples for different ranges:
    
    # # Example 1: Export first 750 frames with separation
    # frame_indices = list(range(750))
    # exporter.export_separated_frames(frame_indices, 
    #                                 "data/animations/early_750_separated.mp4", 
    #                                 target_fps=500.67)
    
    # # Example 2: Export frames 750-1499 with separation  
    # if len(data) > 1499:
    #     later_indices = list(range(750, 1500))
    #     exporter.export_separated_frames(later_indices, 
    #                                     "data/animations/later_750_separated.mp4", 
    #                                     target_fps=500.67)
        
    #     # Example 3: Compare low contrast frames from early vs later
    #     early_low, early_high = exporter.separate_interleaved_frames(range(750))
    #     later_low, later_high = exporter.separate_interleaved_frames(range(750, 1500))
        
    #     min_len = min(len(early_low), len(later_low))
    #     exporter.export_comparison_video(early_low[:min_len], later_low[:min_len],
    #                                    "data/animations/low_contrast_comparison.mp4",
    #                                    target_fps=500.67)