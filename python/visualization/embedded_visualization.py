import h5py 
import numpy as np 
import matplotlib.pyplot as plt 
from matplotlib.animation import FuncAnimation, PillowWriter
from scipy.signal import detrend 
from scipy import signal 
import warnings 


h5_path = "converted__500/led_E0B0.h5"  
with h5py.File(h5_path, 'r') as hf:
    data = hf['image_stack'][:]  # shape: (1500, H, W), dtype=uint16

frame_means = [np.mean(f) for f in data[:]]

plt.figure(figsize=(10, 4))
plt.plot(frame_means, marker='o')
plt.title('Mean Intensity per Frame')
plt.xlabel('Frame Index')
plt.ylabel('Mean Intensity')
plt.grid(True, alpha=0.3)
plt.show()

print("All frame means:")
for i in range(1500):
    print(f"Frame {i}: mean = {np.mean(data[i]):.2f}")

## shows sharp step down in mean intensity at frame 750 =====

first_idxs  = list(range(0, 750))       
middle_idxs = list(range(750, 1500))    

all_idxs = first_idxs + middle_idxs

fig, axes = plt.subplots(2, 10, figsize=(20, 4))
for i, frame_idx in enumerate(all_idxs):
    row = i // 10
    col = i % 10
    ax = axes[row, col]
    ax.imshow(data[frame_idx], cmap="gray")
    ax.set_title(f"Frame {frame_idx}")
    ax.axis("off")

plt.tight_layout()
plt.show()   

