# dds\_controller
Current (as of 2015) code to configure and control the AD9910 DDS with Altera's
Cyclone II FPGA.

This code sends commands to the DDS on the slave boards to the pulser, which
drives various lasers and devices around the lab. In short, it takes and stores
pulse sequences from the pulser over a data bus and reacts to commands to
update the DDS for the next pulse.

The top level of the directory structure contains some folders which separate
the project into source code, data, scripts, and Quartus project files. The
`data` folder holds memory initialization files for the FPGA's ROM. The
`python` folder contains python scripts for, e.g., generating data files. There
are a few different quartus project folders at the top level: `singletone`
configures a board to be used in single tone mode with a set of selectable
frequencies; `pulser` is the actual code run on the pulser slave boards;
`devboard` has project files to use with the blue Cyclone II development board.
The `src` folder separates code based on the Quartus project it belongs to:
`common` is used across projects, while code in other folders correspond to the
project the folder is named after.

Be sure to program the device through the SignalTap interface, because that
always seems to work.

When changing the data in the RAM mif files, the altera quartus program will not update 
the design until you delete the `db` and `db_incremental` folders in the `pulser` folder.