# video_stitcher.py
import cv2
import glob
import os
from pathlib import Path
import numpy as np
import re

class VideoStitcher:
    def __init__(self):
        self.supported_formats = ['.mp4', '.avi', '.mov', '.mkv']
    
    def natural_sort_key(self, filename):
        """
        Sort filenames naturally (handles numbers properly)
        E.g., file1.mp4, file2.mp4, file10.mp4 instead of file1.mp4, file10.mp4, file2.mp4
        """
        # Extract numbers from filename and convert to integers for proper sorting
        return [int(text) if text.isdigit() else text.lower() for text in re.split(r'(\d+)', filename)]
    
    def get_video_info(self, video_path):
        """
        Get basic information about a video file
        """
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            return None
        
        fps = cap.get(cv2.CAP_PROP_FPS)
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        duration = frame_count / fps if fps > 0 else 0
        
        cap.release()
        
        return {
            'fps': fps,
            'frame_count': frame_count,
            'width': width,
            'height': height,
            'duration': duration
        }
    
    def stitch_videos(self, input_pattern, output_path, target_fps=None, add_transition_info=True):
        """
        Stitch multiple videos into one continuous video
        
        Parameters:
        - input_pattern: Glob pattern for input videos (e.g., "data/high_contrast_animations/*.mp4")
        - output_path: Path for the output stitched video
        - target_fps: Target FPS (if None, uses FPS from first video)
        - add_transition_info: Whether to add text overlay showing which file is playing
        """
        
        # Find all video files
        video_files = glob.glob(input_pattern)
        
        if not video_files:
            print(f"No video files found matching pattern: {input_pattern}")
            return False
        
        # Sort files naturally
        video_files.sort(key=self.natural_sort_key)
        
        print(f"Found {len(video_files)} video files to stitch:")
        
        # Get info from all videos and validate
        video_infos = []
        total_duration = 0
        total_frames = 0
        
        for i, video_file in enumerate(video_files):
            info = self.get_video_info(video_file)
            if info is None:
                print(f"Error: Cannot read video file {video_file}")
                continue
                
            video_infos.append((video_file, info))
            total_duration += info['duration']
            total_frames += info['frame_count']
            
            print(f"  {i+1:2d}. {Path(video_file).name}")
            print(f"      {info['frame_count']:4d} frames, {info['duration']:5.2f}s, {info['width']}x{info['height']}, {info['fps']:.2f} FPS")
        
        if not video_infos:
            print("No valid video files found!")
            return False
        
        # Use first video's properties as reference
        first_video_path, first_info = video_infos[0]
        reference_fps = target_fps if target_fps else first_info['fps']
        reference_width = first_info['width']
        reference_height = first_info['height']
        
        print(f"\n=== STITCHING SUMMARY ===")
        print(f"Total videos: {len(video_infos)}")
        print(f"Total frames: {total_frames:,}")
        print(f"Total duration: {total_duration:.2f} seconds ({total_duration/60:.2f} minutes)")
        print(f"Output resolution: {reference_width}x{reference_height}")
        print(f"Output FPS: {reference_fps:.2f}")
        print(f"Output file: {output_path}")
        
        # Create output directory
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        
        # Create video writer
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(output_path, fourcc, reference_fps, (reference_width, reference_height))
        
        if not out.isOpened():
            print(f"Error: Could not create output video writer")
            return False
        
        print(f"\n=== STITCHING IN PROGRESS ===")
        
        total_processed_frames = 0
        
        # Process each video
        for video_index, (video_path, info) in enumerate(video_infos):
            print(f"Processing video {video_index + 1}/{len(video_infos)}: {Path(video_path).name}")
            
            cap = cv2.VideoCapture(video_path)
            if not cap.isOpened():
                print(f"Error: Cannot open {video_path}")
                continue
            
            frame_count = 0
            
            while True:
                ret, frame = cap.read()
                if not ret:
                    break
                
                # Resize frame if necessary
                if frame.shape[:2] != (reference_height, reference_width):
                    frame = cv2.resize(frame, (reference_width, reference_height))
                
                # Add transition info overlay if requested
                if add_transition_info:
                    # Add semi-transparent background for text
                    overlay = frame.copy()
                    
                    # Determine text content
                    file_name = Path(video_path).stem
                    text1 = f"File {video_index + 1}/{len(video_infos)}: {file_name}"
                    text2 = f"Frame {frame_count + 1}/{info['frame_count']} | Total: {total_processed_frames + 1:,}"
                    
                    # Calculate text size and position
                    font = cv2.FONT_HERSHEY_SIMPLEX
                    font_scale = 0.6
                    thickness = 1
                    
                    (text1_width, text1_height), _ = cv2.getTextSize(text1, font, font_scale, thickness)
                    (text2_width, text2_height), _ = cv2.getTextSize(text2, font, font_scale, thickness)
                    
                    # Add background rectangle
                    bg_height = text1_height + text2_height + 20
                    bg_width = max(text1_width, text2_width) + 20
                    cv2.rectangle(overlay, (10, 10), (10 + bg_width, 10 + bg_height), (0, 0, 0), -1)
                    
                    # Blend with original frame for transparency
                    alpha = 0.7
                    frame = cv2.addWeighted(overlay, alpha, frame, 1 - alpha, 0)
                    
                    # Add text
                    cv2.putText(frame, text1, (20, 30), font, font_scale, (0, 255, 0), thickness)
                    cv2.putText(frame, text2, (20, 55), font, font_scale, (255, 255, 255), thickness)
                
                out.write(frame)
                frame_count += 1
                total_processed_frames += 1
                
                # Progress update every 100 frames
                if total_processed_frames % 100 == 0:
                    progress = (total_processed_frames / total_frames) * 100
                    print(f"  Progress: {total_processed_frames:,}/{total_frames:,} frames ({progress:.1f}%)")
            
            cap.release()
            print(f"  Completed: {frame_count} frames from {Path(video_path).name}")
        
        out.release()
        
        print(f"\n=== STITCHING COMPLETE ===")
        print(f"Output saved: {output_path}")
        print(f"Total frames processed: {total_processed_frames:,}")
        print(f"Final duration: {total_processed_frames / reference_fps:.2f} seconds")
        
        return True
    
    def create_summary_report(self, input_pattern, output_report_path):
        """
        Create a text report summarizing all videos to be stitched
        """
        video_files = glob.glob(input_pattern)
        video_files.sort(key=self.natural_sort_key)
        
        report_lines = []
        report_lines.append("=== VIDEO STITCHING SUMMARY REPORT ===\n")
        report_lines.append(f"Input pattern: {input_pattern}")
        report_lines.append(f"Total files found: {len(video_files)}\n")
        
        total_duration = 0
        total_frames = 0
        
        for i, video_file in enumerate(video_files):
            info = self.get_video_info(video_file)
            if info:
                total_duration += info['duration']
                total_frames += info['frame_count']
                
                report_lines.append(f"{i+1:2d}. {Path(video_file).name}")
                report_lines.append(f"    Frames: {info['frame_count']:4d} | Duration: {info['duration']:6.2f}s | Resolution: {info['width']}x{info['height']} | FPS: {info['fps']:.2f}")
        
        report_lines.append(f"\nTOTAL SUMMARY:")
        report_lines.append(f"Total frames: {total_frames:,}")
        report_lines.append(f"Total duration: {total_duration:.2f} seconds ({total_duration/60:.2f} minutes)")
        
        # Save report
        Path(output_report_path).parent.mkdir(parents=True, exist_ok=True)
        with open(output_report_path, 'w') as f:
            f.write('\n'.join(report_lines))
        
        print(f"Summary report saved: {output_report_path}")
        return '\n'.join(report_lines)


