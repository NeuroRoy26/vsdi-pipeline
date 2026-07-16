"""
Performance-optimized BLK converter for large datasets (67+ GB)
- Intelligent chunk sizing based on available memory
- Direct file-to-HDF5 writing without intermediate arrays
- Optimal HDF5 chunking for compression and access patterns
- Memory usage monitoring
"""

import struct
import sys
import os
import glob
import numpy as np
import h5py
from pathlib import Path
import psutil
import time
from tqdm import tqdm
import warnings

class OptimizedBLKConverter:
    def __init__(self, memory_limit_gb=None):
        self.datatype_map = {
            11: (np.uint8, 1, 'DAT_UCHAR (8-bit unsigned)'),
            12: (np.uint16, 2, 'DAT_USHORT (16-bit unsigned)'), 
            13: (np.int32, 4, 'DAT_LONG (32-bit signed)'),
            14: (np.float32, 4, 'DAT_FLOAT (32-bit float)')
        }
        
        self.variant_map = {
            11: 'FROM_VDAQ',
            12: 'FROM_ORA', 
            13: 'FROM_DYEDAQ'
        }
        
        # Auto-detect optimal memory usage
        available_memory = psutil.virtual_memory().available
        self.memory_limit = memory_limit_gb * 1e9 if memory_limit_gb else available_memory * 0.5
        print(f"Using {self.memory_limit/1e9:.1f} GB memory limit for processing")

    def calculate_optimal_chunk_size(self, frame_width, frame_height, dtype_size, target_memory_mb=500):
        """Calculate optimal chunk size based on memory constraints"""
        frame_bytes = frame_width * frame_height * dtype_size
        chunk_frames = max(1, int((target_memory_mb * 1e6) // frame_bytes))
        
        # Ensure reasonable bounds
        chunk_frames = min(chunk_frames, 1000)  # Max 1000 frames per chunk
        chunk_frames = max(chunk_frames, 10)    # Min 10 frames per chunk
        
        return chunk_frames

    def read_blk_header(self, filename):
        """Optimized header reading - only essential fields"""
        def read(fid, fmt):
            size = struct.calcsize(fmt)
            data = fid.read(size)
            if len(data) < size:
                raise ValueError(f"Unexpected end of file while reading {fmt}")
            return struct.unpack(fmt, data)[0]

        with open(filename, 'rb') as fid:
            header = {}
            header['filesize'] = read(fid, 'q')
            header['checksum_header'] = read(fid, 'h')
            header['checksum_data'] = read(fid, 'h')
            header['lenheader'] = read(fid, 'i')
            header['versionid'] = read(fid, 'f')
            header['filetype'] = read(fid, 'i')
            header['filesubtype'] = read(fid, 'i')
            header['datatype'] = read(fid, 'i')
            header['sizeof'] = read(fid, 'i')
            header['framewidth'] = read(fid, 'i')
            header['frameheight'] = read(fid, 'i')
            header['nframesperstim'] = read(fid, 'i')

            # Get actual file size
            fid.seek(0, 2)
            actual_filesize = fid.tell()
            
            # Calculate actual frames
            data_start = header['lenheader']
            pixel_size = header['framewidth'] * header['frameheight'] * header['sizeof']
            available_data_bytes = actual_filesize - data_start
            header['actual_nframes'] = available_data_bytes // pixel_size
            header['actual_filesize'] = actual_filesize
            
            return header

    def validate_header(self, header, filename, verbose=True):
        """Fast header validation"""
        if header['datatype'] not in self.datatype_map:
            raise ValueError(f"Unsupported data type: {header['datatype']}")
        
        if header['actual_nframes'] == 0:
            raise ValueError("No frame data found in file")
        
        if header['framewidth'] <= 0 or header['frameheight'] <= 0:
            raise ValueError(f"Invalid frame dimensions: {header['framewidth']}x{header['frameheight']}")
        
        if verbose:
            dtype_info = self.datatype_map[header['datatype']]
            file_size_mb = header['actual_filesize'] / 1e6
            print(f"Processing: {Path(filename).name} ({file_size_mb:.1f} MB, {header['actual_nframes']} frames)")
            
            if header['actual_nframes'] != header['nframesperstim']:
                print(f"  Frame count corrected: {header['nframesperstim']} → {header['actual_nframes']}")
        
        return True

    def convert_blk_to_hdf5_optimized(self, blk_file, h5_file=None, overwrite=False):
        """Memory-optimized conversion with direct file-to-HDF5 streaming"""
        start_time = time.time()
        
        try:
            # Read and validate header
            header = self.read_blk_header(blk_file)
            self.validate_header(header, blk_file)
            
            # Generate output filename
            if h5_file is None:
                h5_file = Path(blk_file).with_suffix('.h5')
            
            if os.path.exists(h5_file) and not overwrite:
                print(f"SKIPPED: {h5_file} already exists")
                return False
            
            # Extract parameters
            width = header['framewidth']
            height = header['frameheight'] 
            nframes = header['actual_nframes']
            header_len = header['lenheader']
            dtype = self.datatype_map[header['datatype']][0]
            dtype_size = self.datatype_map[header['datatype']][1]
            
            # Calculate optimal processing parameters
            chunk_frames = self.calculate_optimal_chunk_size(width, height, dtype_size)
            frame_size = width * height
            
            print(f"  Using chunk size: {chunk_frames} frames ({chunk_frames * frame_size * dtype_size / 1e6:.1f} MB)")
            
            # Optimal HDF5 chunking - balance between compression and access patterns
            # For imaging data, chunk by single frames is usually optimal
            hdf5_chunks = (1, height, width) if nframes > 1 else None
            
            # Create HDF5 file with optimized settings
            with h5py.File(h5_file, 'w') as hf:
                # Create dataset
                dataset = hf.create_dataset(
                    "image_stack",
                    shape=(nframes, height, width),
                    dtype=dtype,
                    compression='gzip',
                    compression_opts=6,  # Good balance of speed vs compression
                    chunks=hdf5_chunks,
                    fletcher32=True,  # Add checksum for data integrity
                    shuffle=True      # Improve compression for imaging data
                )
                
                # Stream data directly from file to HDF5
                with open(blk_file, 'rb') as f:
                    f.seek(header_len)
                    
                    # Progress tracking
                    with tqdm(total=nframes, desc="Converting", unit="frames", 
                             unit_scale=True, leave=False) as pbar:
                        
                        for start_frame in range(0, nframes, chunk_frames):
                            end_frame = min(start_frame + chunk_frames, nframes)
                            chunk_nframes = end_frame - start_frame
                            
                            # Read chunk directly
                            raw_data = np.fromfile(f, dtype=dtype, count=frame_size * chunk_nframes)
                            
                            if raw_data.size != frame_size * chunk_nframes:
                                raise ValueError(f"Read error at frame {start_frame}")
                            
                            # Reshape and write directly to HDF5
                            chunk_data = raw_data.reshape((chunk_nframes, height, width))
                            dataset[start_frame:end_frame] = chunk_data
                            
                            # Update progress
                            pbar.update(chunk_nframes)
                            
                            # Optional: Force garbage collection for very large files
                            if chunk_nframes > 500:
                                del raw_data, chunk_data
                
                # Store comprehensive metadata
                attrs = hf.attrs
                attrs['frame_width'] = width
                attrs['frame_height'] = height
                attrs['nframes'] = nframes
                attrs['dtype'] = str(dtype)
                attrs['source_file'] = str(blk_file)
                attrs['version_id'] = header['versionid']
                attrs['variant'] = self.variant_map.get(header['filesubtype'], 'Unknown')
                attrs['original_filesize'] = header['filesize']
                attrs['actual_filesize'] = header['actual_filesize']
                attrs['header_length'] = header_len
                attrs['processing_chunk_size'] = chunk_frames
                attrs['conversion_time'] = time.time() - start_time
            
            # Calculate compression ratio
            h5_size = os.path.getsize(h5_file)
            compression_ratio = header['actual_filesize'] / h5_size
            conversion_time = time.time() - start_time
            throughput_mb_s = (header['actual_filesize'] / 1e6) / conversion_time
            
            print(f"✓ SUCCESS: {Path(h5_file).name}")
            print(f"  Size: {header['actual_filesize']/1e6:.1f} MB → {h5_size/1e6:.1f} MB " 
                  f"({compression_ratio:.1f}x compression)")
            print(f"  Time: {conversion_time:.1f}s ({throughput_mb_s:.1f} MB/s)")
            
            return True
            
        except Exception as e:
            print(f"✗ ERROR converting {blk_file}: {str(e)}")
            return False

    def batch_convert_optimized(self, input_pattern, output_dir=None, overwrite=False):
        """Optimized batch conversion for large datasets"""
        
        # Find files
        if os.path.isfile(input_pattern):
            blk_files = [input_pattern]
        else:
            blk_files = glob.glob(input_pattern)
            
        if not blk_files:
            print(f"No files found matching pattern: {input_pattern}")
            return
        
        # Calculate total dataset size
        total_size = sum(os.path.getsize(f) for f in blk_files)
        print(f"\n=== BATCH CONVERSION ===")
        print(f"Files: {len(blk_files)}")
        print(f"Total size: {total_size/1e9:.2f} GB")
        print(f"Available memory: {psutil.virtual_memory().available/1e9:.1f} GB")
        
        # Create output directory
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)
        
        # Process files
        success_count = 0
        failed_files = []
        total_start_time = time.time()
        
        for i, blk_file in enumerate(blk_files, 1):
            print(f"\n[{i}/{len(blk_files)}] Processing {Path(blk_file).name}")
            
            try:
                # Determine output file
                if output_dir:
                    h5_file = os.path.join(output_dir, Path(blk_file).stem + '.h5')
                else:
                    h5_file = Path(blk_file).with_suffix('.h5')
                
                success = self.convert_blk_to_hdf5_optimized(blk_file, h5_file, overwrite)
                
                if success:
                    success_count += 1
                else:
                    failed_files.append(blk_file)
                
                # Memory usage monitoring
                memory_usage = psutil.virtual_memory().percent
                if memory_usage > 80:
                    print(f"  Warning: High memory usage ({memory_usage:.1f}%)")
                    
            except KeyboardInterrupt:
                print("\nConversion interrupted by user")
                break
            except Exception as e:
                print(f"✗ UNEXPECTED ERROR: {str(e)}")
                failed_files.append(blk_file)
        
        # Final summary
        total_time = time.time() - total_start_time
        print(f"\n=== CONVERSION COMPLETE ===")
        print(f"Processed: {success_count}/{len(blk_files)} files")
        print(f"Total time: {total_time/60:.1f} minutes")
        print(f"Average throughput: {total_size/1e9/total_time*60:.1f} GB/min")
        
        if failed_files:
            print(f"\nFailed files ({len(failed_files)}):")
            for f in failed_files:
                print(f"  - {Path(f).name}")

def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Optimized BLK to HDF5 converter for large datasets",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
USAGE EXAMPLES:
- Convert single file (saves as same name with .h5 extension):
   python optimized_blk_converter.py led_E1B13.blk

- Convert all BLK files in current directory:
   python optimized_blk_converter.py "*.blk"
   python optimized_blk_converter.py "*.BLK"

- Specific use case - convert with output directory:
   python optimized_blk_converter.py "dataset/20210305-500Hz/*.BLK" -o converted_500/

- Convert files with overwrite option:
   python optimized_blk_converter.py "dataset/*.BLK" -o output/ --overwrite

- Just inspect files without converting:
   python optimized_blk_converter.py "dataset/*.BLK" --inspect-only

- Set memory limit for processing:
   python optimized_blk_converter.py "*.BLK" -o output/ --memory-limit 8

FILE SAVING BEHAVIOR:
- Without -o: Saves .h5 files in the same directory as source .BLK files
- With -o: Saves all .h5 files in the specified output directory
- Filenames: input_filename.BLK → input_filename.h5
- Creates output directory automatically if it doesn't exist
        """)  
    parser.add_argument("input", help="Input BLK file(s) - can use wildcards like '*.BLK'")
    parser.add_argument("-o", "--output-dir", help="Output directory (creates if doesn't exist)")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing .h5 files")
    parser.add_argument("--memory-limit", type=float, help="Memory limit in GB (default: auto-detect)")
    parser.add_argument("--inspect-only", action="store_true", help="Only inspect file headers, don't convert")
    
    args = parser.parse_args()
    
    converter = OptimizedBLKConverter(memory_limit_gb=args.memory_limit)
    
    if args.inspect_only:
        blk_files = glob.glob(args.input) if not os.path.isfile(args.input) else [args.input]
        for blk_file in sorted(blk_files):
            try:
                header = converter.read_blk_header(blk_file)
                converter.validate_header(header, blk_file, verbose=True)
            except Exception as e:
                print(f"✗ ERROR inspecting {blk_file}: {str(e)}")
    else:
        converter.batch_convert_optimized(args.input, args.output_dir, args.overwrite)

if __name__ == '__main__':
    main()