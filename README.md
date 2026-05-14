Signal Processing Pipeline for Multimodal VSDI and MEA Fusion

Overview
This repository contains an end-to-end computational pipeline engineered to extract, stabilize, decompose, and map high-resolution spatiotemporal cortical dynamics from in vivo Voltage-Sensitive Dye Imaging (VSDI) and simultaneous Multielectrode Array (MEA) recordings.
Because raw VSD optical data is heavily contaminated by cardiovascular pulsatility, respiration artifacts, and photobleaching drift, this pipeline employs a series of principled, physics-driven algorithms to isolate the incredibly faint (sub-1%) fractional changes in fluorescence (ΔF/F0). It culminates in a multimodal fusion framework that bridges the macroscopic subthreshold dendritic inputs (VSD) with the localized, deep-layer spiking outputs (MEA).
Key Methodological Advancements:
Cross-Channel Optical Flow Motion Compensation: Exploits time-multiplexed dual-wavelength illumination by calculating non-parametric deformation fields exclusively on the high-contrast structural (green) channel, and applying backwards-warping to the functional (red) channel to stabilize tissue at sub-pixel accuracy without degrading the delicate neural signal.
Non-Negative Matrix Factorization (NMF): Replaces traditional Independent Component Analysis (ICA) to eliminate "polarity ambiguity." By enforcing strictly non-negative constraints that mirror the physical reality of photon emission, NMF reliably reconstructs positive neural depolarizations without subjective post-hoc sign inversions.
Optical Dipole Synthesis & CSD Fusion: Synchronizes the VSD wave with MEA data by converting 2D MEA voltages into Current Source Density (CSD) maps via a discrete Laplacian estimator, and extracting a baseline-corrected "optical dipole" from the VSD data (subtracting a reference ROI from an active ROI) to match the AC-coupled nature of extracellular recordings.

--------------------------------------------------------------------------------
Repository Structure
The codebase is divided into Python scripts (for data ingestion, parsing, and video rendering) and MATLAB scripts (for core signal processing, matrix decomposition, and interactive GUIs).
1. Python Utilities (Data Ingestion & Video)
optimized_blk_converter.py / blk_batch_converter.py: Memory-optimized scripts to batch-convert proprietary .blk binary files to HDF5 (.h5) format with optimal chunking and compression.
blk_log_parser.py: Parses .txt acquisition logs into structured JSON metadata (extracting trial numbers, FPS, stimuli).
batch_demux_1000.py: Demultiplexes 1000Hz interleaved frames into separate structural (even) and functional (odd) video streams based on contrast detection.
video_stitcher.py / raw_vs_motion_visualization.py: Uses OpenCV to stitch animations and generate side-by-side comparison videos of raw vs. motion-corrected data.
2. MATLAB Pipeline (Core Processing)
Phase A: Pre-processing & Motion Compensation
vsd_motion_correct.m / vsd_batch_runner.m: The core motion compensation wrapper. It automatically assigns structural/functional frames based on pair-wise contrast, maps reference frames, and executes the variational optical flow registration.
parallax_reduction.m: Applies a Laplacian pyramid-based residual motion correction to mitigate depth-dependent parallax artifacts.
Phase B: Signal Extraction & Trial Averaging
run_single_trials.m / run_trial_averaging.m: Loads motion-compensated HDF5 files, computes the baseline resting light intensity (F0), calculates the fractional change (ΔF/F0 ), and applies temporal binning and Gaussian/Median spatial filtering.
analysis_Step1_Concatenate.m: Concatenates multiple trial sweeps into a single unified temporal timeline. Incorporates a tangent-based "Smart Trigger Detection" algorithm (identifying max derivative slopes) to find precise stimulus onset times.
Phase C: Component Separation (SVD-NMF)
PCA_ICA_decomp.m: (Legacy/Comparison) Standard SVD/PCA dimensionality reduction followed by spatial FastICA. Demonstrates the polarity ambiguity limitations.
nmf_decomp.m: (Recommended) Executes Non-Negative Matrix Factorization (NMF) via Alternating Least Squares (ALS) on spatially binned data to extract purely positive, physiologically accurate components.
post_reconstruction_v4.m: Reconstructs the isolated components into a cleaned VSD movie, generating dynamic spatiotemporal threshold masks based on a configurable noise floor and saturation percentile.
Phase D: MEA Analysis & Multimodal Fusion
MEA_Interactive_GUI.m: An interactive tool allowing the user to stereotactically align the 8x9 FlexMEA72 grid onto the optical field of view using the structural blood vessel map.
VSD_MEA.m: The master multimodal fusion script. It processes the raw MEA data (trigger recovery, bandpass 4-150Hz), calculates the 2D Laplacian CSD, synthesizes the VSD "optical dipole", aligns both timelines, and outputs overlaid filmstrips and animations.
Phase E: Diagnostics & Visualization
observe_bleaching.m: Fits exponential and linear models to the global mean to quantify photobleaching and illumination drift.
analyze_threshold_sensitivity.m: Evaluates different pixel-wise standard deviation multipliers to robustly define activated pixels.
vsd_overlay.m / vsd_fluorescence.m: Advanced visualization tools to generate videos of the ΔF/F0 wave superimposed over the semitransparent structural anatomy.

