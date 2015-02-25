# dds_controller
Current (as of 2015) code to configure and control the model AD9910 DDS with Altera's Cyclone II FPGA.

The current status on the device's capabilities is that it can write to the three control function registers and eight profile registers at startup, allowing the DDS to be used in single-tone profile mode only. Future updates will add arbitrary modulation of waveforms via the onboard DDS RAM.
