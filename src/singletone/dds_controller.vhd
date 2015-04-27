-- Top level controller to use the AD9910 as a fixed-frequency generator
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.dds_lib.all;

entity dds_controller is
	port (
		clock:          in std_logic;
		reset:          in std_logic;
		profile_sel:    in std_logic_vector
				(DDS_PROFILE_SEL_WIDTH - 1 downto 0);

		
		dds_reset:      out std_logic;
		-- Serial clock
		dds_sclk:       out std_logic;
		-- Serial data out
		-- The AD9910 has two serial pins, but one only ever writes out.
		dds_sdo:         out std_logic;
		-- Reset IO operation
		dds_io_reset:    out std_logic;
		-- Tell the DDS to update values and flush buffers
		dds_io_update:   out std_logic;
		-- Profile select out
		dds_profile_sel: out std_logic_vector
				(DDS_PROFILE_SEL_WIDTH - 1 downto 0);
		-- Chip select bar
		dds_cs:          out std_logic;
		-- Stuff to do with the digital-analog converter
		dac_wre:         out std_logic;
		dac_control:     out std_logic_vector(DDS_PL_PORT_WIDTH - 1 downto 0)
	);
end dds_controller;

architecture behavior of dds_controller is
	type dds_state is (
		-- Do nothing (except write DAC pins)
		ST_STANDBY,
		ST_WRITE_CONTROL_FNS,
		ST_WRITE_PROFILES,
		ST_FINISH
	);
	signal state: dds_state;

	constant ROM_PROFILE_WIDTH:      natural := 2 * DDS_WORD_WIDTH +
            DDS_ADDR_WIDTH;
    constant ROM_PROFILE_DEPTH:      natural := 8;
    constant ROM_PROFILE_ADDR_WIDTH: natural := 3;

    constant ROM_CONTROL_FN_WIDTH:      natural := DDS_WORD_WIDTH +
            DDS_ADDR_WIDTH;
    constant ROM_CONTROL_FN_DEPTH:      natural := 3;
    constant ROM_CONTROL_FN_ADDR_WIDTH: natural := 2;

    signal aux_rom_profile_addr: std_logic_vector(ROM_PROFILE_ADDR_WIDTH - 1 
            downto 0); 
    signal aux_rom_profile_q:    std_logic_vector(ROM_PROFILE_WIDTH - 1 
            downto 0); 

    signal aux_rom_control_fn_addr: std_logic_vector(ROM_CONTROL_FN_ADDR_WIDTH
            - 1 downto 0);
    signal aux_rom_control_fn_q:    std_logic_vector(ROM_CONTROL_FN_WIDTH - 1
            downto 0);

	constant SERIAL_BUS_WIDTH: natural := ROM_PROFILE_WIDTH;

	signal aux_p2s_reset:  std_logic;
    signal aux_p2s_sclk:   std_logic;
    signal aux_p2s_sdo:    std_logic;
    signal aux_p2s_len:    natural range 1 to SERIAL_BUS_WIDTH;
    signal aux_p2s_pdi:    std_logic_vector(SERIAL_BUS_WIDTH - 1 downto 0); 
    signal aux_p2s_finish: std_logic;

	-- Output buffers

	signal io_reset:  std_logic;
	signal io_update: std_logic;
begin
	serial_bus: entity work.p2s_bus
    generic map (
        DATA_WIDTH => ROM_PROFILE_WIDTH
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

	dds_profile_sel <= profile_sel;
	
	dds_cs      <= '0';
	dac_control <= (others => '1');
	
	state_control:
	process (clock, reset)
		variable counter: natural := 0;
		variable finish:  boolean := false;
	begin
		if reset = '1' then
			state <= ST_STANDBY;
		elsif rising_edge(clock) then
			case state is 
			when ST_STANDBY => 
				state     <= ST_WRITE_CONTROL_FNS;
				io_reset  <= '1';
				io_update <= '0';
				counter   := 0;
				finish    := false;
				
				aux_p2s_reset           <= '1';
				aux_p2s_len             <= DDS_WORD_WIDTH;
				aux_p2s_pdi             <= (others => '0');
				aux_rom_control_fn_addr <= (others => '0');
				aux_rom_profile_addr    <= (others => '0');
			when ST_WRITE_CONTROL_FNS =>
				if finish = true then
					finish    := false;
					state     <= ST_WRITE_PROFILES;
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
					state <= ST_WRITE_CONTROL_FNS;
					io_reset  <= '0';
					io_update <= '0';
				end if;
			when ST_WRITE_PROFILES =>
				if finish = true then
					state     <= ST_FINISH;
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
					state <= ST_WRITE_PROFILES;
					io_reset  <= '0';
					io_update <= '0';
				end if;
			when ST_FINISH =>
				state         <= ST_FINISH;
				io_reset      <= '1';
				io_update     <= '0';
				counter       := 0;
				aux_p2s_reset <= '1';
			end case;
		end if;
	end process;
	
	dds_signal_control:
	process (state)
	begin
		case state is
			when ST_STANDBY =>
				dds_reset     <= '1';
				dds_sdo       <= '0';
				dds_io_reset  <= '1';
				dds_io_update <= '0';
				dds_sclk      <= '0';
			when ST_WRITE_CONTROL_FNS =>
				dds_reset     <= '0';
				dds_sdo       <= aux_p2s_sdo;
				dds_sclk      <= aux_p2s_sclk;
				dds_io_reset  <= io_reset;
				dds_io_update <= io_update;
			when ST_WRITE_PROFILES =>
				dds_reset     <= '0';
				dds_sdo       <= aux_p2s_sdo;
				dds_sclk      <= aux_p2s_sclk;
				dds_io_reset  <= io_reset;
				dds_io_update <= io_update;
			when ST_FINISH =>
				dds_reset     <= '0';
				dds_sdo       <= '0';
				dds_io_reset  <= '1';
				dds_io_update <= '0';
				dds_sclk      <= '0';
		end case;
	end process;
end behavior;