class FrameAnimationViewer:
    def __init__(self, data, first_frames, middle_frames, original_fps=500):
        self.data = data
        self.first_frames = first_frames
        self.middle_frames = middle_frames
        self.original_fps = original_fps
        
    def create_animation(self, playback_fps=30, figsize=(14, 8), show_stats=True, save_gif=False, gif_name="frame_comparison.gif"):
        """
        Create animated comparison of frame sets
        
        Parameters:
        - playback_fps: Display FPS (default 30)
        - figsize: Figure size tuple
        - show_stats: Whether to show frame statistics
        - save_gif: Whether to save as GIF file
        - gif_name: Name for saved GIF
        """
        
        # Calculate interval for matplotlib animation (in milliseconds)
        interval = 1000 / playback_fps
        
        # Create figure with subplots
        if show_stats:
            fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=figsize)
            ax3.set_title("Intensity Statistics")
            ax4.set_title("Frame Info")
        else:
            fig, (ax1, ax2) = plt.subplots(1, 2, figsize=figsize)
        
        # Set up image displays
        ax1.set_title(f"Early Frames ({self.first_frames[0]}-{self.first_frames[-1]})")
        ax1.axis("off")
        ax2.set_title(f"Later Frames ({self.middle_frames[0]}-{self.middle_frames[-1]})")
        ax2.axis("off")
        
        # Initialize images with proper color scaling
        vmin_early = np.min(self.data[self.first_frames])
        vmax_early = np.max(self.data[self.first_frames])
        vmin_later = np.min(self.data[self.middle_frames])
        vmax_later = np.max(self.data[self.middle_frames])
        
        im1 = ax1.imshow(self.data[self.first_frames[0]], cmap="gray", 
                        vmin=vmin_early, vmax=vmax_early)
        im2 = ax2.imshow(self.data[self.middle_frames[0]], cmap="gray", 
                        vmin=vmin_later, vmax=vmax_later)
        
        # Add colorbars
        plt.colorbar(im1, ax=ax1, shrink=0.8)
        plt.colorbar(im2, ax=ax2, shrink=0.8)
        
        if show_stats:
            # Prepare statistics
            early_means = [np.mean(self.data[idx]) for idx in self.first_frames]
            later_means = [np.mean(self.data[idx]) for idx in self.middle_frames]
            
            # Plot intensity over frame sequence
            ax3.plot(range(len(self.first_frames)), early_means, 'b-o', 
                    label='Early frames', markersize=4)
            ax3.plot(range(len(self.middle_frames)), later_means, 'r-o', 
                    label='Later frames', markersize=4)
            ax3.set_xlabel('Sequence Position')
            ax3.set_ylabel('Mean Intensity')
            ax3.legend()
            ax3.grid(True, alpha=0.3)
            
            # Current frame indicator
            early_marker, = ax3.plot(0, early_means[0], 'bo', markersize=8, 
                                   markeredgecolor='blue', markerfacecolor='lightblue')
            later_marker, = ax3.plot(0, later_means[0], 'ro', markersize=8, 
                                   markeredgecolor='red', markerfacecolor='lightcoral')
            
            # Info text
            ax4.axis('off')
            info_text = ax4.text(0.1, 0.8, '', transform=ax4.transAxes, 
                               fontsize=10, verticalalignment='top', fontfamily='monospace')
        
        def update(frame_idx):
            # Update images
            im1.set_data(self.data[self.first_frames[frame_idx]])
            im2.set_data(self.data[self.middle_frames[frame_idx]])
            
            if show_stats:
                # Update markers
                early_marker.set_data([frame_idx], [early_means[frame_idx]])
                later_marker.set_data([frame_idx], [later_means[frame_idx]])
                
                # Update info text
                early_frame_num = self.first_frames[frame_idx]
                later_frame_num = self.middle_frames[frame_idx]
                early_mean = early_means[frame_idx]
                later_mean = later_means[frame_idx]
                
                # Calculate time in original recording
                early_time = early_frame_num / self.original_fps * 1000  # ms
                later_time = later_frame_num / self.original_fps * 1000  # ms
                
                info_str = f"""Animation Frame: {frame_idx + 1}/{len(self.first_frames)}

Early Frame Info:
  Frame #: {early_frame_num}
  Time: {early_time:.2f} ms
  Mean: {early_mean:.1f}
  
Later Frame Info:
  Frame #: {later_frame_num}  
  Time: {later_time:.2f} ms
  Mean: {later_mean:.1f}
  
Intensity Ratio: {later_mean/early_mean:.3f}
Playback: {playback_fps:.1f} fps
Original: {self.original_fps:.1f} fps"""
                
                info_text.set_text(info_str)
        
        # Create animation
        ani = FuncAnimation(fig, update, frames=len(self.first_frames), 
                          interval=interval, blit=False, repeat=True)
        
        plt.tight_layout()
        
        # Save as GIF if requested
        if save_gif:
            print(f"Saving animation as {gif_name}...")
            writer = PillowWriter(fps=min(playback_fps, 30))  # GIFs work best at ≤30fps
            ani.save(gif_name, writer=writer)
            print(f"Saved: {gif_name}")
        
        return fig, ani
    
    def show_static_comparison(self, figsize=(16, 10)):
        """Show static side-by-side comparison of all frames"""
        
        fig, axes = plt.subplots(3, 10, figsize=figsize)
        
        # Top row: Early frames
        for i, frame_idx in enumerate(self.first_frames):
            ax = axes[0, i]
            ax.imshow(self.data[frame_idx], cmap="gray")
            ax.set_title(f"Frame {frame_idx}", fontsize=8)
            ax.axis("off")
        
        # Middle row: Later frames  
        for i, frame_idx in enumerate(self.middle_frames):
            ax = axes[1, i]
            ax.imshow(self.data[frame_idx], cmap="gray")
            ax.set_title(f"Frame {frame_idx}", fontsize=8)
            ax.axis("off")
            
        # Bottom row: Difference (later - early, normalized)
        for i in range(len(self.first_frames)):
            ax = axes[2, i]
            early_frame = self.data[self.first_frames[i]].astype(float)
            later_frame = self.data[self.middle_frames[i]].astype(float) 
            
            # Normalize to same scale before difference
            early_norm = (early_frame - early_frame.min()) / (early_frame.max() - early_frame.min())
            later_norm = (later_frame - later_frame.min()) / (later_frame.max() - later_frame.min())
            diff = later_norm - early_norm
            
            im = ax.imshow(diff, cmap="RdBu_r", vmin=-1, vmax=1)
            ax.set_title(f"Diff {i+1}", fontsize=8)
            ax.axis("off")
        
        # Add row labels
        fig.text(0.02, 0.75, 'Early Frames\n(1-10)', rotation=90, 
                fontsize=12, ha='center', va='center')
        fig.text(0.02, 0.5, 'Later Frames\n(751-760)', rotation=90, 
                fontsize=12, ha='center', va='center')  
        fig.text(0.02, 0.25, 'Normalized\nDifference', rotation=90, 
                fontsize=12, ha='center', va='center')
        
        plt.tight_layout()
        plt.subplots_adjust(left=0.05)
        return fig
    
    def print_intensity_stats(self):
        """Print detailed intensity statistics"""
        early_means = [np.mean(self.data[idx]) for idx in self.first_frames]
        later_means = [np.mean(self.data[idx]) for idx in self.middle_frames]
        
        print("INTENSITY ANALYSIS")
        print("=" * 50)
        print(f"Early frames ({self.first_frames[0]}-{self.first_frames[-1]}):")
        print(f"  Mean intensity: {np.mean(early_means):.1f} ± {np.std(early_means):.1f}")
        print(f"  Range: {min(early_means):.1f} - {max(early_means):.1f}")
        
        print(f"\nLater frames ({self.middle_frames[0]}-{self.middle_frames[-1]}):")
        print(f"  Mean intensity: {np.mean(later_means):.1f} ± {np.std(later_means):.1f}")
        print(f"  Range: {min(later_means):.1f} - {max(later_means):.1f}")
        
        ratio = np.mean(later_means) / np.mean(early_means)
        print(f"\nIntensity drop ratio: {ratio:.3f} ({(1-ratio)*100:.1f}% decrease)")
        print(f"Step occurs at frame 750 (~{750/self.original_fps*1000:.1f} ms)")

# Create viewer instance
viewer = FrameAnimationViewer(data, first_idxs, middle_idxs, original_fps=500)

# Show intensity statistics
viewer.print_intensity_stats()

#static_fig = viewer.show_static_comparison()
#plt.show()
print("Close the animation window to continue to the next one.")

# Method 1: Show live animation (will open matplotlib window)
print("\n1. From 500.67 fps to 50 fps")
fig1, ani1 = viewer.create_animation(playback_fps=50, show_stats=True)
plt.show()

# Method 2: Save as GIF and show simple version
#print("\n2. Saving GIF and showing simple version...")
#fig2, ani2 = viewer.create_animation(playback_fps=15, show_stats=False, 
#                                   save_gif=True, gif_name="frame_comparison_15fps.gif")
#plt.show()

#Method 3: High-speed version
print("\n3. High-speed version (500 fps)")
fig3, ani3 = viewer.create_animation(playback_fps=500, show_stats=True)
plt.show()