"""
Streamlined VSD Video Export - Enhanced version with pseudocolor toggle and configurable output
takes raw input and motion-corrected data, creates side-by-side comparison video.

Usage: 
python script.py --raw data.h5 --corrected corrected.h5 --no-pseudocolor --output results/grayscale_comparison.mp4 --fps 200
python raw_vs_motion_visualization_v2.py --raw converted__500/led_E0B0.h5 --corrected data/motion_corrected/led_E0B0_vsd_corrected.h5 --no-pseudocolor --output data/motion_corrected/led_E0B0_comparison.mp4
"""

import h5py
import numpy as np
import cv2
import argparse
import os
from tqdm import tqdm

def load_and_separate(h5_file, is_raw=True):
    """Load data and separate structural/functional channels"""
    with h5py.File(h5_file, 'r') as f:
        if is_raw:
            data = f['image_stack'][:] if 'image_stack' in f else f[list(f.keys())[0]][:]
            # Ensure [frames, height, width] orientation
            if data.shape[0] != 1500:
                data = np.transpose(data, (2, 0, 1)) if data.shape[2] == 1500 else np.transpose(data, (1, 0, 2))
            # Separate interleaved channels (matching MATLAB indexing)
            structural = data[1::2]  # Even frames (structural)
            functional = data[0::2]  # Odd frames (functional)
        else:
            # Motion-corrected data
            if 'structural' in f and 'functional' in f:
                structural, functional = f['structural'][:], f['functional'][:]
            else:
                structural, functional = f['ch1'][:], f['ch2'][:]
            # Ensure [frames, height, width]
            if structural.shape[0] != 750:
                structural = np.transpose(structural, (2, 0, 1))
                functional = np.transpose(functional, (2, 0, 1))
    
    return structural, functional

def normalize_frame(data, pct=(1, 99)):
    """Normalize to 0-255 using percentiles"""
    p_low, p_high = np.percentile(data, pct)
    return np.clip((data - p_low) / (p_high - p_low) * 255, 0, 255).astype(np.uint8)

def create_colored_frame(structural, functional, use_pseudocolor=True):
    """Create RGB frame: Structural=Cyan, Functional=Magenta (if pseudocolor enabled)"""
    h, w = structural.shape
    s_norm, f_norm = normalize_frame(structural), normalize_frame(functional)
    
    if use_pseudocolor:
        # BGR format: Structural (cyan), Functional (magenta)
        frame = np.zeros((h, w, 3), dtype=np.uint8)
        frame[:, :, 0] = np.maximum(s_norm, f_norm)  # Blue
        frame[:, :, 1] = s_norm                      # Green  
        frame[:, :, 2] = f_norm                      # Red
    else:
        # Grayscale: combine channels as weighted average
        combined = (0.7 * s_norm + 0.3 * f_norm).astype(np.uint8)
        frame = cv2.cvtColor(combined, cv2.COLOR_GRAY2BGR)
    
    return frame

def export_comparison_video(raw_file, corrected_file, output_path=None, fps=250.335, use_pseudocolor=True):
    """Export side-by-side comparison video"""
    
    # Handle output path
    if output_path is None:
        output_dir = 'videos'
        os.makedirs(output_dir, exist_ok=True)
        color_suffix = '_pseudocolor' if use_pseudocolor else '_grayscale'
        output_path = os.path.join(output_dir, f'vsd_comparison{color_suffix}_{fps:.0f}fps.mp4')
    else:
        # Create directory if needed
        output_dir = os.path.dirname(output_path)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir, exist_ok=True)
        # Ensure .mp4 extension
        if not output_path.lower().endswith('.mp4'):
            output_path += '.mp4'
    
    # Load data
    raw_struct, raw_func = load_and_separate(raw_file, is_raw=True)
    corr_struct, corr_func = load_and_separate(corrected_file, is_raw=False)
    
    # Match frame counts
    min_frames = min(len(raw_struct), len(corr_struct))
    color_mode = "pseudocolor" if use_pseudocolor else "grayscale"
    print(f"Processing {min_frames} frames at {fps} fps in {color_mode} mode")
    
    # Setup video writer
    sample = create_colored_frame(raw_struct[0], raw_func[0], use_pseudocolor)
    h, w = sample.shape[:2]
    
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(output_path, fourcc, fps, (w*2 + 10, h))
    
    # Process frames
    for i in tqdm(range(min_frames)):
        raw_frame = create_colored_frame(raw_struct[i], raw_func[i], use_pseudocolor)
        corr_frame = create_colored_frame(corr_struct[i], corr_func[i], use_pseudocolor)
        
        # Add labels
        cv2.putText(raw_frame, 'Raw', (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
        cv2.putText(corr_frame, 'Corrected', (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
        
        # Side-by-side with separator
        combined = np.zeros((h, w*2 + 10, 3), dtype=np.uint8)
        combined[:, :w] = raw_frame
        combined[:, w:w+10] = [50, 50, 50]
        combined[:, w+10:] = corr_frame
        
        out.write(combined)
    
    out.release()
    print(f'Video saved: {output_path}')

def main():
    parser = argparse.ArgumentParser(description='VSD Video Export')
    parser.add_argument('--raw', required=True, help='Raw data H5 file')
    parser.add_argument('--corrected', required=True, help='Motion-corrected H5 file')
    parser.add_argument('--output', '-o', default=None, 
                        help='Output video path/filename (default: videos/vsd_comparison_[mode]_[fps]fps.mp4)')
    parser.add_argument('--fps', type=float, default=250.335, help='Video frame rate')
    parser.add_argument('--no-pseudocolor', action='store_true', 
                        help='Disable pseudocolor (use grayscale instead)')
    
    args = parser.parse_args()
    
    use_pseudocolor = not args.no_pseudocolor
    export_comparison_video(args.raw, args.corrected, args.output, args.fps, use_pseudocolor)

if __name__ == '__main__':
    main()