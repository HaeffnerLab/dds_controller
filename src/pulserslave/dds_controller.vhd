-- Top-level controller for a slave DDS board to the pulser controller
-- An idea: rewrite the Python scripts to generate VHDL libraries with
--  array constants for data
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.dds_lib.all;

entity dds_controller is
	generic (
		BUS_ADDR_WIDTH: natural := 3
	);
	port (
		--- Input from board

		clock:             in std_logic;
		-- A physical dip switch sets the address of each board to identify it
		-- in bus communications.
		chip_addr:         in std_logic_vector(BUS_ADDR_WIDTH - 1 downto 0);

		--- Output to DDS

		-- Serial clock
		dds_sclk:          out std_logic;
		-- Master DDS reset pin
		dds_reset:         out std_logic;
		-- Serial data out. The AD9910 has two serial pins, but only one input.
		dds_sdo:           out std_logic;
		-- Parallel data out
		dds_pdo:           out std_logic_vector
				(DDS_PARALLEL_PORT_WIDTH - 1 downto 0);
		-- Parallel data port destination
		dds_paddr:         out std_logic_vector
				(DDS_PARALLEL_ADDR_WIDTH -1 downto 0);
		-- Transmission enable for parallel port; active high
		dds_tx_en:         out std_logic;
		dds_io_reset:      out std_logic;
		-- Update serial registers
		dds_io_update:     out std_logic;
		-- Profile select out
		dds_profile_sel:   out std_logic_vector(DDS_PROFILE_ADDR_WIDTH - 1
				downto 0);
		-- Chip select bar
		dds_cs:            out std_logic;
		-- DDS digital-analog converter write enable; active high
		dds_dac_wre:       out std_logic;

		--- Input and output to LVDS bus

		bus_data_in:     in std_logic_vector(DDS_PARALLEL_PORT_WIDTH - 1 downto
				0);
		-- Chip select; tells which board is being talked to
		bus_addr:        in std_logic_vector(BUS_ADDR_WIDTH - 1 downto 0);
		bus_ram_reset:   in std_logic;
		-- Go to next set of pulser data
		bus_step:        in std_logic;
		bus_dds_reset:   in std_logic;
		-- Bus data lives in a queue for reading
		-- Empty flag; active high
		bus_fifo_empty:  in std_logic;
		-- Read enable; active high
		bus_fifo_rd_en:  out std_logic;
		bus_fifo_rd_clk: out std_logic;
		-- Transmission enable; set high when this board is selected
		bus_tx_en:       out std_logic_vector(1 downto 0)
	);
end dds_controller;

