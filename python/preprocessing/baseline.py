import h5py
import numpy as np

with h5py.File('led_E1B13.h5','r') as f:
    data = f['image_stack'][:]    # (1500,H,W)

# per‑frame dynamic range
ranges = data.max(axis=(1,2)) - data.min(axis=(1,2))

# even vs. odd indices
idx0 = np.arange(0, len(ranges), 2)
idx1 = np.arange(1, len(ranges), 2)

mean0, mean1 = ranges[idx0].mean(), ranges[idx1].mean()

if mean0 > mean1:
    active_indices, baseline_indices = idx0, idx1
else:
    active_indices, baseline_indices = idx1, idx0

print(f'Active channel mean range ≈ {ranges[active_indices].mean():.0f}')
print(f'Baseline channel mean range ≈ {ranges[baseline_indices].mean():.0f}')

# now split
active_stack   = data[active_indices]
baseline_stack = data[baseline_indices]

# baseline_stack is your low‑contrast frames (shape: 750,H,W)
baseline_img = baseline_stack.mean(axis=0)

# active_stack is your high‑contrast frames (750,H,W)
dff = (active_stack - baseline_img[None]) / baseline_img[None]
import matplotlib.pyplot as plt

# choose sensible vmin/vmax based on your biology; e.g. ±5%
vmin, vmax = -0.05, 0.05

fig, ax = plt.subplots()
im = ax.imshow(dff[0], vmin=vmin, vmax=vmax, cmap='hot')
plt.colorbar(im, ax=ax, label='ΔF/F')
ax.set_title('Active frame 0')
ax.axis('off')
plt.show()
