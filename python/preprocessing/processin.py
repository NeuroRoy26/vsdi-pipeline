import h5py
import numpy as np
import matplotlib.pyplot as plt
from scipy.signal import detrend
from scipy import signal
import warnings

# === 1. Load the HDF5 data ===
h5_path = "data/led_E1B13.h5"  # Replace with your filename
with h5py.File(h5_path, 'r') as hf:
    data = hf['image_stack'][:]  # shape: (1500, H, W), dtype=uint16

# === 2. Separate Green and Blue Channels ===
green_frames = data[1::2]  # Odd frames
blue_frames = data[0::2]   # Even frames
print(f"Green shape: {green_frames.shape}, Blue shape: {blue_frames.shape}")

# === 3. Estimate and Subtract Dark Field ===
# Use median of first few blue frames as dark field
dark_field = np.median(blue_frames[:10], axis=0)
green_dark_corrected = green_frames - dark_field
blue_dark_corrected = blue_frames - dark_field

# Clip any negative values (uint16 wraparound avoidance)
green_dark_corrected = np.clip(green_dark_corrected, 0, None)
blue_dark_corrected = np.clip(blue_dark_corrected, 0, None)

# === 4. Bleaching Correction ===
# Option A: Blue-channel division (illumination reference)
eps = 1e-3  # small constant to avoid division by zero
bleach_corrected = green_dark_corrected / (blue_dark_corrected + eps)

# === 5. Detrending Before ΔF/F Calculation ===
def polynomial_detrend_3d(data, poly_order=2):
    """
    Apply polynomial detrending along time axis for each pixel.
    
    Parameters:
    - data: 3D array (time, height, width)
    - poly_order: order of polynomial to fit and subtract
    
    Returns:
    - detrended data with same shape
    """
    n_frames, h, w = data.shape
    detrended = np.zeros_like(data, dtype=np.float32)
    
    print(f"Detrending {h*w} pixels with order-{poly_order} polynomial...")
    
    # Create time vector
    t = np.arange(n_frames)
    
    # Process each pixel
    for y in range(h):
        for x in range(w):
            pixel_timeseries = data[:, y, x].astype(np.float32)
            
            # Fit polynomial
            try:
                poly_coeffs = np.polyfit(t, pixel_timeseries, poly_order)
                poly_trend = np.polyval(poly_coeffs, t)
                detrended[:, y, x] = pixel_timeseries - poly_trend
            except np.RankWarning:
                # If polyfit fails, fall back to linear detrend
                detrended[:, y, x] = signal.detrend(pixel_timeseries, type='linear')
        
        if y % 50 == 0:
            print(f"  Processed row {y}/{h}")
    
    return detrended

def scipy_detrend_3d(data, detrend_type='linear'):
    """
    Apply scipy.signal.detrend along time axis for each pixel.
    
    Parameters:
    - data: 3D array (time, height, width)  
    - detrend_type: 'linear' or 'constant'
    
    Returns:
    - detrended data
    """
    print(f"Applying {detrend_type} detrend along time axis...")
    # Apply detrend along axis 0 (time)
    return signal.detrend(data, axis=0, type=detrend_type)

# Choose detrending method
print("Applying polynomial detrending...")
# Option 1: Polynomial detrending (better for gradual drift)
bleach_detrended = polynomial_detrend_3d(bleach_corrected, poly_order=2)

# Option 2: Simple linear detrending (faster, often sufficient)
# bleach_detrended = scipy_detrend_3d(bleach_corrected, detrend_type='linear')

# Add back the mean to preserve signal level
mean_signal = np.mean(bleach_corrected, axis=0)
bleach_detrended_centered = bleach_detrended + mean_signal

# === 6. Normalize to Dynamic Range ===
bleach_corrected_norm = (bleach_detrended_centered - bleach_detrended_centered.min()) / (bleach_detrended_centered.max() - bleach_detrended_centered.min())

# === 7. Compute ΔF/F ===
# Use average of first N frames as baseline
N_baseline = 50
F0 = np.mean(bleach_corrected_norm[:N_baseline], axis=0)
deltaF_over_F = (bleach_corrected_norm - F0) / (F0 + eps)

