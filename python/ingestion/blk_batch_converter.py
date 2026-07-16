"""
blk_batch_converter.py

Batch convert BLK files to HDF5.

Usage:
    # Convert a single file:
    python blk_batch_converter.py led_E1B13.blk

    # Convert all BLK files in current directory:
    python blk_batch_converter.py "*.blk"

    # Convert with output directory:
    python blk_batch_converter.py "*.blk" -o converted_h5/

    # Inspect files without converting:
    python blk_batch_converter.py "*.blk" --inspect-only

    # Overwrite existing files:
    python blk_batch_converter.py "*.blk" --overwrite
"""
# MY USECASE in the environment: python blk_batch_converter.py "dataset/20210305-500Hz/*.BLK" -o converted__500/

import struct
import sys
import os
import glob
import numpy as np
import h5py
from pathlib import Path

class BLKConverter:
    def __init__(self):
        self.datatype_map = {
            11: (np.uint8, 'DAT_UCHAR (8-bit unsigned)'),
            12: (np.uint16, 'DAT_USHORT (16-bit unsigned)'),
            13: (np.int32, 'DAT_LONG (32-bit signed)'),
            14: (np.float32, 'DAT_FLOAT (32-bit float)')
        }
        
        self.variant_map = {
            11: 'FROM_VDAQ',
            12: 'FROM_ORA',
            13: 'FROM_DYEDAQ'
        }

    def read_blk_header(self, filename):
        """Extract header information from BLK file"""
        def read(fid, fmt):
            size = struct.calcsize(fmt)
            data = fid.read(size)
            if len(data) < size:
                raise ValueError(f"Unexpected end of file while reading {fmt}")
            return struct.unpack(fmt, data)[0]

        with open(filename, 'rb') as fid:
            header = {}
            header['filesize'] = read(fid, 'q')  # 8 bytes long
            header['checksum_header'] = read(fid, 'h')
            header['checksum_data'] = read(fid, 'h')
            header['lenheader'] = read(fid, 'i')
            header['versionid'] = read(fid, 'f')  # May be corrupted in some files
            header['filetype'] = read(fid, 'i')
            header['filesubtype'] = read(fid, 'i')
            header['datatype'] = read(fid, 'i')
            header['sizeof'] = read(fid, 'i')
            header['framewidth'] = read(fid, 'i')
            header['frameheight'] = read(fid, 'i')  # Fixed typo from original
            header['nframesperstim'] = read(fid, 'i')

            # Get actual file size and calculate real number of frames
            fid.seek(0, 2)
            actual_filesize = fid.tell()
            
            # Calculate actual number of frames based on file size
            data_start = header['lenheader']
            pixel_size = header['framewidth'] * header['frameheight'] * header['sizeof']
            available_data_bytes = actual_filesize - header['lenheader']
            header['actual_nframes'] = available_data_bytes // pixel_size
            
            return header

    def validate_header(self, header, filename):
        """Validate header information and print summary"""
        print(f"\n=== Processing: {filename} ===")
        print(f"File size: {header['filesize']} bytes")
        print(f"Header length: {header['lenheader']} bytes")
        print(f"Version ID: {header['versionid']:.6f} {'(may be corrupted)' if abs(header['versionid']) < 1e-30 else ''}")
        print(f"Variant: {self.variant_map.get(header['filesubtype'], 'Unknown')} ({header['filesubtype']})")
        
        dtype_info = self.datatype_map.get(header['datatype'])
        if dtype_info:
            print(f"Data type: {dtype_info[1]} ({header['datatype']})")
        else:
            raise ValueError(f"Unsupported data type: {header['datatype']}")
            
        print(f"Data element size: {header['sizeof']} bytes")
        print(f"Frame size: {header['framewidth']} x {header['frameheight']}")
        print(f"Frames (header): {header['nframesperstim']}")
        print(f"Frames (actual): {header['actual_nframes']}")
        
        if header['actual_nframes'] != header['nframesperstim']:
            print(f"INFO: Using actual frame count ({header['actual_nframes']}) instead of header count ({header['nframesperstim']})")
        
        return True

    def convert_blk_to_hdf5(self, blk_file, h5_file=None, overwrite=False):
        """Convert a single BLK file to HDF5"""
        try:
            # Read and validate header
            header = self.read_blk_header(blk_file)
            self.validate_header(header, blk_file)
            
            # Generate output filename if not provided
            if h5_file is None:
                h5_file = Path(blk_file).with_suffix('.h5')
            
            # Check if output exists
            if os.path.exists(h5_file) and not overwrite:
                print(f"SKIPPED: {h5_file} already exists (use --overwrite to replace)")
                return False
            
            # Extract parameters from header
            width = header['framewidth']
            height = header['frameheight']
            nframes = header['actual_nframes']
            header_len = header['lenheader']
            
            # Get numpy dtype
            dtype_info = self.datatype_map.get(header['datatype'])
            if not dtype_info:
                raise ValueError(f"Unsupported data type: {header['datatype']}")
            dtype = dtype_info[0]
            
            frame_size = width * height
            
            # Read binary data
            with open(blk_file, 'rb') as f:
                f.seek(header_len)
                raw_data = np.fromfile(f, dtype=dtype, count=frame_size * nframes)
            
            if raw_data.size != frame_size * nframes:
                raise ValueError(f"Data size mismatch! Expected {frame_size * nframes}, got {raw_data.size}")
            
            # Reshape data
            data = raw_data.reshape((nframes, height, width))  # [frames, H, W]
            
            # Save to HDF5
            with h5py.File(h5_file, 'w') as hf:
                hf.create_dataset("image_stack", data=data, compression="gzip", compression_opts=6)
                
                # Store metadata as attributes
                hf.attrs['frame_width'] = width
                hf.attrs['frame_height'] = height
                hf.attrs['nframes'] = nframes
                hf.attrs['dtype'] = str(dtype)
                hf.attrs['source_file'] = str(blk_file)
                hf.attrs['version_id'] = header['versionid']
                hf.attrs['variant'] = self.variant_map.get(header['filesubtype'], 'Unknown')
                hf.attrs['original_filesize'] = header['filesize']
                hf.attrs['header_length'] = header_len
            
            print(f"✓ SUCCESS: Converted to {h5_file}")
            print(f"  Data shape: {data.shape} (frames, height, width)")
            print(f"  Data type: {dtype}")
            print(f"  Compression: gzip")
            
            return True
            
        except Exception as e:
            print(f"✗ ERROR converting {blk_file}: {str(e)}")
            return False

    def batch_convert(self, input_pattern, output_dir=None, overwrite=False):
        """Batch convert BLK files matching a pattern"""
        # Find all matching files
        if os.path.isfile(input_pattern):
            blk_files = [input_pattern]
        else:
            blk_files = glob.glob(input_pattern)
        
        if not blk_files:
            print(f"No files found matching pattern: {input_pattern}")
            return
        
        print(f"Found {len(blk_files)} BLK files to convert")
        
        # Create output directory if specified
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)
        
        success_count = 0
        failed_files = []
        
        for blk_file in sorted(blk_files):
            try:
                # Determine output file
                if output_dir:
                    h5_file = os.path.join(output_dir, Path(blk_file).stem + '.h5')
                else:
                    h5_file = Path(blk_file).with_suffix('.h5')
                
                success = self.convert_blk_to_hdf5(blk_file, h5_file, overwrite)
                if success:
                    success_count += 1
                else:
                    failed_files.append(blk_file)
                    
            except KeyboardInterrupt:
                print("\nConversion interrupted by user")
                break
            except Exception as e:
                print(f"✗ UNEXPECTED ERROR with {blk_file}: {str(e)}")
                failed_files.append(blk_file)
        
        # Summary
        print(f"\n=== BATCH CONVERSION SUMMARY ===")
        print(f"Total files processed: {len(blk_files)}")
        print(f"Successfully converted: {success_count}")
        print(f"Failed: {len(failed_files)}")
        
        if failed_files:
            print("\nFailed files:")
            for f in failed_files:
                print(f"  - {f}")

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Convert BLK files to HDF5 format")
    parser.add_argument("input", help="Input BLK file(s) - can use wildcards like '*.blk'")
    parser.add_argument("-o", "--output-dir", help="Output directory (default: same as input)")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing output files")
    parser.add_argument("--inspect-only", action="store_true", help="Only inspect headers, don't convert")
    
    args = parser.parse_args()
    
    converter = BLKConverter()
    
    if args.inspect_only:
        # Just inspect files
        blk_files = glob.glob(args.input) if not os.path.isfile(args.input) else [args.input]
        for blk_file in sorted(blk_files):
            try:
                header = converter.read_blk_header(blk_file)
                converter.validate_header(header, blk_file)
            except Exception as e:
                print(f"✗ ERROR inspecting {blk_file}: {str(e)}")
    else:
        # Convert files
        converter.batch_convert(args.input, args.output_dir, args.overwrite)

if __name__ == '__main__':
    main()