"""
VSD Data Video Export Tool (OpenCV Version)

Creates side-by-side comparison videos of raw vs motion-corrected VSD data
using OpenCV for reliable video generation.

Usage:
    python vsd_video_export.py --raw converted__500/led_E0B4.h5 --corrected data/motion_corrected/led_E0B4_vsd_corrected.h5
    
    # With custom mixing method:
    python vsd_video_export.py --raw data.h5 --corrected corrected.h5 --mix-method additive
"""

import h5py
import numpy as np
import cv2
import argparse
import os
from pathlib import Path
from tqdm import tqdm

class VSDVideoExporter:
    def __init__(self):
        self.mixing_methods = {
            'alpha_blend': self._alpha_blend,
            'additive': self._additive,
            'screen': self._screen,
            'overlay': self._overlay,
            'maximum': self._maximum
        }
        
    def load_raw_data(self, h5_file):
        """Load and separate raw interleaved data"""
        print(f"Loading raw data from: {h5_file}")
        
        with h5py.File(h5_file, 'r') as f:
            datasets = list(f.keys())
            print(f"Available datasets: {datasets}")
            
            if 'image_stack' in datasets:
                data = f['image_stack'][:]
            else:
                data = f[datasets[0]][:]
        
        print(f"Raw data shape: {data.shape}")
        
        # Ensure correct orientation [frames, height, width]
        if data.shape[0] == 1500:  # frames first
            pass
        elif data.shape[2] == 1500:  # frames last
            data = np.transpose(data, (2, 0, 1))
        elif data.shape[1] == 1500:  # frames middle
            data = np.transpose(data, (1, 0, 2))
        else:
            raise ValueError(f"Cannot determine frame dimension from shape {data.shape}")
        
        # Separate channels
        structural = data[1::2, :, :]  # Even indices in original (1, 3, 5, ...)
        functional = data[0::2, :, :]  # Odd indices in original (0, 2, 4, ...)
        
        print(f"Structural channel shape: {structural.shape}")
        print(f"Functional channel shape: {functional.shape}")
        
        return structural, functional
    
    def load_corrected_data(self, h5_file):
        """Load motion-corrected data"""
        print(f"Loading corrected data from: {h5_file}")
        
        with h5py.File(h5_file, 'r') as f:
            datasets = list(f.keys())
            print(f"Available datasets: {datasets}")
            
            if 'structural_corrected' in datasets and 'functional_corrected' in datasets:
                structural = f['structural_corrected'][:]
                functional = f['functional_corrected'][:]
            elif 'ch1' in datasets and 'ch2' in datasets:
                structural = f['ch1'][:]
                functional = f['ch2'][:]
            else:
                raise ValueError(f"Cannot find expected corrected datasets. Available: {datasets}")
        
        # Ensure correct orientation [frames, height, width]
        if structural.ndim == 3:
            if structural.shape[0] != 750:
                if structural.shape[2] == 750:
                    structural = np.transpose(structural, (2, 0, 1))
                    functional = np.transpose(functional, (2, 0, 1))
                elif structural.shape[1] == 750:
                    structural = np.transpose(structural, (1, 0, 2))
                    functional = np.transpose(functional, (1, 0, 2))
        
        print(f"Corrected structural shape: {structural.shape}")
        print(f"Corrected functional shape: {functional.shape}")
        
        return structural, functional
    
    def normalize_channel(self, data, percentile_range=(1, 99)):
        """Normalize channel data to 0-255 range"""
        data_flat = data.reshape(-1)
        p_low, p_high = np.percentile(data_flat, percentile_range)
        
        # Clip and normalize
        data_norm = np.clip(data, p_low, p_high)
        if p_high > p_low:
            data_norm = (data_norm - p_low) / (p_high - p_low) * 255
        else:
            data_norm = np.zeros_like(data_norm)
        
        return data_norm.astype(np.uint8)
    
    def create_colored_frame(self, structural, functional, mix_method='alpha_blend'):
        """Create colored frame: Green+Blue for structural, Red+Blue for functional"""
        height, width = structural.shape
        
        # Normalize channels
        struct_norm = self.normalize_channel(structural)
        func_norm = self.normalize_channel(functional)
        
        # Create RGB channels (OpenCV uses BGR)
        # Structural: Green + Blue (BGR: Blue=255, Green=255, Red=0)
        struct_bgr = np.zeros((height, width, 3), dtype=np.uint8)
        struct_bgr[:, :, 0] = struct_norm  # Blue
        struct_bgr[:, :, 1] = struct_norm  # Green
        
        # Functional: Red + Blue (BGR: Blue=255, Green=0, Red=255)
        func_bgr = np.zeros((height, width, 3), dtype=np.uint8)
        func_bgr[:, :, 0] = func_norm  # Blue
        func_bgr[:, :, 2] = func_norm  # Red
        
        # Mix channels
        mixed = self.mixing_methods[mix_method](struct_bgr, func_bgr)
        
        return np.clip(mixed, 0, 255).astype(np.uint8)
    
    def _alpha_blend(self, img1, img2, alpha=0.5):
        """50/50 transparent overlay"""
        return cv2.addWeighted(img1, alpha, img2, 1-alpha, 0)
    
    def _additive(self, img1, img2):
        """Add colors together (brighter)"""
        return cv2.add(img1, img2)
    
    def _screen(self, img1, img2):
        """Screen blend (lighter, good for overlapping data)"""
        img1_f = img1.astype(np.float32) / 255.0
        img2_f = img2.astype(np.float32) / 255.0
        result = 1 - (1 - img1_f) * (1 - img2_f)
        return (result * 255).astype(np.uint8)
    
    def _overlay(self, img1, img2):
        """Preserves highlights and shadows"""
        img1_f = img1.astype(np.float32) / 255.0
        img2_f = img2.astype(np.float32) / 255.0
        
        mask = img1_f < 0.5
        result = np.where(mask, 
                         2 * img1_f * img2_f,
                         1 - 2 * (1 - img1_f) * (1 - img2_f))
        return (result * 255).astype(np.uint8)
    
    def _maximum(self, img1, img2):
        """Takes the maximum value of each channel"""
        return np.maximum(img1, img2)
    
    def create_side_by_side_frame(self, raw_struct, raw_func, corr_struct, corr_func, mix_method):
        """Create side-by-side comparison frame"""
        # Create colored frames
        raw_colored = self.create_colored_frame(raw_struct, raw_func, mix_method)
        corr_colored = self.create_colored_frame(corr_struct, corr_func, mix_method)
        
        # Resize if needed
        if raw_colored.shape != corr_colored.shape:
            corr_colored = cv2.resize(corr_colored, (raw_colored.shape[1], raw_colored.shape[0]))
        
        # Add text labels
        cv2.putText(raw_colored, 'Raw Data', (10, 30), 
                   cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
        cv2.putText(corr_colored, 'Motion Corrected', (10, 30), 
                   cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
        
        # Create side-by-side with separator
        separator_width = 10
        height, width = raw_colored.shape[:2]
        
        side_by_side = np.zeros((height, width*2 + separator_width, 3), dtype=np.uint8)
        side_by_side[:, :width] = raw_colored
        side_by_side[:, width:width+separator_width] = [50, 50, 50]  # Gray separator
        side_by_side[:, width+separator_width:] = corr_colored
        
        return side_by_side
    
    def export_videos(self, raw_file, corrected_file, output_dir='videos', 
                     fps_rates=[500.67, 250.335, 125.17], mix_method='alpha_blend'):
        """Export comparison videos at different frame rates"""
        
        os.makedirs(output_dir, exist_ok=True)
        
        # Load data
        raw_struct, raw_func = self.load_raw_data(raw_file)
        corr_struct, corr_func = self.load_corrected_data(corrected_file)
        
        # Ensure same number of frames
        min_frames = min(raw_struct.shape[0], corr_struct.shape[0])
        raw_struct = raw_struct[:min_frames]
        raw_func = raw_func[:min_frames]
        corr_struct = corr_struct[:min_frames]
        corr_func = corr_func[:min_frames]
        
        print(f"Processing {min_frames} frames with mixing method: {mix_method}")
        
        # Get sample frame for dimensions
        sample_frame = self.create_side_by_side_frame(
            raw_struct[0], raw_func[0], corr_struct[0], corr_func[0], mix_method)
        frame_height, frame_width = sample_frame.shape[:2]
        
        # Export videos at different frame rates
        for fps in fps_rates:
            output_file = os.path.join(output_dir, f'vsd_comparison_{fps:.2f}fps_{mix_method}.mp4')
            print(f"\nExporting video at {fps:.2f} fps...")
            
            # Setup video writer
            fourcc = cv2.VideoWriter_fourcc(*'mp4v')
            out = cv2.VideoWriter(output_file, fourcc, fps, (frame_width, frame_height))
            
            if not out.isOpened():
                print(f"Error: Could not open video writer for {output_file}")
                continue
            
            # Process frames with progress bar
            for i in tqdm(range(min_frames), desc=f'{fps:.2f} fps'):
                frame = self.create_side_by_side_frame(
                    raw_struct[i], raw_func[i], corr_struct[i], corr_func[i], mix_method)
                
                out.write(frame)
            
            out.release()
            print(f"Saved: {output_file}")
        
        # Export individual channel videos
        print("\nExporting individual channel videos...")
        self.export_individual_channels(raw_struct, raw_func, corr_struct, corr_func, 
                                       output_dir, fps_rates[0])
    
    def export_individual_channels(self, raw_struct, raw_func, corr_struct, corr_func, 
                                  output_dir, fps):
        """Export individual channel videos for reference"""
        
        channels = {
            'raw_structural': raw_struct,
            'raw_functional': raw_func, 
            'corrected_structural': corr_struct,
            'corrected_functional': corr_func
        }
        
        for name, data in channels.items():
            output_file = os.path.join(output_dir, f'{name}_{fps:.2f}fps.mp4')
            
            # Normalize data
            data_norm = self.normalize_channel(data)
            height, width = data_norm.shape[1:]
            
            # Setup video writer
            fourcc = cv2.VideoWriter_fourcc(*'mp4v')
            out = cv2.VideoWriter(output_file, fourcc, fps, (width, height), isColor=False)
            
            if not out.isOpened():
                print(f"Error: Could not open video writer for {name}")
                continue
            
            # Write frames
            for i in tqdm(range(data_norm.shape[0]), desc=f'{name}'):
                out.write(data_norm[i])
            
            out.release()
            print(f"Saved individual channel: {output_file}")
    
    def create_preview_comparison(self, raw_file, corrected_file, output_dir='videos'):
        """Create a preview image showing different mixing methods"""
        import matplotlib.pyplot as plt
        
        # Load data
        raw_struct, raw_func = self.load_raw_data(raw_file)
        corr_struct, corr_func = self.load_corrected_data(corrected_file)
        
        # Use middle frame
        mid_frame = min(raw_struct.shape[0], corr_struct.shape[0]) // 2
        
        fig, axes = plt.subplots(2, len(self.mixing_methods), figsize=(20, 8))
        fig.suptitle('Mixing Methods Preview - Raw (top) vs Corrected (bottom)', fontsize=16)
        
        for i, (method_name, _) in enumerate(self.mixing_methods.items()):
            # Raw data - convert BGR to RGB for matplotlib
            raw_colored = self.create_colored_frame(
                raw_struct[mid_frame], raw_func[mid_frame], method_name)
            raw_rgb = cv2.cvtColor(raw_colored, cv2.COLOR_BGR2RGB)
            axes[0, i].imshow(raw_rgb)
            axes[0, i].set_title(f'Raw - {method_name}')
            axes[0, i].axis('off')
            
            # Corrected data - convert BGR to RGB for matplotlib
            corr_colored = self.create_colored_frame(
                corr_struct[mid_frame], corr_func[mid_frame], method_name)
            corr_rgb = cv2.cvtColor(corr_colored, cv2.COLOR_BGR2RGB)
            axes[1, i].imshow(corr_rgb)
            axes[1, i].set_title(f'Corrected - {method_name}')
            axes[1, i].axis('off')
        
        plt.tight_layout()
        preview_file = os.path.join(output_dir, 'mixing_methods_preview.png')
        os.makedirs(output_dir, exist_ok=True)
        plt.savefig(preview_file, dpi=150, bbox_inches='tight')
        plt.close()
        
        print(f"Mixing methods preview saved: {preview_file}")


def main():
    parser = argparse.ArgumentParser(description='Export VSD data comparison videos')
    parser.add_argument('--raw', required=True, help='Raw data H5 file')
    parser.add_argument('--corrected', required=True, help='Motion-corrected data H5 file')
    parser.add_argument('--output-dir', default='videos', help='Output directory')
    parser.add_argument('--fps', nargs='+', type=float, default=[500.67, 250.335, 125.17],
                       help='Frame rates for video export')
    parser.add_argument('--mix-method', default='alpha_blend',
                       choices=['alpha_blend', 'additive', 'screen', 'overlay', 'maximum'],
                       help='Channel mixing method')
    parser.add_argument('--preview-only', action='store_true',
                       help='Only create preview of mixing methods')
    
    args = parser.parse_args()
    
    exporter = VSDVideoExporter()
    
    print("VSD Video Export Tool (OpenCV)")
    print("==============================")
    print(f"Raw data: {args.raw}")
    print(f"Corrected data: {args.corrected}")
    print(f"Output directory: {args.output_dir}")
    print(f"Frame rates: {args.fps}")
    print(f"Mixing method: {args.mix_method}")
    print("\nColor scheme:")
    print("  Structural channel (even indices): Green + Blue")
    print("  Functional channel (odd indices): Red + Blue")
    print("\nMixing method options:")
    print("  alpha_blend - 50/50 transparent overlay")
    print("  additive - Add colors together (brighter)")
    print("  screen - Screen blend (lighter, good for overlapping data)")
    print("  overlay - Preserves highlights and shadows")
    print("  maximum - Takes the maximum value of each channel")
    
    if args.preview_only:
        print("\nCreating mixing methods preview...")
        exporter.create_preview_comparison(args.raw, args.corrected, args.output_dir)
    else:
        print("\nStarting video export...")
        exporter.create_preview_comparison(args.raw, args.corrected, args.output_dir)
        exporter.export_videos(args.raw, args.corrected, args.output_dir, args.fps, args.mix_method)
    
    print("\nDone!")


if __name__ == '__main__':
    main()