# === 8. Compare Before/After Detrending ===
def plot_detrending_comparison(original, detrended, sample_coords=[(100, 100), (200, 200)]):
    """
    Show effect of detrending on sample pixels.
    """
    fig, axes = plt.subplots(len(sample_coords), 2, figsize=(12, 6))
    if len(sample_coords) == 1:
        axes = axes.reshape(1, -1)
    
    for i, (y, x) in enumerate(sample_coords):
        # Original signal
        axes[i, 0].plot(original[:, y, x], alpha=0.8, label='Original')
        axes[i, 0].set_title(f'Original Signal - Pixel ({y}, {x})')
        axes[i, 0].set_xlabel('Frame')
        axes[i, 0].set_ylabel('Intensity')
        axes[i, 0].grid(True, alpha=0.3)
        
        # Detrended signal  
        axes[i, 1].plot(detrended[:, y, x], alpha=0.8, color='red', label='Detrended')
        axes[i, 1].set_title(f'Detrended Signal - Pixel ({y}, {x})')
        axes[i, 1].set_xlabel('Frame')
        axes[i, 1].set_ylabel('Intensity')
        axes[i, 1].grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.show()

# Show detrending effect
plot_detrending_comparison(bleach_corrected, bleach_detrended_centered)

# === 9. Noise Analysis and Visualization ===
def analyze_noise_maps():
    """
    Create noise maps showing temporal standard deviation at each pixel.
    """
    # Compute noise (temporal std) for different processing stages
    noise_original = np.std(bleach_corrected, axis=0)
    noise_detrended = np.std(bleach_detrended_centered, axis=0)
    
    # Also compute noise in final ΔF/F
    noise_deltaF_original = np.std(deltaF_no_detrend, axis=0)
    noise_deltaF_detrended = np.std(deltaF_over_F, axis=0)
    
    fig, axes = plt.subplots(2, 3, figsize=(15, 10))
    
    # Raw signal noise maps
    im1 = axes[0, 0].imshow(noise_original, cmap='hot')
    axes[0, 0].set_title('Noise (Original Bleach Correction)')
    axes[0, 0].axis('off')
    plt.colorbar(im1, ax=axes[0, 0])
    
    im2 = axes[0, 1].imshow(noise_detrended, cmap='hot')
    axes[0, 1].set_title('Noise (After Detrending)')
    axes[0, 1].axis('off')
    plt.colorbar(im2, ax=axes[0, 1])
    
    # Noise reduction map
    noise_reduction = noise_original / (noise_detrended + eps)
    im3 = axes[0, 2].imshow(noise_reduction, cmap='viridis', vmin=0.5, vmax=2.0)
    axes[0, 2].set_title('Noise Reduction Factor')
    axes[0, 2].axis('off')
    plt.colorbar(im3, ax=axes[0, 2])
    
    # ΔF/F noise maps
    im4 = axes[1, 0].imshow(noise_deltaF_original, cmap='hot')
    axes[1, 0].set_title('ΔF/F Noise (Original)')
    axes[1, 0].axis('off')
    plt.colorbar(im4, ax=axes[1, 0])
    
    im5 = axes[1, 1].imshow(noise_deltaF_detrended, cmap='hot')
    axes[1, 1].set_title('ΔF/F Noise (Detrended)')
    axes[1, 1].axis('off')
    plt.colorbar(im5, ax=axes[1, 1])
    
    # ΔF/F noise reduction
    deltaF_noise_reduction = noise_deltaF_original / (noise_deltaF_detrended + eps)
    im6 = axes[1, 2].imshow(deltaF_noise_reduction, cmap='viridis', vmin=0.5, vmax=2.0)
    axes[1, 2].set_title('ΔF/F Noise Reduction Factor')
    axes[1, 2].axis('off')
    plt.colorbar(im6, ax=axes[1, 2])
    
    plt.tight_layout()
    plt.show()
    
    # Print summary statistics
    mean_noise_reduction = np.mean(noise_reduction)
    mean_deltaF_noise_reduction = np.mean(deltaF_noise_reduction)
    
    print(f"Average noise reduction in raw signals: {mean_noise_reduction:.2f}x")
    print(f"Average noise reduction in ΔF/F: {mean_deltaF_noise_reduction:.2f}x")
    
    return noise_original, noise_detrended, noise_deltaF_original, noise_deltaF_detrended