# Usage
if __name__ == "__main__":
    stitcher = VideoStitcher()
    
    # Define input and output paths
    input_pattern = "data/all_files_high_contrast/*_HIGH_CONTRAST_ONLY_500_67fps.mp4"
    output_video = "data/final_stitched/FINAL_STITCHED_500_67fps.mp4"
    summary_report = "data/final_stitched/summary.txt"
    
    print("=== HIGH CONTRAST VIDEO STITCHER ===\n")
    
    # First, create a summary report
    print("Creating summary report...")
    report_content = stitcher.create_summary_report(input_pattern, summary_report)
    print("\n" + report_content)
    
    # Ask for confirmation (comment out if you want to run automatically)
    # response = input("\nProceed with stitching? (y/n): ")
    # if response.lower() != 'y':
    #     print("Stitching cancelled.")
    #     exit()
    
    # Stitch all videos
    print("\n" + "="*50)
    success = stitcher.stitch_videos(
        input_pattern=input_pattern,
        output_path=output_video,
        target_fps=500.67,  # Keep original FPS
        add_transition_info=True  # Add overlay showing which file is currently playing
    )
    
    if success:
        print(f"\n🎉 SUCCESS! All videos stitched into: {output_video}")
    else:
        print(f"\n❌ FAILED to create stitched video")
    
    # Alternative: Stitch without transition info overlay
    # output_clean = "data/final_stitched/ALL_HIGH_CONTRAST_CLEAN_500_67fps.mp4"
    # stitcher.stitch_videos(
    #     input_pattern=input_pattern,
    #     output_path=output_clean,
    #     target_fps=500.67,
    #     add_transition_info=False  # Clean version without overlay
    # )