# vsdi-processing
Voltage Sensitive Dye Imaging processing

The pipeline contains a converter (from blk to hdf5), parser (reading hdf5), motion compensation (using flow correction) and viewer (different visualizations) scripts. 
Further additions include:
Raw fluorescence calculation script
deltaF/F calculation script
overlaying structural frames on functional script (also used as visualization script)
trial averaging with 100 baseline frames, 5 frames temporal binning, sigma = 1, and median window = 3
currently working on analyzing threshold sensitivity, activation masks, and computing of matrices, later will work on producing maps and graphs
Next step would be try applying PSD, PCA and ICA
