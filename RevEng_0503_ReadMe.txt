# Documentation: 0503 MEA Data Processing Pipeline

## 1. Overview
This script is a standalone reverse-engineered pipeline designed to process Micro-Electrode Array (MEA) data for **Subject 0503**. It bypasses the original compiled GUI (`SEP_Project`) to provide direct access to raw data, filtering logic, and visualization.

**Key Capabilities:**
* Loads raw `.mat` data.
* Recovers triggers using a subject-specific derivative method.
* Applies identical filtering (Notch + Bandpass) as the original software.
* Epochs data into Event-Related Potentials (ERPs).
* Recreates the 8x8 Dashboard with interactive Normalization and Layout control.

## 2. Requirements
* **MATLAB Version:** R2019b or later (Recommended).
* **Toolboxes:** Signal Processing Toolbox (Required for `filtfilt`, `butter`, `iirnotch`).
* **File Structure:**
    * Script must be in the parent directory.
    * Data must be in: `./data/ID0503/0503_MEA72_01_ref_ground_512Hz.mat`

## 3. Pipeline Logic & Constraints

### A. Trigger Logic (CRITICAL WARNING)
* **Method:** The script does *not* use simple thresholding. It detects triggers by calculating the derivative of Channel 70 and identifying "Odd" integer step sizes (e.g., +1, -1, +3).
* **Hardcoded Fixes:** The original code contained manual patches for missing/false triggers for Subject 0503.
    * *Trial 1:* Forces a trigger event at index **30157**.
    * *Trial 2:* Forces events at **32945** and **39389**.
* **Constraint:** This logic is **specific to Subject 0503**. Do not use this script "as-is" for other subjects (e.g., 0203, 2602) without verifying their specific trigger logic in `triggerConditioning.m`.

### B. Signal Processing
The pipeline applies the following filters in order:
1.  **Artifact Cut:** Removes the first **0.5 seconds** of recording (to remove power-on artifacts).
2.  **Notch Filter:**
    * Base Frequencies: 50Hz and its harmonics (100, 150...).
    * **Sidebands:** Aggressively filters `±12Hz` and `±24Hz` around every harmonic.
    * *Note:* This is an unusually aggressive filter that removes specific environmental noise found in the original lab setup.
3.  **Bandpass Filter:**
    * Range: **4 - 150 Hz**.
    * Type: 3rd Order Butterworth.
    * Implementation: Zero-phase filtering (`filtfilt`).

### C. Channel Mapping
* **Input:** The raw matrix `Y` contains 64 rows of data (indices 2-65).
* **Layout:** The script maps these linear rows to a 9x8 grid (A1 to J8).
* **Geometry:**
    * Rows A and B have gaps (missing corners).
    * Row I is skipped entirely.
    * Row J contains the bottom electrodes.
* **Orientation:** The script assumes "Top-Down" view. Use the `FLIP_L_R` flag in the visualization section if the physical setup requires lateral mirroring.

## 4. Output Variables
When you run the script, the following variables are available in the workspace for integration into other pipelines:

| Variable Name | Dimensions | Description |
| :--- | :--- | :--- |
| **`data`** | `[64 x Time]` | Continuous, filtered data for all 64 channels. Referenced to Ground. |
| **`erp_stack`** | `[64 x Time x Trials]` | The 3D matrix of segmented trials (n=25). Use this for single-trial analysis. |
| **`erpAvg`** | `[64 x Time]` | The Grand Average ERP (mean of `erp_stack`). |
| **`tFinal`** | `[1 x Time]` | Time vector in milliseconds (e.g., -20ms to 160ms). |
| **`onsetIdx`** | `[1 x 25]` | Indices of valid triggers in the continuous `data` stream. |

## 5. Visualization Controls
The final figure ("Reconstructed Dashboard") includes interactive variables you can change within the script:

* **`NORMALIZE_MODE` (Checkbox):**
    * *Unchecked:* Auto-scales every plot to fit its data (good for seeing shape).
    * *Checked:* Locks Y-axis to **-500 µV to +500 µV**. (good for comparing noise levels).
* **`FLIP_L_R` (Boolean):** Set to `true` to mirror the grid left-to-right.
* **`FLIP_U_D` (Boolean):** Set to `true` to mirror the grid up-down.

## 6. Integration Guide (Moving to Bipolar Pipeline)

To use this data in your **Bipolar Montage** pipeline, follow these steps:

1.  **Run the script** to populate the workspace.
2.  **Access the `data` variable.** It is currently **Ground Referenced**.
3.  **Perform Subtraction:** You do *not* need to re-reference before subtraction.
    * *Formula:* `Bipolar_Ch = Channel_A - Channel_B`

### Example Code for Bipolar Conversion:
```matlab
% Example: Create a Bipolar Channel between A1 (Ch1) and A2 (Ch2)
% Note: Ensure you check the 'row_map' to find which index corresponds to which pin.

% 1. Find indices
idx_A1 = 1; % Based on row 2 of Y
idx_A2 = 2; % Based on row 3 of Y

% 2. Calculate Bipolar Derivation (Continuous Data)
bipolar_continuous = data(idx_A1, :) - data(idx_A2, :);

% 3. Calculate Bipolar Derivation (Epochs/Trials)
% Dimensions: (Channel, Time, Trial)
bipolar_epochs = erp_stack(idx_A1, :, :) - erp_stack(idx_A2, :, :);
bipolar_avg = mean(bipolar_epochs, 3, 'omitnan');

% 4. Plot
figure; plot(tFinal, squeeze(bipolar_avg));
title('Bipolar Montage: A1 - A2');