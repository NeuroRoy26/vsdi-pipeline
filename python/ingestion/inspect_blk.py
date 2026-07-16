import struct
import sys

def inspect_blk_file(filename):
    def read(fid, fmt):
        size = struct.calcsize(fmt)
        data = fid.read(size)
        return struct.unpack(fmt, data)[0]

    with open(filename, 'rb') as fid:
        print(f"Inspecting file: {filename}\n")
        
        header = {}
        header['filesize'] = read(fid, 'q')  # 8 bytes long
        header['checksum_header'] = read(fid, 'h')
        header['checksum_data'] = read(fid, 'h')
        header['lenheader'] = read(fid, 'i')
        header['versionid'] = read(fid, 'f')
        header['filetype'] = read(fid, 'i')
        header['filesubtype'] = read(fid, 'i')
        header['datatype'] = read(fid, 'i')
        header['sizeof'] = read(fid, 'i')
        header['framewidth'] = read(fid, 'i')
        header['frameheidth'] = read(fid, 'i')
        header['nframesperstim'] = read(fid, 'i')

        fid.seek(0)
        header_bytes = fid.read(header['lenheader'])
        header['headersize'] = len(header_bytes)

        variant_map = {
            11: 'FROM_VDAQ',
            12: 'FROM_ORA',
            13: 'FROM_DYEDAQ'
        }
        datatype_map = {
            11: 'DAT_UCHAR (8-bit unsigned)',
            12: 'DAT_USHORT (16-bit unsigned)',
            13: 'DAT_LONG (32-bit signed)',
            14: 'DAT_FLOAT (32-bit float)'
        }

        print(" BLK HEADER INFO")
        print(f" - File size:       {header['filesize']} bytes")
        print(f" - Header length:   {header['lenheader']} bytes")
        print(f" - Version ID:      {header['versionid']}")
        print(f" - Variant:         {variant_map.get(header['filesubtype'], 'Unknown')} ({header['filesubtype']})")
        print(f" - Data type:       {datatype_map.get(header['datatype'], 'Unknown')} ({header['datatype']})")
        print(f" - Data element size: {header['sizeof']} bytes")
        print(f" - Frame size:      {header['framewidth']} x {header['frameheidth']}")
        print(f" - Frames per stim: {header['nframesperstim']}")
        print(f" - Header bytes read: {header['headersize']}")

        # Rough check: number of pixels * bytes should match file size
        num_pixels = header['framewidth'] * header['frameheidth'] * header['nframesperstim']
        expected_data_bytes = num_pixels * header['sizeof']
        total_expected = expected_data_bytes + header['lenheader']

        print("\n DATA CONSISTENCY CHECK")
        print(f" - Expected total size: {total_expected} bytes")
        if total_expected != header['filesize']:
            print(" WARNING: File size does not match expected from header.")
        else:
            print(" File size matches expected layout.")

        return header


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python inspect_blk.py <filename.blk>")
    else:
        inspect_blk_file(sys.argv[1])

def inspect_blk_layout(filename):
    with open(filename, 'rb') as f:
        f.seek(0, 2)
        total_size = f.tell()
        f.seek(0)

        def read(fmt): return struct.unpack(fmt, f.read(struct.calcsize(fmt)))[0]

        filesize = read('q')
        _ = read('h')  # checksum_header
        _ = read('h')  # checksum_data
        header_len = read('i')
        _ = read('f')  # version
        _ = read('i')  # filetype
        _ = read('i')  # filesubtype
        datatype = read('i')
        sizeof = read('i')
        width = read('i')
        height = read('i')
        _ = read('i')  # unreliable nframes

        data_start = header_len
        pixel_size = width * height * sizeof
        nframes_real = (total_size - header_len) // pixel_size

        data_bytes = nframes_real * pixel_size
        footer_start = header_len + data_bytes
        footer_bytes = total_size - footer_start

        print(f" FILE SIZE: {total_size} bytes")
        print(f" HEADER: {header_len} bytes")
        print(f" IMAGE DATA: {nframes_real} frames ({data_bytes} bytes)")
        print(f" FOOTER: {footer_bytes} bytes starting at offset {footer_start}")

        if footer_bytes > 0:
            print(" Footer detected. Contains potential ephys or metadata.")
        else:
            print(" No footer detected. Clean image block.")

inspect_blk_layout('led_E1B13.blk')
