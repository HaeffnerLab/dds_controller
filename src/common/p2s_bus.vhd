-- Converts a series of parallel data into a fast and continuous time-serial
-- bit stream
library ieee;
use ieee.std_logic_1164.all;

library work;
use work.dds_lib.all;

entity p2s_bus is
	generic (
		-- Maximum writable data size
		DATA_WIDTH: natural
	);
	port (
		clock:  in std_logic;
		reset:  in std_logic;
		pdi:    in std_logic_vector(DATA_WIDTH - 1 downto 0);
		-- Settable number of bits to write
		len:    in natural range 0 to DATA_WIDTH;
		sclk:   out std_logic;
		sdo:    out std_logic;
		finish: out std_logic
	);
end p2s_bus;

architecture behavior of p2s_bus is
	-- Quick fix: delay one clock cycle
	signal read_wait: std_logic := '1';
begin
	process (clock)
		-- Data shift register
		-- DST_LEN is DATA_WIDTH - 1 because the first address bit is
		-- immediately written out.
		constant DST_LEN: natural := DATA_WIDTH - 1;
		variable dst:     std_logic_vector(DST_LEN - 1 downto 0)
				:= (others => '0');
		-- Sampled length input
		variable n:       natural range 0 to DATA_WIDTH := 0;
		-- Internally track the value of sclk
		variable sclk_sync:    std_logic := '0';
		variable bits_written: natural range 0 to DATA_WIDTH - 1 := 0;
	begin
		if rising_edge(clock) then
			if reset = '1' then
				sclk      <= '0';
				finish    <= '0';
				read_wait <= '1';
			elsif read_wait = '1' then
				n            := len;
				dst          := pdi(DATA_WIDTH - 2 downto 0);
				sdo          <= pdi(DATA_WIDTH - 1);
				sclk_sync    := '0';
				sclk         <= '0';
				finish       <= '0';
				bits_written := 0;
				read_wait    <= '0';
			else
				if sclk_sync = '0' then
					sclk_sync    := '1';
					sclk         <= '1';
					if bits_written = n - 1 then
						finish <= '1';
					else
						finish <= '0';
					end if;
				else
					sclk_sync := '0';
					sclk      <= '0';
					finish    <= '0';
					if bits_written = n - 1 then
						-- Update data register. Careful about the order.
						n            := len;
						sdo          <= pdi(DATA_WIDTH - 1);
						dst          := pdi(DATA_WIDTH - 2 downto 0);
						bits_written := 0;
					else
						-- Write out highest bit
						sdo          <= dst(DST_LEN - 1);
						dst          := dst(DST_LEN - 2 downto 0) & '0';
						bits_written := bits_written + 1;
					end if;
				end if;
			end if;
		end if;
	end process;
end behavior;
