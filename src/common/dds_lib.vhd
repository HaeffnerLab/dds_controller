-- Constants for the AD9910
library ieee;
use ieee.std_logic_1164.all;

-- Not totally obvious which numbers need their own constants
package dds_lib is
	constant DDS_WORD_WIDTH: natural := 32;
	-- Width of instruction/serial register address
	constant DDS_ADDR_WIDTH: natural := 8;
	-- Number of profile select pins
	constant DDS_PROFILE_ADDR_WIDTH: natural := 3;
	constant DDS_PARALLEL_PORT_WIDTH: natural := 16;
	constant DDS_PARALLEL_ADDR_WIDTH: natural := 2;
	constant DDS_PROFILE_WIDTH: natural := 2 * DDS_WORD_WIDTH;
	constant DDS_CONTROL_FN_WIDTH: natural := DDS_WORD_WIDTH;
	constant DDS_FTW_ADDR_BYTE: std_logic_vector(DDS_ADDR_WIDTH - 1 downto 0)
			:= "00000111";
	constant DDS_RAM_ADDR_BYTE: std_logic_vector(DDS_ADDR_WIDTH - 1 downto 0)
			:= "00010110";
	-- Profile constant to write entire RAM memory block at once
	constant DDS_RAM_WRITE_PROFILE: std_logic_vector(2 * DDS_WORD_WIDTH +
			DDS_ADDR_WIDTH - 1 downto 0) :=
			x"0e00007dffc0000004";
	-- Width of DAC amplitude data
	constant DDS_DAC_CONTROL_WIDTH: natural := 16;
end package;
