# `dds_controller`
Current (as of 2015) code to configure and control the model AD9910 DDS with
Altera's Cyclone II FPGA.

The current status on the device's capabilities is that it can write to the
three control function registers and eight profile registers at startup,
allowing the DDS to be used in single-tone profile mode only. Future updates
will add arbitrary modulation of waveforms via the onboard DDS RAM.

The top level of the directory structure contains some folders which separate
the project into source code, data, scripts, and Quartus project files. The
`data` folder holds memory initialization files for the FPGA ROM and the
`python` folder contains python scripts for, e.g., generating data files. There
are a few different quartus project folders at the top level: `singletone`
configures a board to be used in single tone mode with a set of selectable
frequencies; `rammode` configures a board to modulate the output waveform with
predefined amplitude data; `dev_board` has project files to use with the blue
Cyclone II development board. The `src` folder separates code based on the
Quartus project it belongs to: `common` is used across projects, while code in
other folders correspond to the project the folder is named after.
