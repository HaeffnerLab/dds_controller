-- Top-level controller for the model AD9910 with input from the pulser
-- Various code improvements wanting to be made:
--- Encapsulate objects with record types (cf. procedure code for why)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.dds_lib.all;
use work.pulser_lib.all;

entity dds_controller is
	port (
		-- Board pins
	
		-- Incoming clock @ 25MHz
		clock:            in std_logic;
		-- Physical dip switch which identifies this board to the pulser
		chip_addr:        in std_logic_vector(BUS_ADDR_WIDTH - 1 downto 0);

		--- Pins to DDS

		-- Master DDS reset pin
		dds_reset:        out std_logic;

		-- Serial clock
		dds_sclk:         out std_logic;
		-- Serial data out
		-- The AD9910 has two serial pins, but never reads in
		dds_sdo:          out std_logic;
		-- Reset IO operation
		dds_io_reset:     out std_logic;
		-- Tell the DDS to update values and flush buffers
		dds_io_update:    out std_logic;

		-- Parallel data out
		dds_pdo:          out std_logic_vector(DDS_PL_PORT_WIDTH - 1 downto 0);
		-- Parallel data destination
		dds_pl_dest:      out std_logic_vector(DDS_PL_ADDR_WIDTH - 1 downto 0);
		-- Write data from parallel bus to destination
		dds_pl_tx_en:     out std_logic;
		-- Write DAC voltage level from parallel port
		dds_dac_wre:      out std_logic;

		-- Profile select out
		dds_profile_sel: out std_logic_vector
				(DDS_PROFILE_SEL_WIDTH - 1 downto 0);
		-- Chip select bar
		dds_cs:           out std_logic;

		--- LVDS bus pins, asynchronous
		
		-- Master reset for the board
		bus_dds_reset:   in std_logic;
		bus_data_in:     in std_logic_vector(DDS_PL_PORT_WIDTH - 1 downto
				0);
		-- Chip select; tells which board is being talked to
		bus_addr:        in std_logic_vector(BUS_ADDR_WIDTH - 1 downto 0);
		bus_ram_reset:   in std_logic;
		-- Go to next set of pulser data
		bus_step:        in std_logic;
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

	--- DDS IO state machine

	type dds_state is (
		ST_STANDBY,
		ST_INIT,
		ST_ACTIVE,
		ST_STEP
	);
	signal state: dds_state;
	
	--- Clocks
	
	-- Runs at 100MHz (or 4 times 25MHz onboard clock speed)
	signal clk_100: std_logic;
	-- Divide by 20 of onboard clock
	signal clk_sys: std_logic;
	
	-- DDS serial communication subcomponents
	
	constant SERIAL_BUS_WIDTH: natural := 72;
	
	signal aux_p2s_reset:  std_logic;
	signal aux_p2s_sclk:   std_logic;
	signal aux_p2s_sdo:    std_logic;
	signal aux_p2s_len:    natural range 1 to SERIAL_BUS_WIDTH;
	signal aux_p2s_pdi:    std_logic_vector(SERIAL_BUS_WIDTH - 1 downto 0);
	signal aux_p2s_finish: std_logic;
	
	constant ROM_PROFILE_WIDTH:      natural := 2 * DDS_WORD_WIDTH +
			DDS_ADDR_WIDTH;
	constant ROM_PROFILE_DEPTH:      natural := 8;
	constant ROM_PROFILE_ADDR_WIDTH: natural := 3;

	constant ROM_RAM_WIDTH:      natural := DDS_WORD_WIDTH;
	constant ROM_RAM_DEPTH:      natural := 1024;
	constant ROM_RAM_ADDR_WIDTH: natural := 10;

	constant ROM_CONTROL_FN_WIDTH:      natural := DDS_WORD_WIDTH +
			DDS_ADDR_WIDTH;
	constant ROM_CONTROL_FN_DEPTH:      natural := 3;
	constant ROM_CONTROL_FN_ADDR_WIDTH: natural := 2;

	signal aux_rom_profile_addr: std_logic_vector(ROM_PROFILE_ADDR_WIDTH - 1 
			downto 0);
	signal aux_rom_profile_q:    std_logic_vector(ROM_PROFILE_WIDTH - 1 
			downto 0); 

	signal aux_rom_ram_addr: std_logic_vector(ROM_RAM_ADDR_WIDTH - 1 downto 0);
	signal aux_rom_ram_q:    std_logic_vector(ROM_RAM_WIDTH - 1
			downto 0);

	signal aux_rom_control_fn_addr: std_logic_vector(ROM_CONTROL_FN_ADDR_WIDTH
			- 1 downto 0);
	signal aux_rom_control_fn_q:    std_logic_vector(ROM_CONTROL_FN_WIDTH - 1
			downto 0);

	--- RAM to hold sequences from pulser
	
	constant RAM_WR_WIDTH:      natural := 16;
	constant RAM_WR_ADDR_WIDTH: natural := 11;
	constant RAM_WR_DEPTH:      natural := 2048;
	constant RAM_RD_WIDTH:      natural := 64;
	constant RAM_RD_ADDR_WIDTH: natural := 9;
	constant RAM_RD_DEPTH:      natural := 512;

	signal aux_ram_data:    std_logic_vector(RAM_WR_WIDTH - 1 downto 0);
	signal aux_ram_wr_addr: std_logic_vector(RAM_WR_ADDR_WIDTH - 1 downto 0);
	signal aux_ram_wr_clk:  std_logic;
	signal aux_ram_wr_en:   std_logic;
	signal aux_ram_q:       std_logic_vector(RAM_RD_WIDTH - 1 downto 0);
	signal aux_ram_rd_addr: std_logic_vector(RAM_RD_ADDR_WIDTH - 1 downto 0);

	constant RAM_AMPL_WIDTH:  natural := 13;
	constant RAM_PHASE_WIDTH: natural := 16;

	-- RAM output signals
	-- Each 64 bit block from RAM is organized as follows:
	-- [63..32]: FTW
	-- [31..19]: Amplitude
	-- [18..16]: Profile
	--  [15..0]: Phase
	signal ram_out_ftw:     std_logic_vector(DDS_WORD_WIDTH - 1 downto 0);
	signal ram_out_ampl:    std_logic_vector(RAM_AMPL_WIDTH - 1 downto 0);
	signal ram_out_profile: std_logic_vector(DDS_PROFILE_SEL_WIDTH - 1 downto
			0);
	signal ram_out_phase:   std_logic_vector(RAM_PHASE_WIDTH - 1 downto 0);

	--- Output buffers
	
	signal profile_sel: std_logic_vector(DDS_PROFILE_SEL_WIDTH - 1 downto 0);

	signal io_reset:  std_logic;
	signal io_update: std_logic;
	signal pl_data:   std_logic_vector(DDS_PL_PORT_WIDTH - 1 downto 0);
	signal pl_dest:   std_logic_vector(DDS_PL_ADDR_WIDTH - 1 downto 0);
	signal pl_tx_en:  std_logic;
	signal dac_wre:   std_logic;

	signal fifo_rd_en:  std_logic;
	signal fifo_rd_clk: std_logic;
	
	--- Interprocess communication
	
	signal serial_write_complete: boolean := false;
begin

	--- Combinatorial signals

	dds_cs <= '0';

	-- It is important that these two be high Z when not communicating
	bus_fifo_rd_en  <= fifo_rd_en when bus_addr = chip_addr else 'Z';
	bus_fifo_rd_clk <= fifo_rd_clk when bus_addr = chip_addr else 'Z';
	bus_tx_en       <= b"11" when bus_addr = chip_addr else b"00";

	--- Generate other clocks
	
	pll_clk: entity work.pll_mf
	port map (
		clock,
		clk_100
	);
	
	sys_clk:
	process (clock)
		variable count: natural range 0 to 19 := 0;
	begin
		if rising_edge(clock) then
			if count < 10 then
				count   := count + 1;
				clk_sys <= '0';
			elsif count < 19 then
				count   := count + 1;
				clk_sys <= '1';
			else
				count   := 0;
				clk_sys <= '1';
			end if;
		end if;
	end process;

	--- DDS parallel and serial IO and ROM subcomponents

	serial_bus: entity work.p2s_bus
	generic map (
		DATA_WIDTH => SERIAL_BUS_WIDTH
	)
	port map (
		clock  => clk_100,
		reset  => aux_p2s_reset,
		pdi    => aux_p2s_pdi,
		len    => aux_p2s_len,
		sclk   => aux_p2s_sclk,
		sdo    => aux_p2s_sdo,
		finish => aux_p2s_finish
	);

	profile_rom: entity work.rom_mf
	generic map (
		DATA_WIDTH    => ROM_PROFILE_WIDTH,
		ADDRESS_WIDTH => ROM_PROFILE_ADDR_WIDTH,
		DEPTH         => ROM_PROFILE_DEPTH,
		INIT_FILE     => "../data/profile_data.mif"
	)
	port map (
		clock   => clk_100,
		address => aux_rom_profile_addr,
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
		clock   => clk_100,
		address => aux_rom_ram_addr,
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
		clock   => clk_100,
		address => aux_rom_control_fn_addr,
		q       => aux_rom_control_fn_q
	);
	
	state_control:
	process (clk_100)
		-- Quick fix: step state should only trigger once RAM output updated
		-- Revert to parallel processes like in original code?
		variable ram_out_var: std_logic_vector(RAM_RD_WIDTH - 1 downto 0)
				:= (others => '0');
	begin
		if bus_dds_reset = '1' then
			state <= ST_STANDBY;
		elsif rising_edge(clk_100) then
			case state is
			when ST_STANDBY =>
				ram_out_var := (others => '0');
				state <= ST_INIT;
			when ST_INIT =>
				if serial_write_complete = true then
					state <= ST_ACTIVE;
				else
					state <= ST_INIT;
				end if;
			when ST_ACTIVE =>
				if ram_out_var /= aux_ram_q then
					ram_out_var := aux_ram_q;
					state <= ST_STEP;
				else
					state <= ST_ACTIVE;
				end if;
			when ST_STEP =>
				if serial_write_complete = true then
					state <= ST_ACTIVE;
				else
					state <= ST_STEP;
				end if;
			end case;
			ram_out_ftw     <= ram_out_var(RAM_RD_WIDTH - 1 downto RAM_RD_WIDTH
					- DDS_WORD_WIDTH);
			ram_out_ampl    <= ram_out_var(DDS_WORD_WIDTH - 1 downto
					DDS_WORD_WIDTH - RAM_AMPL_WIDTH);
			ram_out_profile <= ram_out_var(RAM_PHASE_WIDTH + 2 downto
					RAM_PHASE_WIDTH);
			ram_out_phase   <= ram_out_var(RAM_PHASE_WIDTH - 1 downto 0);
		end if;
	end process;

	-- See common/dds_lib for the meaning of all the procedures
	dds_serial_control:
	process (clk_100)
		type serial_state_type is (
			ST_WRITE_INIT_PROFILE,
			ST_WRITE_RAM_ADDR,
			ST_WRITE_RAM,
			ST_WRITE_CONTROL_FNS,
			ST_WRITE_PROFILES
		);
		variable serial_state: serial_state_type := ST_WRITE_INIT_PROFILE;
		variable counter: natural := 0;
		variable finish:  boolean := false;
	begin
		if rising_edge(clk_100) then
			case state is
			when ST_STANDBY =>
				serial_state            := ST_WRITE_INIT_PROFILE;
				serial_write_complete   <= false;
				io_reset                <= '1';
				io_update               <= '0';
				counter                 := 0;
				finish                  := false;
				aux_p2s_reset           <= '1';
				aux_p2s_len             <= SERIAL_BUS_WIDTH;
				aux_p2s_pdi             <= (others => '0');
				aux_rom_ram_addr        <= (others => '0');
				aux_rom_control_fn_addr <= (others => '0');
				aux_rom_profile_addr    <= (others => '0');
			when ST_INIT =>
				case serial_state is
				when ST_WRITE_INIT_PROFILE =>
					if finish = true then
						finish := false;
						serial_state := ST_WRITE_RAM_ADDR;
						io_reset  <= '1';
						io_update <= '1';
					else
						write_constant (
							SERIAL_BUS_WIDTH,
							ROM_PROFILE_WIDTH,
							DDS_RAM_INIT_PROFILE,
							aux_p2s_reset,
							aux_p2s_len,
							aux_p2s_pdi,
							aux_p2s_finish,
							finish
						);
						serial_state := ST_WRITE_INIT_PROFILE;
						io_reset  <= '0';
						io_update <= '0';
					end if;
				when ST_WRITE_RAM_ADDR =>
					if finish = true then
						finish := false;
						serial_state := ST_WRITE_RAM;
					else
						write_constant (
							SERIAL_BUS_WIDTH,
							DDS_ADDR_WIDTH,
							DDS_RAM_ADDR_BYTE,
							aux_p2s_reset,
							aux_p2s_len,
							aux_p2s_pdi,
							aux_p2s_finish,
							finish
						);
						serial_state := ST_WRITE_RAM_ADDR;
						io_update <= '0';
						io_reset  <= '0';
					end if;
				when ST_WRITE_RAM =>
					if finish = true then
						finish := false;
						serial_state := ST_WRITE_CONTROL_FNS;
						io_reset  <= '1';
						io_update <= '1';
					else
						write_from_rom (
							SERIAL_BUS_WIDTH,
							ROM_RAM_WIDTH,
							ROM_RAM_ADDR_WIDTH,
							ROM_RAM_DEPTH,
							aux_p2s_reset,
							aux_p2s_len,
							aux_p2s_pdi,
							aux_p2s_finish,
							aux_rom_ram_addr,
							aux_rom_ram_q,
							counter,
							finish
						);
						serial_state := ST_WRITE_RAM;
						io_reset  <= '0';
						io_update <= '0';
					end if;
				when ST_WRITE_CONTROL_FNS =>
					if finish = true then
						finish := false;
						serial_state := ST_WRITE_PROFILES;
						io_reset  <= '1';
						io_update <= '1';
					else
						write_from_rom (
							SERIAL_BUS_WIDTH,
							ROM_CONTROL_FN_WIDTH,
							ROM_CONTROL_FN_ADDR_WIDTH,
							ROM_CONTROL_FN_DEPTH,
							aux_p2s_reset,
							aux_p2s_len,
							aux_p2s_pdi,
							aux_p2s_finish,
							aux_rom_control_fn_addr,
							aux_rom_control_fn_q,
							counter,
							finish
						);
						serial_state := ST_WRITE_CONTROL_FNS;
						io_reset  <= '0';
						io_update <= '0';
					end if;
				when ST_WRITE_PROFILES =>
					if finish = true then
						serial_write_complete <= true;
						serial_state := ST_WRITE_PROFILES;
						io_reset  <= '1';
						io_update <= '1';
					else
						write_from_rom (
							SERIAL_BUS_WIDTH,
							ROM_PROFILE_WIDTH,
							ROM_PROFILE_ADDR_WIDTH,
							ROM_PROFILE_DEPTH,
							aux_p2s_reset,
							aux_p2s_len,
							aux_p2s_pdi,
							aux_p2s_finish,
							aux_rom_profile_addr,
							aux_rom_profile_q,
							counter,
							finish
						);
						serial_state := ST_WRITE_PROFILES;
						io_reset  <= '0';
						io_update <= '0';
					end if;
				end case;
			when ST_ACTIVE =>
				finish := false;
				serial_state := ST_WRITE_INIT_PROFILE;
				serial_write_complete <= false;
				io_reset  <= '1';
				io_update <= '0';
				counter := 0;
				aux_p2s_reset <= '1';
			when ST_STEP =>
				if finish = true then
					serial_write_complete <= true;
					io_reset  <= '1';
					io_update <= '1';
				else
					write_constant (
						SERIAL_BUS_WIDTH,
						DDS_ADDR_WIDTH + DDS_WORD_WIDTH,
						DDS_FTW_ADDR_BYTE & ram_out_ftw,
						aux_p2s_reset,
						aux_p2s_len,
						aux_p2s_pdi,
						aux_p2s_finish,
						finish
					);
					io_reset  <= '0';
					io_update <= '0';
				end if;
			end case;
		end if;
	end process;

	pl_dest <= "01"; -- Currently never needs to be changed

	dds_parallel_control:
	process (clk_100)
		variable count: natural range 0 to 5 := 0;
	begin
		if state = ST_STEP then
			if rising_edge(clk_100) then
				if count < 3 then
					pl_data(DDS_PL_PORT_WIDTH - 1 downto DDS_PL_PORT_WIDTH -
							RAM_AMPL_WIDTH) <= ram_out_ampl;
					pl_data(DDS_PL_PORT_WIDTH - RAM_AMPL_WIDTH - 1 downto 0) <=
							(others => '0');
				else
					pl_data <= ram_out_phase;
				end if;
				case count is
				when 0 =>
					pl_tx_en <= '0';
					dac_wre  <= '0';
					count    := count + 1;
				when 1 =>
					pl_tx_en <= '0';
					dac_wre <= '1';
					count   := count + 1;
				when 2 =>
					pl_tx_en <= '0';
					dac_wre <= '0';
					count   := count + 1;
				when 3 =>
					pl_tx_en <= '0';
					dac_wre  <= '0';
					count    := count + 1;
				when 4 =>
					pl_tx_en <= '1';
					dac_wre  <= '0';
					count    := count + 1;
				when 5 =>
					pl_tx_en <= '0';
					dac_wre  <= '0';
				end case;
			end if;
		else
			pl_data     <= (others => '0');
			pl_tx_en    <= '0';
			dac_wre     <= '0';
			count       := 0;
		end if;
	end process;
	
	dds_signal_control:
	process (state)
		-- Don't update profile_sel until FTW is written
		variable profile_sel_var: std_logic_vector(DDS_PROFILE_SEL_WIDTH - 1
				downto 0) := (others => '0');
	begin
		case state is
			when ST_STANDBY =>
				dds_reset     <= '1';
				dds_sdo       <= '0';
				dds_sclk      <= '0';
				dds_io_reset  <= '1';
				dds_io_update <= '0';
				dds_profile_sel <= (others => '0');
				dds_pdo         <= (others => '0');
				dds_pl_dest     <= (others => '0');
				dds_pl_tx_en    <= '0';
				dds_dac_wre     <= '0';
			when ST_INIT =>
				dds_reset     <= '0';
				dds_sdo       <= aux_p2s_sdo;
				dds_sclk      <= aux_p2s_sclk;
				dds_io_reset  <= io_reset;
				dds_io_update <= io_update;
				dds_profile_sel <= (others => '0');
				dds_pdo         <= (others => '0');
				dds_pl_dest     <= (others => '0');
				dds_pl_tx_en    <= '0';
				dds_dac_wre     <= '0';
			when ST_ACTIVE =>
				dds_reset     <= '0';
				dds_sclk      <= '0';
				dds_sdo       <= '0';
				dds_io_reset  <= '1';
				dds_io_update <= '0';
				dds_profile_sel <= profile_sel_var;
				dds_pdo         <= (others => '0');
				dds_pl_dest     <= (others => '0');
				dds_pl_tx_en    <= '0';
				dds_dac_wre     <= '0';
			when ST_STEP =>
				if serial_write_complete = true then
					profile_sel_var := ram_out_profile;
				end if;
				dds_reset     <= '0';
				dds_sdo       <= aux_p2s_sdo;
				dds_sclk      <= aux_p2s_sclk;
				dds_io_reset  <= io_reset;
				dds_io_update <= io_update;
				dds_profile_sel <= profile_sel_var;
				dds_pdo         <= pl_data;
				dds_pl_dest     <= pl_dest;
				dds_pl_tx_en    <= pl_tx_en;
				dds_dac_wre     <= dac_wre;
		end case;
	end process;

	-- RAM and bus communication
	-- Would be cool to move to a subcomponent

	pulser_ram: entity work.ram_mf
	generic map (
		WRITE_WIDTH      => RAM_WR_WIDTH,
		WRITE_ADDR_WIDTH => RAM_WR_ADDR_WIDTH,
		WRITE_DEPTH      => RAM_WR_DEPTH,
		READ_WIDTH       => RAM_RD_WIDTH,
		READ_ADDR_WIDTH  => RAM_RD_ADDR_WIDTH,
		READ_DEPTH       => RAM_RD_DEPTH
	)
	port map (
		data      => aux_ram_data,
		wraddress => aux_ram_wr_addr,
		wrclock   => aux_ram_wr_clk,
		wren      => aux_ram_wr_en,
		rdaddress => aux_ram_rd_addr,
		rdclock   => clock,
		q         => aux_ram_q
	);

	ram_address_step:
	process (bus_step, bus_ram_reset)
		variable addr_counter: natural range 0 to RAM_RD_DEPTH - 1 := 0;
	begin
		if bus_dds_reset = '1' or bus_ram_reset = '1' then
			addr_counter := 0;
		elsif rising_edge(bus_step) then
			addr_counter := addr_counter + 1;
		end if;
		aux_ram_rd_addr <= std_logic_vector(to_unsigned(addr_counter,
				RAM_RD_ADDR_WIDTH));
	end process;

	-- Drive RAM read clock to continuously refresh output values; keep
	-- querying the FIFO for data and transfer to onboard RAM until FIFO is
	-- empty
	ram_control:
	process (clk_sys, bus_ram_reset, bus_dds_reset)
		variable ram_write_addr: natural range 0 to RAM_WR_DEPTH - 1 := 0;
		variable counter:        natural range 0 to 8 := 0;
	begin
		if bus_dds_reset = '1' or bus_ram_reset = '1' then
			ram_write_addr := 0;
			counter := 0;
			fifo_rd_clk <= '0';
			fifo_rd_en <= '0';
			aux_ram_wr_addr <= (others => '0');
			aux_ram_wr_clk <= '0';
			aux_ram_wr_en <= '0';
			aux_ram_data <= (others => '0');
		elsif rising_edge(clk_sys) then
			case counter is
			-- Look for data in the FIFO
			when 0 =>
				fifo_rd_clk   <= '1';
				fifo_rd_en    <= '0';
				aux_ram_wr_en <= '0';
				counter       := counter + 1;
			when 1 =>
				fifo_rd_clk <= '0';
				if bus_addr = chip_addr and bus_fifo_empty /= '1' then
					counter := counter + 1;
				else
					counter := 0;
				end if;
			when 2 =>
				fifo_rd_en <= '1';
				counter    := counter + 1;
			when 3 =>
				fifo_rd_clk    <= '1';
				aux_ram_wr_en  <= '1';
				aux_ram_wr_clk <= '1';
				counter        := counter + 1;
			when 4 =>
				fifo_rd_clk <= '0';
				counter     := counter + 1;
			-- Set data to write
			when 5 =>
				aux_ram_wr_addr <= std_logic_vector(to_unsigned
						(ram_write_addr, RAM_WR_ADDR_WIDTH));
				aux_ram_data <= bus_data_in;
				counter      := counter + 1;
			when 6 =>
				aux_ram_wr_clk <= '0';
				counter        := counter + 1;
			when 7 =>
				ram_write_addr := ram_write_addr + 1;
				counter := counter + 1;
			when 8 =>
				counter := 0;
			end case;
		end if;
	end process;
end behavior;