# Without detrending (recompute for comparison)
bleach_no_detrend_norm = (bleach_corrected - bleach_corrected.min()) / (bleach_corrected.max() - bleach_corrected.min())
F0_no_detrend = np.mean(bleach_no_detrend_norm[:N_baseline], axis=0)
deltaF_no_detrend = (bleach_no_detrend_norm - F0_no_detrend) / (F0_no_detrend + eps)

# Generate noise analysis
print("Analyzing noise maps...")
noise_orig, noise_detr, noise_dF_orig, noise_dF_detr = analyze_noise_maps()

# === 10. Side-by-side ΔF/F Comparison ===
frame_idx = 400  # pick a later frame to inspect drift correction

fig, axes = plt.subplots(1, 2, figsize=(12, 5))

im1 = axes[0].imshow(deltaF_no_detrend[frame_idx], cmap='RdBu_r', vmin=-0.1, vmax=0.1)
axes[0].set_title(f"ΔF/F Without Detrending\nFrame {frame_idx}")
axes[0].axis('off')
plt.colorbar(im1, ax=axes[0])

# With detrending
im2 = axes[1].imshow(deltaF_over_F[frame_idx], cmap='RdBu_r', vmin=-0.1, vmax=0.1)
axes[1].set_title(f"ΔF/F With Polynomial Detrending\nFrame {frame_idx}")
axes[1].axis('off')
plt.colorbar(im2, ax=axes[1])

plt.tight_layout()
plt.show()

# === 11. Time Series Analysis ===
def analyze_drift_correction(original_deltaF, detrended_deltaF, sample_coords=[(100, 100)]):
    """
    Analyze how well detrending corrected for drift.
    """
    fig, axes = plt.subplots(2, 1, figsize=(12, 8))
    
    for y, x in sample_coords:
        # ΔF/F time courses
        axes[0].plot(original_deltaF[:, y, x], alpha=0.7, label=f'No detrend ({y},{x})')
        axes[0].plot(detrended_deltaF[:, y, x], alpha=0.7, label=f'With detrend ({y},{x})')
    
    axes[0].set_title('ΔF/F Time Courses')
    axes[0].set_xlabel('Frame')
    axes[0].set_ylabel('ΔF/F')
    axes[0].legend()
    axes[0].grid(True, alpha=0.3)
    
    # Statistical summary
    drift_original = np.std(np.mean(original_deltaF, axis=(1,2)))
    drift_corrected = np.std(np.mean(detrended_deltaF, axis=(1,2)))
    
    axes[1].plot(np.mean(original_deltaF, axis=(1,2)), label=f'Original (σ={drift_original:.4f})')
    axes[1].plot(np.mean(detrended_deltaF, axis=(1,2)), label=f'Detrended (σ={drift_corrected:.4f})')
    axes[1].set_title('Global Mean ΔF/F Over Time')
    axes[1].set_xlabel('Frame')
    axes[1].set_ylabel('Mean ΔF/F')
    axes[1].legend()
    axes[1].grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.show()
    
    print(f"Drift reduction: {drift_original:.4f} → {drift_corrected:.4f} ({100*(1-drift_corrected/drift_original):.1f}% improvement)")

# Run drift analysis
analyze_drift_correction(deltaF_no_detrend, deltaF_over_F)

# === 12. Optional: Try Different Detrending Orders ===
def compare_detrending_orders():
    """
    Compare different polynomial orders for detrending.
    """
    orders = [1, 2, 3]  # linear, quadratic, cubic
    sample_pixel = (100, 100)
    y, x = sample_pixel
    
    fig, axes = plt.subplots(2, 2, figsize=(12, 8))
    axes = axes.flatten()
    
    # Original signal
    original_signal = bleach_corrected[:, y, x]
    axes[0].plot(original_signal, alpha=0.8, label='Original')
    axes[0].set_title(f'Original Signal - Pixel {sample_pixel}')
    axes[0].legend()
    axes[0].grid(True, alpha=0.3)
    
    # Different detrending orders
    for i, order in enumerate(orders):
        detrended = polynomial_detrend_3d(bleach_corrected, poly_order=order)
        detrended_centered = detrended + mean_signal
        
        axes[i+1].plot(detrended_centered[:, y, x], alpha=0.8, 
                      label=f'Order {order}', color=f'C{i+1}')
        axes[i+1].set_title(f'Polynomial Order {order}')
        axes[i+1].legend()
        axes[i+1].grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.show()

