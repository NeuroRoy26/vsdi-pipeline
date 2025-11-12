import h5py
import numpy as np
import matplotlib.pyplot as plt

# 1. Load the HDF5 data
h5_path = "converted__500/led_E1B13.h5"         # replace with your filename
with h5py.File(h5_path, 'r') as hf:
    data = hf['image_stack'][:]  # shape: (nframes, H, W)

# 2. Display a few raw frames
n_show = 10                       # how many frames to peek at
plt.figure(figsize=(12, 3))
for i in range(n_show):
    ax = plt.subplot(1, n_show, i+1)
    img = data[i]               # frame i
    ax.imshow(img, cmap='gray')
    ax.set_title(f"Frame {i}")
    ax.axis('off')
plt.suptitle("Raw VSD Frames (uint16)")
plt.tight_layout()
plt.show()

# # 3. (Optional) Simple animation in an IPython notebook
# import matplotlib.pyplot as plt
# import matplotlib.animation as animation
# from IPython.display import HTML

# # 1. Prepare figure
# fig = plt.figure(figsize=(5,5))
# im = plt.imshow(data[0], cmap='gray', vmin=data.min(), vmax=data.max())
# plt.axis('off')

# # 2. Update function
# def update(frame):
#     im.set_data(data[frame])
#     return [im]

# # 3. Create animation
# ani = animation.FuncAnimation(
#     fig, update,
#     frames=range(data.shape[0]), # currently, all frames
#     interval=40
# )

# # 4. Save as GIF using PillowWriter
# from matplotlib.animation import PillowWriter
# writer = PillowWriter(fps=25)   # match interval (1000 ms/40 ms ≈ 25 fps)

# ani.save('vsd1_movie.gif', writer=writer)
