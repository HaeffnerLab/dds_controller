-- Top-level controller for the model AD9910 DDS with RAM modulation.
-- Various code improvements wanting to be made:
--- Encapsulate objects with record types (cf. procedure code for why)
--- Use boolean over std_logic for internal signals
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.dds_lib.all;

entity dds_controller is
	port (
		clock:            in std_logic;
		reset:            in std_logic;

		-- Serial clock
		dds_sclk:         out std_logic;
		-- Master DDS reset pin
		dds_reset:        out std_logic;
		-- Serial data out
		-- The AD9910 has two serial pins, but one only ever writes out.
		dds_sdo:          out std_logic;
		-- Reset IO operation
		dds_io_reset:     out std_logic;
		-- Tell the DDS to update values and flush buffers
		dds_io_update:    out std_logic;
		-- Profile select out
		dds_profile_addr: out std_logic_vector
				(DDS_PROFILE_ADDR_WIDTH - 1 downto 0);
		-- Chip select bar
		dds_cs:           out std_logic;
		-- Stuff to do with the digital-analog converter
		dds_dac_wre:      out std_logic;
		dds_dac_control:  out std_logic_vector(DAC_CONTROL_WIDTH - 1 downto 0)
	);
end dds_controller;

architecture behavior of dds_controller is

	-- TODO: put procedures in dds_lib

	-- Reusable procedure to simply write a constant (such as an instruction)
	-- to the DDS over the serial port, then stop.
	procedure write_constant (
			P2S_WIDTH:  in natural;
			DATA_WIDTH: in natural;
			data:       in std_logic_vector;
			signal p2s_reset:  out std_logic;
			signal p2s_len:    out natural;
			signal p2s_pdi:    out std_logic_vector;
			signal p2s_finish: in std_logic;
			variable finish:     out boolean
	) is
	begin
		if p2s_finish = '1' then
			p2s_reset <= '1';
			finish    := true;
		else
			p2s_reset <= '0';
			p2s_len   <= DATA_WIDTH;
			p2s_pdi(P2S_WIDTH - 1 downto P2S_WIDTH - DATA_WIDTH) <= data;
			finish := false;
		end if;
	end procedure;

	-- Reusable procedure to write the entire contents of an Altera ROM
	-- component over the serial port in sequence, then stop.
	procedure write_from_rom (
			P2S_WIDTH:  in natural;
			DATA_WIDTH: in natural;
			ADDR_WIDTH: in natural;
			DATA_DEPTH: in natural;
			signal p2s_reset:  out std_logic;
			signal p2s_len:    out natural;
			signal p2s_pdi:    out std_logic_vector;
			signal p2s_finish: in std_logic;
			signal rom_addr:   out std_logic_vector;
			signal rom_q:      in std_logic_vector;
			variable addr_count: inout natural;
			variable finish:     out boolean
	) is
	begin
		p2s_reset <= '0';
		p2s_len   <= DATA_WIDTH;
		p2s_pdi(P2S_WIDTH - 1 downto P2S_WIDTH - DATA_WIDTH) <= rom_q;
		if addr_count = DATA_DEPTH - 1 then
			-- Can't have an address greater than depth
			rom_addr <= std_logic_vector(to_unsigned(0, ADDR_WIDTH));
			rom_addr   <= (others => '0');
			if p2s_finish = '1' then
				p2s_reset <= '1';
				addr_count := 0;
				finish := true;
			else
				finish := false;
			end if;
		else
			rom_addr <= std_logic_vector(to_unsigned(addr_count + 1,
					ADDR_WIDTH));
			if p2s_finish = '1' then
				addr_count := addr_count + 1;
			end if;
			finish := false;
		end if;
	end procedure;

	type dds_state is (
		-- Do nothing (except write DAC pins)
		ST_STANDBY,
		ST_INIT,
		ST_FINISH
	);
	signal state: dds_state := ST_STANDBY;
	
	constant SERIAL_BUS_WIDTH: natural := 128;
	
	signal aux_p2s_reset:  std_logic := '1';
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
			downto 0) := (others => '0');
	signal aux_rom_profile_q:    std_logic_vector(ROM_PROFILE_WIDTH - 1 
			downto 0); 

	signal aux_rom_ram_addr: std_logic_vector(ROM_RAM_ADDR_WIDTH - 1 downto 0)
			:= (others => '0');
	signal aux_rom_ram_q:    std_logic_vector(ROM_RAM_WIDTH - 1
			downto 0);

	signal aux_rom_control_fn_addr: std_logic_vector(ROM_CONTROL_FN_ADDR_WIDTH
			- 1 downto 0) := (others => '0');
	signal aux_rom_control_fn_q:    std_logic_vector(ROM_CONTROL_FN_WIDTH - 1
			downto 0);
	
	signal io_reset:  std_logic := '1';
	signal io_update: std_logic := '0';
	
	signal serial_write_complete: boolean := false;
