# ext_visualization.py
import h5py 
import numpy as np 
import matplotlib.pyplot as plt 
import cv2
from pathlib import Path
import warnings

class EfficientVideoExporter:
    def __init__(self, data, original_fps=500):
        self.data = data
        self.original_fps = original_fps
        
    def export_frames_to_video(self, frame_indices, output_path, target_fps=60, 
                              normalize=True, add_frame_info=True):
        """
        Export frames to MP4 video using OpenCV
        
        Parameters:
        - frame_indices: List of frame indices to export
        - output_path: Output video file path
        - target_fps: Target FPS for output video
        - normalize: Whether to normalize intensity for better contrast
        - add_frame_info: Whether to overlay frame number and timestamp
        """
        
        # Get frame dimensions
        height, width = self.data[0].shape
        
        # Add padding for text if needed
        text_padding = 60 if add_frame_info else 0
        video_height = height + text_padding
        
        # Define codec and create VideoWriter
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(output_path, fourcc, target_fps, (width, video_height))
        
        print(f"Exporting {len(frame_indices)} frames to {output_path}")
        print(f"Target FPS: {target_fps}, Original FPS: {self.original_fps}")
        
        for i, frame_idx in enumerate(frame_indices):
            if i % 100 == 0:
                print(f"Processing frame {i+1}/{len(frame_indices)}")
                
            # Get frame data
            frame_data = self.data[frame_idx].astype(np.float32)
            
            # Normalize for better visualization
            if normalize:
                frame_data = (frame_data - frame_data.min()) / (frame_data.max() - frame_data.min())
                frame_data = (frame_data * 255).astype(np.uint8)
            else:
                # Scale 16-bit to 8-bit
                frame_data = (frame_data / 256).astype(np.uint8)
            
            # Convert to RGB (OpenCV uses BGR)
            frame_rgb = cv2.cvtColor(frame_data, cv2.COLOR_GRAY2BGR)
            
            # Add text overlay if requested
            if add_frame_info:
                # Create larger frame with text area
                frame_with_text = np.zeros((video_height, width, 3), dtype=np.uint8)
                frame_with_text[text_padding:, :] = frame_rgb
                
                # Add frame info
                timestamp_ms = frame_idx / self.original_fps * 1000
                text1 = f"Frame: {frame_idx:4d}"
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
                               target_fps=60, side_by_side=True):
        """
        Export side-by-side comparison video
        """
        if len(early_frames) != len(later_frames):
            min_len = min(len(early_frames), len(later_frames))
            early_frames = early_frames[:min_len]
            later_frames = later_frames[:min_len]
        
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
            
            early_norm = (early_data - early_data.min()) / (early_data.max() - early_data.min())
            later_norm = (later_data - later_data.min()) / (later_data.max() - later_data.min())
            
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
                
                # Add labels
                cv2.putText(combined, f"Early Frame {early_frames[i]}", (10, 30), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
                cv2.putText(combined, f"Later Frame {later_frames[i]}", (width+30, 30), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 100, 255), 2)
                
                # Add timing info
                early_time = early_frames[i] / self.original_fps * 1000
                later_time = later_frames[i] / self.original_fps * 1000
                cv2.putText(combined, f"t={early_time:.1f}ms", (10, 60), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
                cv2.putText(combined, f"t={later_time:.1f}ms", (width+30, 60), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
            else:
                # Top-bottom layout
                combined[50:50+height, :width] = early_rgb
                combined[height+100:, :width] = later_rgb
                
                # Add labels
                cv2.putText(combined, f"Early: Frame {early_frames[i]}", (10, 30), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
                cv2.putText(combined, f"Later: Frame {later_frames[i]}", (10, height+80), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 100, 255), 2)
            
            out.write(combined)
        
        out.release()
        print(f"Comparison video saved: {output_path}")

    def export_multiple_speeds(self, frame_indices, base_filename, speeds=[30, 60, 120, 240]):
        """Export the same frames at multiple speeds for comparison"""
        for speed in speeds:
            output_path = f"data/animations/{base_filename}_{speed}fps.mp4"
            self.export_frames_to_video(frame_indices, output_path, target_fps=speed)

# Usage:
if __name__ == "__main__":
    # Load your data
    h5_path = "data/led_E1B13.h5"  
    with h5py.File(h5_path, 'r') as hf:
        data = hf['image_stack'][:]
    
    # Create exporter
    exporter = EfficientVideoExporter(data, original_fps=500)
    
    # Define frame ranges
    early_frames = list(range(0, 750))  
    later_frames = list(range(750, 1500))
    
    # Export options:
    
    # 1. Export early frames at 60fps (smooth for VLC)
    exporter.export_frames_to_video(early_frames, "data/animations/early_frames_500fps.mp4", target_fps=500)
    
    # 2. Export later frames at 60fps  
    exporter.export_frames_to_video(later_frames, "data/animations/later_frames_500fps.mp4", target_fps=500)
    
    # 3. Export side-by-side comparison (first 10 from each)
    exporter.export_comparison_video(early_frames[:], later_frames[:], 
                                   "data/animations/frame_comparison_500fps.mp4", target_fps=500)
    
    # 4. Export at multiple speeds for analysis
    exporter.export_multiple_speeds(early_frames[:], "early_frames", [30, 60, 120])