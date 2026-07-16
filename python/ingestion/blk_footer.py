import numpy as np
import matplotlib.pyplot as plt

def read_blk_footer(filename, n_footer_samples=486413, dtype=np.uint16, samples_per_trial=750):
    bytes_footer = n_footer_samples * np.dtype(dtype).itemsize

    with open(filename, 'rb') as f:
        f.seek(-bytes_footer, 2)  # Seek from EOF
        raw_footer = f.read(bytes_footer)

    # Convert to array
    data = np.frombuffer(raw_footer, dtype=dtype)

    # Reshape to [samples_per_trial × nTrials]
    n_trials = len(data) // samples_per_trial
    data = data[:n_trials * samples_per_trial]
    reshaped = data.reshape((n_trials, samples_per_trial)).T  # Shape: [750 × N]

    # Plot
    plt.figure(figsize=(10, 4))
    plt.plot(reshaped)
    plt.title('Footer Traces')
    plt.xlabel('Frame'); plt.ylabel('Signal')
    plt.grid(True)
    plt.tight_layout()
    plt.show()

    return reshaped

# Example
signals = read_blk_footer('led_E1B13.blk')
