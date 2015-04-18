-- Constants for the AD9910
library ieee;
use ieee.std_logic_1164.all;

package dds_lib is
	-- Width of a serial instruction to the DDS
	constant DDS_ADDR_WIDTH: natural := 8;
	constant DDS_WORD_WIDTH: natural := 32;
	-- Number of profile select bits
	constant DDS_PROFILE_SEL_WIDTH: natural := 3;
	-- Parallel port width
	constant DDS_PL_PORT_WIDTH: natural := 16;
	-- Parallel port data destination
	constant DDS_PL_ADDR_WIDTH: natural := 2;
	-- Frequency tuning word address
	constant DDS_FTW_ADDR_BYTE: std_logic_vector(DDS_ADDR_WIDTH - 1 downto 0)
			:= x"07";
	-- Address to read/write DDS RAM
	constant DDS_RAM_ADDR_BYTE: std_logic_vector(DDS_ADDR_WIDTH - 1 downto 0)
			:= x"16";
	-- Profile constant to write entire RAM memory block at once
    constant DDS_RAM_INIT_PROFILE: std_logic_vector(2 * DDS_WORD_WIDTH +
            DDS_ADDR_WIDTH - 1 downto 0) :=
            x"0E000000FFC0000000";
end package;