--------------------------------------------------------------------------------
Installation & Requirements
Python Environment
Python 3.8+
numpy, h5py, opencv-python (cv2), matplotlib, tqdm, psutil
pip install numpy h5py opencv-python matplotlib tqdm psutil
MATLAB Environment
MATLAB R2021a or newer.
Signal Processing Toolbox, Image Processing Toolbox, Computer Vision Toolbox.
External Dependency: The optical flow motion compensation relies on an external flow_registration toolbox. This path must be provided to vsd_motion_correct.m.

--------------------------------------------------------------------------------
Pipeline Execution Guide
Step 1: Data Conversion Convert your raw .blk files to .h5.
python optimized_blk_converter.py "data/raw/*.BLK" -o data/converted/
Step 2: Motion Compensation (MATLAB) Run vsd_batch_runner.m to select your converted .h5 files. This script calls vsd_motion_correct.m to separate the structural and functional interleaves, calculate optical flow fields, and output stabilized _vsd_corrected.h5 files.
Step 3: Trial Averaging & ΔF/F0
  Run run_trial_averaging.m to select multiple corrected sweeps. It calculates the resting baseline (F0), extracts the fractional signal (ΔF/F0), and averages the sweeps to enhance the Signal-to-Noise Ratio (SNR).
Step 4: Smart Trigger & Concatenation Run analysis_Step1_Concatenate.m to stitch multiple trials together and automatically detect the biological stimulus triggers via tangent projection.
Step 5: NMF Decomposition Run nmf_decomp.m. The script will apply SVD dimensionality reduction followed by NMF. Use the generated interactive dashboard to select the true biological wave components (ignoring heartbeat/striping artifacts). Choose to save the reconstructed combined movie.
Step 6: MEA Coregistration & Fusion
Run MEA_Interactive_GUI.m and load your structural frame. Interactively scale, rotate, and align the 64-channel array onto the cortical surface. Export the coordinates.
Run VSD_MEA.m. This end-to-end script ingests the MEA data, applies the 2D Laplacian CSD, synthesizes the VSD optical dipole by subtracting a reference ROI, and generates the final multimodal overlay animations showing the extracellular current sinks physically aligned with the optical wave.

--------------------------------------------------------------------------------
Notes & Best Practices
Polarity Inversions: If you opt to use ICA (PCA_ICA_decomp.m) instead of NMF, you must run post_reconstruction.m to check global correlation and manually flip the polarity (sign_ass = -1) of inverted components, as ICA is mathematically sign-blind.
Dark Noise Limitations: The fractional fluorescence is faint. Ensure your VSD baseline calculation (p.BaselineIdx) occurs precisely during a pre-stimulus resting state window.
Hardware Triggers: If hardware triggers possess "sawtooth" artifacts, the pipeline utilizes a discrete derivative step (in VSD_MEA.m) to safely reconstruct the pulse trains.