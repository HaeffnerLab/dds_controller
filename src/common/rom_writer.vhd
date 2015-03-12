-- This component is designed to write out the whole contents of a ROM block on
-- the FPGA straight to serial out in sequence.
--
-- There are two ways to operate the rom_writer: normal mode, where each word
-- is written immediately after the last, and "burst", which writes a
-- configurable number of words in sequence, then pauses for a configurable
-- number of clock cycles before starting again.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_arith.all;

library work;
use work.dds_lib.all;

entity rom_writer is
	generic (
		-- Basic configuration

		ROM_DATA_WIDTH:    natural;
		ROM_ADDRESS_WIDTH: natural;
		ROM_DEPTH:         natural;
		ROM_INIT_FILE:     string;
		
		-- Parameters used to configure burst mode

		-- Number of words to write before pause
		-- Burst mode is disabled by setting BURST_COUNT to 0.
		BURST_COUNT:       natural := 0;
		-- Number of cycles to wait between bursts
		BURST_PAUSE:       natural := 0
	);
	port (
		clock:         in std_logic;
		async_clear:   in std_logic;
		dds_sclk:      out std_logic;
		dds_sdo:       out std_logic;
		finish_flag:   out std_logic -- Active high
	);
end rom_writer;

architecture behavior of rom_writer is
	type state_type is (
		ST_STANDBY,
		ST_TRANSFER,
		ST_PAUSE,
		ST_FINISH
	);
	signal state: state_type := ST_STANDBY;

	signal aux_p2s_reset:  std_logic;
	signal aux_p2s_pdi:    std_logic_vector(ROM_DATA_WIDTH - 1 downto 0);
	signal aux_p2s_finish: std_logic;

	signal aux_rom_addr: std_logic_vector(ROM_ADDRESS_WIDTH - 1 downto 0);
	signal aux_rom_q:    std_logic_vector(ROM_DATA_WIDTH - 1 downto 0);
begin
	parallel_to_serial: entity work.p2s_bus
	generic map (
		DATA_WIDTH => ROM_DATA_WIDTH
	)
	port map (
		clock       => clock,
		reset       => aux_p2s_reset,
		pdi         => aux_p2s_pdi,
		sclk        => dds_sclk,
		sdo         => dds_sdo,
		finish_flag => aux_p2s_finish
	);
	
	rom_mf_inst: entity work.rom_mf
	generic map (
		DATA_WIDTH    => ROM_DATA_WIDTH,
		ADDRESS_WIDTH => ROM_ADDRESS_WIDTH,
		DEPTH         => ROM_DEPTH,
		INIT_FILE     => ROM_INIT_FILE
	)
	port map (
		clock   => clock,
		address => aux_rom_addr,
		q       => aux_rom_q
	);
	
	aux_p2s_pdi <= aux_rom_q(ROM_DATA_WIDTH - 1 downto 0);
	
	-- NOTE: This generate statement requires VHDL 2008, which is supposrted
	-- at least in Quartus 13.0sp1 and beyond.
	--
	-- (You can replace this with two generate statements if you have to.)
	burst_pause_check: if BURST_COUNT = 0 generate
	
	-- Normal state control
	state_control:
	process (clock, async_clear)
		-- addr_counter = ROM_DEPTH is just a placeholder value
		variable addr_counter: natural range 0 to ROM_DEPTH := 0;
	begin
		if async_clear = '1' then
			addr_counter := 0;
			state <= ST_STANDBY;
		elsif rising_edge(clock) then
			case state is
			when ST_STANDBY =>
				if async_clear = '1' then
					addr_counter := 0;
					state <= ST_STANDBY;
				else
					addr_counter := 1;
					state <= ST_TRANSFER;
				end if;
			when ST_TRANSFER =>
				if aux_p2s_finish = '1' then
					if addr_counter = ROM_DEPTH then
						state <= ST_FINISH;
					else
						addr_counter := addr_counter + 1;
						state <= ST_TRANSFER;
					end if;
				end if;
			when ST_PAUSE =>
				-- Unused state
				state <= ST_TRANSFER;
			when ST_FINISH =>
				addr_counter := 0;
				if async_clear = '1' then
					state <= ST_STANDBY;
				else
					state <= ST_FINISH;
				end if;
			end case;
		end if;
		aux_rom_addr <=
				std_logic_vector(to_unsigned(addr_counter, ROM_ADDRESS_WIDTH));
	end process;
	
	else generate
	
	-- Burst mode state control
	state_control:
	process (clock, async_clear)
		-- addr_counter = ROM_DEPTH is just a placeholder value
		variable addr_counter: natural range 0 to ROM_DEPTH := 0;
		variable burst_counter: natural range 0 to BURST_COUNT - 1 := 0;
	begin
		if async_clear = '1' then
			addr_counter := 0;
			burst_counter := 0;
			state <= ST_STANDBY;
		elsif rising_edge(clock) then
			case state is
			when ST_STANDBY =>
				burst_counter := 0;
				if async_clear = '1' then
					addr_counter := 0;
					state <= ST_STANDBY;
				else
					addr_counter := 1;
					state <= ST_TRANSFER;
				end if;
			when ST_TRANSFER =>
				if aux_p2s_finish = '1' then
					if addr_counter = ROM_DEPTH then
						state <= ST_FINISH;
					else
						addr_counter := addr_counter + 1;
						if burst_counter = BURST_COUNT - 1 then
							burst_counter := 0;
							state <= ST_PAUSE;
						else
							burst_counter := burst_counter + 1;
							state <= ST_TRANSFER;
						end if;
					end if;
				end if;
			when ST_PAUSE =>
				-- Repurpose burst_count to count pause cycles
				if burst_counter = BURST_PAUSE - 1 then
					burst_counter := 0;
					state <= ST_TRANSFER;
				else
					burst_counter := burst_counter + 1;
					state <= ST_PAUSE;
				end if;
			when ST_FINISH =>
				addr_counter := 0;
				burst_counter := 0;
				if async_clear = '1' then
					state <= ST_STANDBY;
				else
					state <= ST_FINISH;
				end if;
			end case;
		end if;
		aux_rom_addr <=
				std_logic_vector(to_unsigned(addr_counter, ROM_ADDRESS_WIDTH));
	end process;
	
	end generate;

	signal_assignments:
	process (state)
	begin
		case state is
		when ST_STANDBY =>
			aux_p2s_reset <= '1';
			finish_flag   <= '0';
		when ST_TRANSFER =>
			aux_p2s_reset <= '0';
			finish_flag   <= '0';
		when ST_PAUSE =>
			aux_p2s_reset <= '1';
			finish_flag   <= '0';
		when ST_FINISH =>
			aux_p2s_reset <= '1';
			finish_flag   <= '1';
		end case;
	end process;
end behavior;