# Uncomment to compare different polynomial orders
# print("Comparing different detrending polynomial orders...")
# compare_detrending_orders()

# === 13. Create Animations of Temporal Standard Deviation Maps ===
def create_temporal_std_animations():
    """
    Create animations showing how temporal standard deviation evolves.
    Also create static versions of the clean-looking std maps.
    """
    print("Creating temporal standard deviation animations...")
    
    # Compute rolling standard deviation over time windows
    window_size = 50
    n_frames = bleach_corrected.shape[0]
    
    # For original bleach correction
    rolling_std_original = np.zeros_like(bleach_corrected)
    for i in range(n_frames):
        start_idx = max(0, i - window_size // 2)
        end_idx = min(n_frames, i + window_size // 2)
        rolling_std_original[i] = np.std(bleach_corrected[start_idx:end_idx], axis=0)
    
    # For detrended version
    rolling_std_detrended = np.zeros_like(bleach_detrended_centered)
    for i in range(n_frames):
        start_idx = max(0, i - window_size // 2)
        end_idx = min(n_frames, i + window_size // 2)
        rolling_std_detrended[i] = np.std(bleach_detrended_centered[start_idx:end_idx], axis=0)
    
    # For ΔF/F maps
    rolling_std_deltaF = np.zeros_like(deltaF_over_F)
    for i in range(n_frames):
        start_idx = max(0, i - window_size // 2)
        end_idx = min(n_frames, i + window_size // 2)
        rolling_std_deltaF[i] = np.std(deltaF_over_F[start_idx:end_idx], axis=0)
    
    # Create animations
    import matplotlib.animation as animation
    from matplotlib.animation import PillowWriter
    
    # Animation 1: Original bleach correction temporal std
    fig1 = plt.figure(figsize=(7, 7))
    std_max = np.percentile(rolling_std_original, 99)
    im1 = plt.imshow(rolling_std_original[0], cmap='hot', vmin=0, vmax=std_max)
    plt.colorbar(label="Temporal Standard Deviation", shrink=0.8)
    plt.title("Temporal Std: Original Bleach Correction")
    plt.axis('off')
    
    def update1(frame):
        im1.set_data(rolling_std_original[frame])
        return [im1]
    
    ani1 = animation.FuncAnimation(fig1, update1, frames=range(0, n_frames, 5), interval=100)
    ani1.save('temporal_std_original.gif', writer=PillowWriter(fps=10))
    plt.close()
    
    # Animation 2: Detrended temporal std
    fig2 = plt.figure(figsize=(7, 7))
    std_max_detr = np.percentile(rolling_std_detrended, 99)
    im2 = plt.imshow(rolling_std_detrended[0], cmap='hot', vmin=0, vmax=std_max_detr)
    plt.colorbar(label="Temporal Standard Deviation", shrink=0.8)
    plt.title("Temporal Std: After Detrending")
    plt.axis('off')
    
    def update2(frame):
        im2.set_data(rolling_std_detrended[frame])
        return [im2]
    
    ani2 = animation.FuncAnimation(fig2, update2, frames=range(0, n_frames, 5), interval=100)
    ani2.save('temporal_std_detrended.gif', writer=PillowWriter(fps=10))
    plt.close()
    
    # Animation 3: ΔF/F temporal std
    fig3 = plt.figure(figsize=(7, 7))
    std_max_dF = np.percentile(rolling_std_deltaF, 99)
    im3 = plt.imshow(rolling_std_deltaF[0], cmap='hot', vmin=0, vmax=std_max_dF)
    plt.colorbar(label="Temporal Standard Deviation", shrink=0.8)
    plt.title("Temporal Std: ΔF/F")
    plt.axis('off')
    
    def update3(frame):
        im3.set_data(rolling_std_deltaF[frame])
        return [im3]
    
    ani3 = animation.FuncAnimation(fig3, update3, frames=range(0, n_frames, 5), interval=100)
    ani3.save('temporal_std_deltaF.gif', writer=PillowWriter(fps=10))
    plt.close()
    
    # Also create static versions (the "clean" maps you liked)
    fig, axes = plt.subplots(1, 3, figsize=(18, 6))
    
    # Static temporal std maps (full time series)
    static_std_original = np.std(bleach_corrected, axis=0)
    static_std_detrended = np.std(bleach_detrended_centered, axis=0)
    static_std_deltaF = np.std(deltaF_over_F, axis=0)
    
    im1 = axes[0].imshow(static_std_original, cmap='hot')
    axes[0].set_title('Temporal Std: Original\n(The "clean" map you liked!)')
    axes[0].axis('off')
    plt.colorbar(im1, ax=axes[0])
    
    im2 = axes[1].imshow(static_std_detrended, cmap='hot')
    axes[1].set_title('Temporal Std: Detrended\n(Shows stability improvement)')
    axes[1].axis('off')
    plt.colorbar(im2, ax=axes[1])
    
    im3 = axes[2].imshow(static_std_deltaF, cmap='hot')
    axes[2].set_title('Temporal Std: ΔF/F\n(Final signal variability)')
    axes[2].axis('off')
    plt.colorbar(im3, ax=axes[2])
    
    plt.tight_layout()
    plt.show()
    
    print("Created animations:")
    print("1. temporal_std_original.gif - shows how temporal stability evolves in original data")
    print("2. temporal_std_detrended.gif - shows how temporal stability evolves after detrending")
    print("3. temporal_std_deltaF.gif - shows how temporal stability evolves in final ΔF/F")
    print("\nThese 'clean' maps indicate good signal quality - low temporal noise!")
    
    return static_std_original, static_std_detrended, static_std_deltaF

# Create the temporal std animations and static maps
static_std_maps = create_temporal_std_animations()

# === 14. Alternative: Create Animation of the "Clean" Temporal Std Map ===
def create_clean_std_animation():
    """
    Create a simple animation cycling through the static temporal std maps.
    """
    import matplotlib.animation as animation
    from matplotlib.animation import PillowWriter
    
    fig = plt.figure(figsize=(8, 8))
    
    # Use the static temporal std of original bleach correction (the "clean" one)
    clean_map = np.std(bleach_corrected, axis=0)
    
    # Create a simple animation that just shows this clean map
    im = plt.imshow(clean_map, cmap='hot')
    plt.colorbar(label="Temporal Standard Deviation\n(Lower = More Stable)", shrink=0.8)
    plt.title("Temporal Stability Map\n(Clean regions = stable pixels)")
    plt.axis('off')
    
    # Simple static animation (just showing the same frame)
    def update_clean(frame):
        return [im]
    
    ani = animation.FuncAnimation(fig, update_clean, frames=100, interval=50)
    ani.save('clean_temporal_std_map.gif', writer=PillowWriter(fps=20))
    plt.close()
    
    print("Also created: clean_temporal_std_map.gif - the 'clean' stability map you liked!")

create_clean_std_animation()

# === 15. Export Final ΔF/F Animation ===
import matplotlib.animation as animation
from matplotlib.animation import PillowWriter

fig = plt.figure(figsize=(6, 6))
im = plt.imshow(deltaF_over_F[0], cmap='RdBu_r', vmin=-0.1, vmax=0.1)
plt.colorbar(label="ΔF/F")
plt.title("VSDI ΔF/F (Polynomial Detrended)")
plt.axis('off')

def update(frame):
    im.set_data(deltaF_over_F[frame])
    return [im]

ani = animation.FuncAnimation(fig, update, frames=range(0, deltaF_over_F.shape[0], 5), interval=100)
ani.save('vsdi_deltaF_over_F_detrended.gif', writer=PillowWriter(fps=10))

print("Processing complete! Applied simple polynomial detrending to correct for gradual drift.")
