import numpy as np
import h5py

def convert_blk_to_hdf5(blk_file, h5_file, width=540, height=516, nframes=1500, header_len=1716):
    dtype = np.uint16
    frame_size = width * height

    with open(blk_file, 'rb') as f:
        f.seek(header_len)
        raw_data = np.fromfile(f, dtype=dtype, count=frame_size * nframes)

    if raw_data.size != frame_size * nframes:
        raise ValueError("Data size mismatch! Check frame count or header length.")

    data = raw_data.reshape((nframes, height, width))  # [frames, H, W]

    # Save to HDF5
    with h5py.File(h5_file, 'w') as hf:
        hf.create_dataset("image_stack", data=data, compression="gzip")
        hf.attrs['frame_width'] = width
        hf.attrs['frame_height'] = height
        hf.attrs['nframes'] = nframes
        hf.attrs['dtype'] = str(dtype)
        hf.attrs['source'] = blk_file

    print(f" Converted and saved: {h5_file}")
    print(f" Data shape: {data.shape} — (frames, height, width)")

    return data

# Run conversion
data = convert_blk_to_hdf5("led_E0B13.blk", "led_E0B13.h5")