architecture behavior of dds_controller is

	--- Onboard RAM to hold pulser data

	constant RAM_RD_ADDR_WIDTH: natural := 10;
	constant RAM_WR_ADDR_WIDTH: natural := 12;
	constant RAM_DATA_WIDTH:    natural := 4 * DDS_PARALLEL_PORT_WIDTH;

	-- Signal from bus
	signal aux_ram_reset:   std_logic;
	signal aux_ram_pdi:     std_logic_vector
			(DDS_PARALLEL_PORT_WIDTH - 1 downto 0);
	-- RAM data word layout:
	-- [63..32]: frequency
	-- [31..16[: amplitude
	-- [15..3]: phase
	-- [2..0]:  profile
	signal aux_ram_pdo:     std_logic_vector(RAM_DATA_WIDTH - 1 downto 0);
	signal aux_ram_rd_addr: std_logic_vector(RAM_RD_ADDR_WIDTH - 1 downto 0);
	signal aux_ram_rd_clk:  std_logic;
	signal aux_ram_wr_addr: std_logic_vector(RAM_WR_ADDR_WIDTH - 1 downto 0);
	signal aux_ram_wr_clk:  std_logic;
	signal aux_ram_wr_en:   std_logic;
	
	--- ROM subcomponent signals

	constant ROM_PROFILE_WIDTH:         natural := DDS_PROFILE_WIDTH +
			DDS_ADDR_WIDTH;
	constant ROM_PROFILE_DEPTH:         natural := 8;
	constant ROM_PROFILE_ADDR_WIDTH:    natural := 3;
	constant ROM_RAM_WIDTH:             natural := DDS_WORD_WIDTH;
	constant ROM_RAM_DEPTH:             natural := 1024;
	constant ROM_RAM_ADDR_WIDTH:        natural := 10;
	constant ROM_CONTROL_FN_WIDTH:      natural := DDS_CONTROL_FN_WIDTH +
			DDS_ADDR_WIDTH;
	constant ROM_CONTROL_FN_DEPTH:      natural := 3;
	constant ROM_CONTROL_FN_ADDR_WIDTH: natural := 2;

	signal aux_rom_profile_addr: std_logic_vector(ROM_PROFILE_ADDR_WIDTH - 1
			downto 0) := (others => '0');
	signal aux_rom_profile_q:       std_logic_vector(ROM_PROFILE_WIDTH - 1
			downto 0);

	signal aux_rom_ram_addr: std_logic_vector(ROM_RAM_ADDR_WIDTH - 1 downto 0)
			:= (others => '0');
	signal aux_rom_ram_q:    std_logic_vector(ROM_RAM_WIDTH - 1
			downto 0);

	signal aux_rom_control_fn_addr: std_logic_vector(ROM_CONTROL_FN_ADDR_WIDTH
			- 1 downto 0) := (others => '0');
	signal aux_rom_control_fn_q:    std_logic_vector(ROM_CONTROL_FN_WIDTH - 1
			downto 0);

	--- Parallel to serial bus
	
	-- Wide enough to hold a profile + instruction
	constant P2S_BUS_WIDTH: natural := 2 * DDS_WORD_WIDTH + DDS_ADDR_WIDTH;

	signal aux_p2s_reset:  std_logic;
	signal aux_p2s_length: natural range 0 to 72;
	signal aux_p2s_data:   std_logic_vector(2 * DDS_WORD_WIDTH + DDS_ADDR_WIDTH
			- 1 downto 0) := x"FFFFFFFFFFFFFFFFFF"; -- Debug data
	signal aux_p2s_finish: std_logic;

	-- TODO: make explicit constants for everything
	signal aux_ram_ftw_out:       std_logic_vector(DDS_WORD_WIDTH - 1 downto
			0);
	signal aux_ram_amplitude_out: std_logic_vector(14 - 1 downto 0);
	signal aux_ram_phase_out:     std_logic_vector((16 - 1) - 1 downto 0);
	signal aux_ram_profile_out:   std_logic_vector(DDS_PROFILE_ADDR_WIDTH - 1
			downto 0);

	--- State machine

	type dds_state_type is (
		ST_STANDBY,
		--- DDS init routine
		ST_INIT,
		--- Wait for update signals from bus
		ST_ACTIVE,
		-- Update over serial and parallel
		ST_STEP
	);
	signal dds_state: dds_state_type := ST_STANDBY;

	--- Interprocess communication signals

	-- A write/update state has finished
	signal write_complete:    std_logic := '0';

	-- Output buffer signals
	signal aux_dds_sdo:       std_logic;
	signal aux_dds_sclk:      std_logic;
	signal aux_dds_io_update: std_logic;
	signal aux_dds_io_reset:  std_logic;
	
	signal fifo_rd_en:        std_logic;
	signal fifo_rd_clk:       std_logic;
begin
	--- Subcomponents

	profile_rom: entity work.rom_mf
	generic map (
		DATA_WIDTH    => ROM_PROFILE_WIDTH,
		ADDRESS_WIDTH => ROM_PROFILE_ADDR_WIDTH,
		DEPTH         => ROM_PROFILE_DEPTH,
		INIT_FILE     => "../data/profile_data.mif"
	)
	port map (
		address => aux_rom_profile_addr,
		clock   => clock,
		q       => aux_rom_profile_q
	);

	dds_ram_rom: entity work.rom_mf
	generic map (
		DATA_WIDTH    => ROM_RAM_WIDTH,
		ADDRESS_WIDTH => ROM_RAM_ADDR_WIDTH,
		DEPTH         => ROM_RAM_DEPTH,
		INIT_FILE     => "../data/ram_data.mif"
	)
	port map (
		address => aux_rom_ram_addr,
		clock   => clock,
		q       => aux_rom_ram_q
	);

	control_fn_rom: entity work.rom_mf
	generic map (
		DATA_WIDTH    => ROM_CONTROL_FN_WIDTH,
		ADDRESS_WIDTH => ROM_CONTROL_FN_ADDR_WIDTH,
		DEPTH         => ROM_CONTROL_FN_DEPTH,
		INIT_FILE     => "../data/control_function_data.mif"
	)
	port map (
		address => aux_rom_control_fn_addr,
		clock   => clock,
		q       => aux_rom_control_fn_q
	);

	p2s_writer: entity work.p2s_bus
	generic map (
		DATA_WIDTH => P2S_BUS_WIDTH
	)
	port map (
		clock  => clock,
		reset  => aux_p2s_reset,
		len    => aux_p2s_length,
		pdi    => aux_p2s_data,
		sclk   => aux_dds_sclk,
		sdo    => aux_dds_sdo,
		finish => aux_p2s_finish
	);

--	local_ram: entity work.ram_mf
--	port map (
--		data      => aux_ram_pdi,
--		rdaddress => aux_ram_rd_addr,
--		rdclock   => aux_ram_rd_clk,
--		wraddress => aux_ram_wr_addr,
--		wrclock   => aux_ram_wr_clk,
--		wren      => aux_ram_wr_en,
--		q         => aux_ram_pdo
--	);

	--- Combinatoric signals

	dds_cs <= '0';

	-- It is important that these two be high Z when not communicating
	bus_fifo_rd_en  <= fifo_rd_en when bus_addr = chip_addr else 'Z';
	bus_fifo_rd_clk <= fifo_rd_clk when bus_addr = chip_addr else 'Z';
	bus_tx_en       <= b"11" when bus_addr = chip_addr else b"00";

	aux_ram_ftw_out       <= aux_ram_pdo(64 - 1 downto 32);
	aux_ram_amplitude_out <= aux_ram_pdo(32 - 1 downto 18);
	aux_ram_profile_out   <= aux_ram_pdo(18 - 1 downto 15);
	aux_ram_phase_out     <= aux_ram_pdo(16 - 1 - 1 downto 0);
	
	--- Processes

	-- Generate slower clock
--	process (clock)
--		variable counter: natural range 0 to 19 := 0;
--	begin
--		if rising_edge(clock) then
--			if counter < 10 then
--				clock <= '1';
--				counter := counter + 1;
--			elsif counter < 19 then
--				clock <= '0';
--				counter := counter + 1;
--			else
--				clock <= '0';
--				counter := 0;
--			end if;
--		end if;
--	end process;

	-- Purely control the order in which states are executed
	dds_state_control:
	process (clock)
	begin
		if bus_dds_reset = '1' then
			dds_state <= ST_STANDBY;
		elsif rising_edge(clock) then
			case dds_state is 
			-- Do nothing
			when ST_STANDBY => 
				dds_state <= ST_INIT;
			-- DDS init routine
			when ST_INIT =>
				if write_complete = '1' then
					dds_state <= ST_ACTIVE;
				else
					dds_state <= ST_INIT;
				end if;
			-- Respond to bus input
			when ST_ACTIVE =>
				if bus_step = '1' then
					dds_state <= ST_STEP;
				else
					dds_state <= ST_ACTIVE;
				end if;
			-- Step to next set of pulser data
			when ST_STEP =>
				if write_complete = '1' then
					dds_state <= ST_ACTIVE;
				else
					dds_state <= ST_STEP;
				end if;
			end case;
		end if;
	end process;

	-- Drive the serial bus with data
	-- Sounded like it would be easy to understand, but it needs to be improved.
	dds_serial_bus_control:
	process (clock)
		-- Just used in init state
		type serial_state_type is (
			-- Profile just for writing data
			ST_WRITE_DDS_RAM_PROFILE,
			ST_WRITE_DDS_RAM_ADDR,
			ST_WRITE_DDS_RAM,
			ST_WRITE_PROFILES,
			ST_WRITE_CONTROL_FNS,
			ST_WRITE_COMPLETE
		);
		variable serial_state: serial_state_type :=
				ST_WRITE_DDS_RAM_PROFILE;
		variable addr_counter: natural range 0 to ROM_RAM_DEPTH;
		variable count: natural range 0 to 1 := 0;
	begin
		case dds_state is
		when ST_STANDBY =>
			aux_p2s_reset     <= '1';
			aux_dds_io_reset  <= '1';
			aux_dds_io_update <= '0';
			serial_state   := ST_WRITE_DDS_RAM_PROFILE;
			write_complete <= '0';
			count := 0;
		when ST_INIT =>
			case serial_state is
			when ST_WRITE_DDS_RAM_PROFILE =>
				case count is
				when 0 =>
					aux_p2s_reset     <= '1';
					aux_dds_io_reset  <= '0';
					aux_dds_io_update <= '0';
					-- TODO: seriously need to work out these constants!
					aux_p2s_length <= 72;
					aux_p2s_data(P2S_BUS_WIDTH - 1 downto P2S_BUS_WIDTH - 72)
							<= DDS_RAM_WRITE_PROFILE;
					count := 1;
				when 1 =>
					aux_p2s_reset <= '0';
					
					if aux_p2s_finish = '1' then
						serial_state      := ST_WRITE_DDS_RAM_ADDR;
						aux_dds_io_update <= '1';
						aux_dds_io_reset  <= '1';
						count := 0;
					end if;
				end case;
			when ST_WRITE_DDS_RAM_ADDR =>
				case count is
				when 0 =>
					aux_p2s_reset     <= '1';
					aux_dds_io_reset  <= '0';
					aux_dds_io_update <= '0';
					aux_p2s_length <= DDS_ADDR_WIDTH;
					aux_p2s_data(P2S_BUS_WIDTH - 1 downto P2S_BUS_WIDTH -
							DDS_ADDR_WIDTH) <= DDS_RAM_ADDR_BYTE;
					count := 1;
				when 1 =>
					aux_p2s_reset <= '0';
					
					if aux_p2s_finish = '1' then
						serial_state      := ST_WRITE_DDS_RAM;
						aux_dds_io_update <= '1';
						aux_dds_io_reset  <= '1';
						count := 0;
					end if;
				end case;
			when ST_WRITE_DDS_RAM =>
				case count is
				when 0 =>
					aux_p2s_reset     <= '1';
					aux_dds_io_reset  <= '0';
					aux_dds_io_update <= '0';
					aux_p2s_length <= DDS_WORD_WIDTH;
					aux_p2s_data(P2S_BUS_WIDTH - 1 downto P2S_BUS_WIDTH -
							DDS_WORD_WIDTH) <= aux_rom_ram_q;
					count := 1;
				when 1 =>
					aux_p2s_reset <= '0';
					aux_rom_ram_addr <= std_logic_vector(to_unsigned(addr_counter,
								ROM_RAM_ADDR_WIDTH));
					
					if aux_p2s_finish = '1' then
						if addr_counter = ROM_RAM_DEPTH - 1 then
							addr_counter      := 0;
							serial_state      := ST_WRITE_PROFILES;
							aux_dds_io_update <= '1';
							aux_dds_io_reset  <= '1';
							count := 0;
						else
							addr_counter := addr_counter + 1;
						end if;
					end if;
				end case;
			when ST_WRITE_PROFILES =>
				case count is
				when 0 =>
					aux_p2s_reset     <= '1';
					aux_dds_io_reset  <= '0';
					aux_dds_io_update <= '0';
					aux_p2s_length <= DDS_PROFILE_WIDTH + DDS_ADDR_WIDTH;
					aux_p2s_data(P2S_BUS_WIDTH - 1 downto P2S_BUS_WIDTH - 72)
							<= aux_rom_profile_q;
					count := 1;
				when 1 =>
					aux_p2s_reset <= '0';
					aux_rom_profile_addr <= std_logic_vector(to_unsigned
							(addr_counter, ROM_PROFILE_ADDR_WIDTH));
					
					if aux_p2s_finish = '1' then
						if addr_counter = ROM_PROFILE_DEPTH - 1 then
							addr_counter      := 0;
							serial_state      := ST_WRITE_CONTROL_FNS;
							aux_dds_io_update <= '1';
							aux_dds_io_reset  <= '1';
							count := 0;
						else
							addr_counter := addr_counter + 1;
						end if;
					end if;
				end case;
			when ST_WRITE_CONTROL_FNS =>
				case count is
				when 0 =>
					aux_p2s_reset     <= '1';
					aux_dds_io_reset  <= '0';
					aux_dds_io_update <= '0';
					aux_p2s_length <= DDS_CONTROL_FN_WIDTH;
					aux_p2s_data(P2S_BUS_WIDTH - 1 downto P2S_BUS_WIDTH - 40)
							<= aux_rom_control_fn_q;
					count := 1;
				when 1 =>
					aux_p2s_reset <= '0';
					aux_rom_control_fn_addr <= std_logic_vector(to_unsigned
							(addr_counter, ROM_CONTROL_FN_ADDR_WIDTH));
					
					if aux_p2s_finish = '1' then
						if addr_counter = ROM_CONTROL_FN_DEPTH - 1 then
							addr_counter      := 0;
							serial_state      := ST_WRITE_COMPLETE;
							aux_dds_io_update <= '1';
							aux_dds_io_reset  <= '1';
							count := 0;
						else
							addr_counter := addr_counter + 1;
						end if;
					end if;
				end case;
			when ST_WRITE_COMPLETE =>
				aux_p2s_reset     <= '1';
				aux_dds_io_update <= '0';
				aux_dds_io_reset  <= '1';
				write_complete    <= '1';
			end case;
		when ST_ACTIVE =>
			aux_p2s_reset  <= '1';
			write_complete <= '0';
			count := 0;
		-- Write FTW
		when ST_STEP =>
			aux_p2s_reset  <= '0';
			aux_p2s_length <= DDS_WORD_WIDTH;
			aux_p2s_data(P2S_BUS_WIDTH - 1 downto P2S_BUS_WIDTH -
					DDS_WORD_WIDTH) <= aux_ram_ftw_out;
			if aux_p2s_finish = '1' then
				write_complete <= '1';
			else
				write_complete <= '0';
			end if;
		end case;
	end process;

	-- Write DAC amplitude and phase offset
	-- Actually wanted too have FTW writer use clk_199...
	dds_parallel_control:
	process (clock)
		variable count: natural range 0 to 5 := 0;
	begin
		if dds_state = ST_STEP then
			case count is
			when 0 =>
				dds_tx_en <= '0';
				dds_pdo(15 downto 14) <= b"00";
				dds_pdo(13 downto 0) <= aux_ram_amplitude_out;
				dds_dac_wre <= '0';
				count := count + 1;
			when 1 =>
				dds_dac_wre <= '1';
				count := count + 1;
			when 2 =>
				dds_dac_wre <= '0';
				count := count + 1;
			when 3 =>
				-- 15 downto 3
				dds_pdo   <= aux_ram_phase_out & b"0";
				dds_paddr <= "01"; -- Never changes currently
				count := count + 1;
			when 4 =>
				dds_dac_wre <= '1';
				dds_tx_en   <= '1';
				count := count + 1;
			when 5 =>
				dds_dac_wre <= '0';
				dds_tx_en   <= '0';
			end case;
		else
			count := 0;
			dds_dac_wre <= '0';
			dds_tx_en   <= '0';
		end if;
	end process;

	dds_signal_control:
	process (dds_state)
	begin
		case dds_state is
			when ST_STANDBY =>
				dds_reset       <= '1';
				dds_sclk        <= '0';
				dds_sdo         <= '0';
				dds_io_reset    <= '1';
				dds_io_update   <= '0';
				dds_profile_sel <= b"000";
			when ST_INIT =>
				dds_reset       <= '0';
				dds_sclk        <= aux_dds_sclk;
				dds_sdo         <= aux_dds_sdo;
				dds_io_reset    <= aux_dds_io_reset;
				dds_io_update   <= aux_dds_io_update;
				dds_profile_sel <= b"000";
			when ST_ACTIVE =>
				dds_reset       <= '0';
				dds_sclk        <= '0';
				dds_sdo         <= '0';
				dds_io_reset    <= '1';
				dds_io_update   <= '0';
				dds_profile_sel <= aux_ram_profile_out;
			when ST_STEP =>
				dds_reset       <= '0';
				dds_sclk        <= aux_dds_sclk;
				dds_sdo         <= aux_dds_sdo;
				dds_io_reset    <= aux_dds_io_reset;
				dds_io_update   <= aux_dds_io_update;
				dds_profile_sel <= aux_ram_profile_out;
		end case;
	end process;

	-- Asynchronous with other processes--an issue?
	ram_address_step:
	process (bus_step, bus_ram_reset)
		variable addr_counter: natural;
	begin
		if bus_ram_reset = '1' then
			addr_counter := 0;
		elsif rising_edge(bus_step) then
			addr_counter := addr_counter + 1;
		end if;
		aux_ram_rd_addr <= std_logic_vector(to_unsigned(addr_counter,
				RAM_RD_ADDR_WIDTH));
	end process;

	-- I haven't fully looked at how the RAM code is supposed to work, so this
	-- is just a mirror of what was already there.
	ram_control:
	process (clock)
		variable ram_write_addr: natural := 0;
		variable counter:        natural range 0 to 8 := 0;
	begin
		if bus_ram_reset = '1' then
			ram_write_addr := 0;
		elsif rising_edge(clock) then
			case counter is
			-- Look for data in the FIFO
			when 0 =>
				fifo_rd_clk <= '1';
				fifo_rd_en <= '0';
				aux_ram_wr_en <= '0';
				counter := counter + 1;
			when 1 =>
				fifo_rd_clk <= '1';
				counter := counter + 1;
			when 2 =>
				if bus_addr = chip_addr and bus_fifo_empty = '1' then
					counter := counter + 1;
				else
					counter := 0;
				end if;
			-- FIFO not empty
			when 3 =>
				fifo_rd_en <= '1';
				counter := counter + 1;
			when 4 =>
				fifo_rd_clk <= '1';
				aux_ram_wr_en <= '1';
				aux_ram_wr_clk <= '1';
				counter := counter + 1;
			when 5 =>
				fifo_rd_clk <= '0';
				counter := counter + 1;
			-- Set data to write
			when 6 =>
				aux_ram_wr_addr <= std_logic_vector(to_unsigned(ram_write_addr,
						RAM_WR_ADDR_WIDTH));
				aux_ram_pdi <= bus_data_in;
				counter := counter + 1;
			when 7 =>
				aux_ram_wr_clk <= '0';
				counter := counter + 1;
			when 8 =>
				ram_write_addr := ram_write_addr + 1;
				counter := 2;
			end case;
		end if;
	end process;
end behavior;
