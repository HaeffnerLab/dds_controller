-- Converts a series of parallel data into a fast and continuous time-serial
-- bit stream
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.dds_lib.all;

entity p2s_bus is
	generic (
		-- Size of data buffer/max input size
		DATA_WIDTH: natural
	);
	port (
		clock:  in std_logic;
		-- Stop writing, active high
		reset:  in std_logic;
		-- Number of bits to write before writing the next word.
		-- Need to evaluate use of natural as a signal type.
		len:    in natural range 0 to DATA_WIDTH;
		-- Parallel data in. The [len] HIGHEST bits are written out, in line with
		-- the logic that data is written from left to right.
		pdi:    in std_logic_vector(DATA_WIDTH - 1 downto 0);
		sclk:   out std_logic;
		-- Serial data out
		sdo:    out std_logic;
		-- Active high
		finish: out std_logic
	);
end p2s_bus;

-- This component uses a shift register to write to serial: on the
-- falling edge of sclk, the highest bit is written and the register
-- is shifter left one bit. sclk runs at half clock speed to meet
-- setup and hold time requirements.
architecture behavior of p2s_bus is
begin
	process (clock)
		-- DST_LEN is DATA_WIDTH - 1 because the first address bit is
		-- immediately written out.
		constant DST_LEN:      natural := DATA_WIDTH - 1;
		-- Sample input data and size
		variable n:            natural range 0 to DATA_WIDTH;
		variable dst:          std_logic_vector(DST_LEN - 1 downto 0);
		-- Internally track the value of sclk
		variable sclk_sync:    std_logic := '0';
		variable bits_written: natural range 0 to DATA_WIDTH - 1 := 0;
	begin
		if reset = '1' then
			bits_written := 0;
			n            := len;
			sclk_sync    := '0';
			sclk         <= '0';
			sdo          <= pdi(DATA_WIDTH - 1);
			dst          := pdi(DATA_WIDTH - 2 downto 0);
			finish       <= '0';
		elsif rising_edge(clock) then
			if sclk_sync = '0' then
				sclk_sync := '1';
				sclk      <= '1';
				finish  <= '0';
			else
				sclk_sync := '0';
				sclk      <= '0';
				if bits_written = n - 1 then
					-- Update data register
					bits_written := 0;
					n   := len;
					sdo <= pdi(DATA_WIDTH - 1);
					dst := pdi(DATA_WIDTH - 2 downto 0);
					finish <= '1';
				else
					-- Write out highest bit
					bits_written := bits_written + 1;
					sdo <= dst(DST_LEN - 1);
					dst := dst(DST_LEN - 2 downto 0) & '0';
					finish <= '0';
				end if;
			end if;
		end if;
	end process;
end behavior;
