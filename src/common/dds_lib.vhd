-- Constants for the AD9910
library ieee;
use ieee.std_logic_1164.all;

package dds_lib is
	-- Width of data used to address data onboard the DDS
	constant DDS_ADDR_WIDTH: natural := 8;
	-- WIdth of a word as used by the DDS
	constant DDS_WORD_WIDTH: natural := 32;
	-- Number of profile pins
	constant DDS_PROFILE_ADDR_WIDTH: natural := 3;
	-- Frequency tuning word address
	constant DDS_FTW_ADDR_BYTE: std_logic_vector(DDS_ADDR_WIDTH - 1 downto 0)
			:= "00000111";
	-- Address to read/write DDS RAM
	constant DDS_RAM_ADDR_BYTE: std_logic_vector(DDS_ADDR_WIDTH - 1 downto 0)
			:= "00010110";
	-- Profile constant to write entire RAM memory block at once
    constant DDS_RAM_WRITE_PROFILE: std_logic_vector(2 * DDS_WORD_WIDTH +
            DDS_ADDR_WIDTH - 1 downto 0) :=
            x"0e00007dffc0000004";
	-- Width of DAC control register
	constant DAC_CONTROL_WIDTH: natural := 16;
	constant DAC_CONTROL_PINS_CONST: std_logic_vector
			(DAC_CONTROL_WIDTH - 1 downto 0) := x"FFFF";
end package;