begin
	serial_bus: entity work.p2s_bus
	generic map (
		DATA_WIDTH => SERIAL_BUS_WIDTH
	)
	port map (
		clock  => clock,
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
        clock   => clock,
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
        clock   => clock,
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
        address => aux_rom_control_fn_addr,
        clock   => clock,
        q       => aux_rom_control_fn_q
    );

	dds_profile_addr <= b"000";
	
	dds_cs          <= '0';
	dds_dac_control <= DAC_CONTROL_PINS_CONST;
	
	state_control:
	process (clock)
	begin
		if rising_edge(clock) then
			if reset = '1' then
				state <= ST_STANDBY;
			else
				case state is 
				when ST_STANDBY =>
					state <= ST_INIT;
				when ST_INIT =>
					if serial_write_complete = true then
						state <= ST_FINISH;
					else
						state <= ST_INIT;
					end if;
				when ST_FINISH =>
					state <= ST_FINISH;
				end case;
			end if;
		end if;
	end process;

	dds_serial_control:
	process (clock)
		type serial_state_type is (
			ST_WRITE_RAM_PROFILE,
			ST_WRITE_RAM_ADDR,
			ST_WRITE_RAM,
			ST_WRITE_PROFILES,
			ST_WRITE_CONTROL_FNS,
			ST_WRITE_FTW
		);
		variable serial_state: serial_state_type := ST_WRITE_PROFILES;
		variable counter: natural := 0;
		variable finish:  boolean := false;
	begin
		if rising_edge(clock) then
			if state = ST_INIT then
				case serial_state is
				when ST_WRITE_RAM_PROFILE =>
					if finish = true then
						finish := false;
						serial_state := ST_WRITE_RAM_ADDR;
					else
						write_constant (
							SERIAL_BUS_WIDTH,
							ROM_PROFILE_WIDTH,
							DDS_RAM_WRITE_PROFILE,
							aux_p2s_reset,
							aux_p2s_len,
							aux_p2s_pdi,
							aux_p2s_finish,
							finish
						);
						serial_state := ST_WRITE_RAM_PROFILE;
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
					end if;
				when ST_WRITE_RAM =>
					if finish = true then
						finish := false;
						serial_state := ST_WRITE_CONTROL_FNS;
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
					end if;
				when ST_WRITE_PROFILES =>
					if finish = true then
						finish := false;
						serial_state := ST_WRITE_RAM_ADDR;
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
					end if;
				when ST_WRITE_CONTROL_FNS =>
					if finish = true then
						finish := false;
						serial_state := ST_WRITE_FTW;
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
					end if;
				when ST_WRITE_FTW =>
					if finish = true then
						serial_write_complete <= true;
						serial_state := ST_WRITE_FTW;
					else
						write_constant (
							SERIAL_BUS_WIDTH,
							DDS_WORD_WIDTH,
							x"11111113", -- Test data
							aux_p2s_reset,
							aux_p2s_len,
							aux_p2s_pdi,
							aux_p2s_finish,
							finish
						);
						serial_state := ST_WRITE_FTW;
					end if;
				end case;
				if finish = true then
					io_update <= '1';
					io_reset  <= '1';
				else
					io_update <= '0';
					io_reset  <= '0';
				end if;
			elsif state = ST_FINISH then
				finish := false;
				serial_state := ST_WRITE_PROFILES;
				serial_write_complete <= false;
			end if;
		end if;
	end process;
	
	dds_signal_control:
	process (clock)
	begin
		case state is
			when ST_STANDBY =>
				dds_reset     <= '1';
				dds_sdo       <= '0';
				dds_sclk      <= '0';
				dds_io_reset  <= '1';
				dds_io_update <= '0';
				dds_dac_wre   <= '1';
			when ST_INIT =>
				dds_reset     <= '0';
				dds_sdo       <= aux_p2s_sdo;
				dds_sclk      <= aux_p2s_sclk;
				dds_io_reset  <= io_reset;
				dds_io_update <= io_update;
				dds_dac_wre   <= '0';
			when ST_FINISH =>
				dds_reset     <= '0';
				dds_sclk      <= '0';
				dds_sdo       <= '0';
				dds_io_reset  <= '1';
				dds_io_update <= '0';
				dds_dac_wre   <= '0';
		end case;
	end process;
end behavior;
