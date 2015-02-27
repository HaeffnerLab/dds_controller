-- The top-level component for writing profile data to the DDS.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_arith.all;

library work;
use work.dds_lib.all;

entity rom_writer is
	generic (
		ROM_DATA_WIDTH:    natural;
		ROM_ADDRESS_WIDTH: natural;
		ROM_DEPTH:         natural;
		ROM_INIT_FILE:     string
	);
	port (
		clock:         in std_logic;
		async_clear:   in std_logic;
		finish_flag:   out std_logic;
		dds_sclk:      out std_logic;
		dds_sdo:       out std_logic
	);
end rom_writer;

architecture behavior of rom_writer is

	type state_type is (
		ST_STANDBY,
		ST_TRANSFER,
		ST_FINISH
	);
	signal state: state_type := ST_STANDBY;

	signal aux_p2s_reset:  std_logic;
	signal aux_p2s_pdi:    std_logic_vector(ROM_DATA_WIDTH - 1 downto 0);
	signal aux_p2s_active: std_logic;
	signal aux_p2s_finish: std_logic;

	signal aux_rom_addr: std_logic_vector(ROM_ADDRESS_WIDTH - 1 downto 0);
	signal aux_rom_q:    std_logic_vector(ROM_DATA_WIDTH - 1 downto 0);

	component p2s_bus
		generic (
			DATA_WIDTH: natural
		);
		port (
			clock:       in std_logic;
			reset:       in std_logic;
			pdi:         in std_logic_vector(DATA_WIDTH - 1 downto 0);
			sclk:        out std_logic;
			sdo:         out std_logic;
			active_flag: out std_logic;
			finish_flag: out std_logic
		);
	end component;

	component rom_mf
		generic (
			DATA_WIDTH:    natural;
			ADDRESS_WIDTH: natural;
			DEPTH:         natural;
			INIT_FILE:     string
		);
		port (
			clock:   in std_logic;
			address: in std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
			q:       out std_logic_vector(DATA_WIDTH - 1 downto 0)
		);
	end component;
begin
	parallel_to_serial: p2s_bus
	generic map (
		DATA_WIDTH => ROM_DATA_WIDTH
	)
	port map (
		clock       => clock,
		reset       => aux_p2s_reset,
		pdi         => aux_p2s_pdi,
		sclk        => dds_sclk,
		sdo         => dds_sdo,
		active_flag => aux_p2s_active,
		finish_flag => aux_p2s_finish
	);
	
	rom_mf_inst: rom_mf
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
	
	state_control:
	process (clock, async_clear)
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
						addr_counter := 0;
						state <= ST_FINISH;
					else
						addr_counter := addr_counter + 1;
						state <= ST_TRANSFER;
					end if;
				end if;
			when ST_FINISH =>
				if async_clear = '1' then
					state <= ST_STANDBY;
				else
					state <= ST_FINISH;
				end if;
			end case;
		end if;
		aux_rom_addr <= std_logic_vector(to_unsigned(addr_counter, ROM_ADDRESS_WIDTH));
	end process;

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
		when ST_FINISH =>
			aux_p2s_reset <= '1';
			finish_flag   <= '1';
		end case;
	end process;
end behavior;
