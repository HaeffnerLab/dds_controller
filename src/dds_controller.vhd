-- Top-level controller for the model AD9910 DDS.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.dds_lib.all;

entity dds_controller is
	port (
		clock:            in std_logic;
		reset:            in std_logic;
		profile_select:   in std_logic_vector
				(DDS_PROFILE_ADDR_WIDTH - 1 downto 0);
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
		dds_cs: out std_logic;
		-- Stuff to do with the digital-analog converter
		dac_wre: out std_logic;
		dac_control: out std_logic_vector(DAC_CONTROL_WIDTH - 1 downto 0)
	);
end dds_controller;

architecture behavior of dds_controller is

	type dds_state is (
		-- Do nothing (except write DAC pins)
		ST_STANDBY,
		ST_WRITE_CONTROL_FNS,
		ST_WRITE_PROFILES,
		-- Set io_update high for a few cycles
		ST_UPDATE,
		ST_FINISH
	);
	signal state: dds_state;
	
	signal aux_profile_sdo:         std_logic;
	signal aux_profile_sclk:        std_logic;
	signal aux_profile_clear:       std_logic;
	signal aux_profile_io_reset:    std_logic;
	signal aux_profile_io_update:   std_logic;
	signal aux_profile_finish_flag: std_logic;
	
	signal aux_control_sdo:         std_logic;
	signal aux_control_sclk:        std_logic;
	signal aux_control_clear:       std_logic;
	signal aux_control_io_reset:    std_logic;
	signal aux_control_io_update:   std_logic;
	signal aux_control_finish_flag: std_logic;

	component rom_writer
		generic (
			ROM_DATA_WIDTH:    natural;
			ROM_ADDRESS_WIDTH: natural;
			ROM_DEPTH:         natural;
			ROM_INIT_FILE:     string
		);
		port (
			clock:       in std_logic;
			async_clear: in std_logic;
			finish_flag: out std_logic;
			dds_sclk:    out std_logic;
			dds_sdo:     out std_logic
		);
	end component;
begin
	control_writer: rom_writer
	generic map (
		ROM_DATA_WIDTH => DDS_WORD_WIDTH + DDS_ADDR_WIDTH,
		ROM_ADDRESS_WIDTH => 2,
		ROM_DEPTH => 3,
		ROM_INIT_FILE => "../data/control_function_data.mif"
	)
	port map (
		clock         => clock,
		async_clear   => aux_control_clear,
		finish_flag   => aux_control_finish_flag,
		dds_sclk      => aux_control_sclk,
		dds_sdo       => aux_control_sdo
	);

	profile_writer: rom_writer
	generic map (
		ROM_DATA_WIDTH => 2 * DDS_WORD_WIDTH + DDS_ADDR_WIDTH,
		ROM_ADDRESS_WIDTH => 3,
		ROM_DEPTH => 8,
		ROM_INIT_FILE => "../data/profile_data.mif"
	)
	port map (
		clock         => clock,
		async_clear   => aux_profile_clear,
		finish_flag   => aux_profile_finish_flag,
		dds_sclk      => aux_profile_sclk,
		dds_sdo       => aux_profile_sdo
	);

	dds_profile_addr <= profile_select;
	
	dds_cs      <= '0';
	dac_control <= DAC_CONTROL_PINS_CONST;
	
	state_control:
	process (clock, reset)
		variable update_counter: natural range 0 to 7;
	begin
		if reset = '1' then
			update_counter := 0;
			state <= ST_STANDBY;
		elsif rising_edge(clock) then
			case state is 
			when ST_STANDBY => 
				if reset = '1' then
					state <= ST_STANDBY;
				else
					state <= ST_WRITE_CONTROL_FNS;
				end if;
			when ST_WRITE_CONTROL_FNS =>
				if aux_control_finish_flag = '1' then
					state <= ST_WRITE_PROFILES;
				else
					state <= ST_WRITE_CONTROL_FNS;
				end if;
			when ST_WRITE_PROFILES => 
				if aux_profile_finish_flag = '1' then
					state <= ST_UPDATE;
				else
					state <= ST_WRITE_PROFILES;
				end if;
			when ST_UPDATE =>
				if update_counter = 7 then
					update_counter := 0;
					state <= ST_FINISH;
				else
					update_counter := update_counter + 1;
					state <= ST_UPDATE;
				end if;
			when ST_FINISH =>
				state <= ST_FINISH;
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
				dds_sdo       <= aux_control_sdo;
				dds_sclk      <= aux_control_sclk;
				dds_io_reset  <= '0';
				dds_io_update <= '0';
			when ST_WRITE_PROFILES =>
				dds_reset     <= '0';
				dds_sdo       <= aux_profile_sdo;
				dds_sclk      <= aux_profile_sclk;
				dds_io_reset  <= '0';
				dds_io_update <= '0';
			when ST_UPDATE =>
				dds_reset     <= '0';
				dds_sdo       <= '0';
				dds_io_reset  <= '0';
				dds_io_update <= '1';
				dds_sclk      <= '0';
			when ST_FINISH =>
				dds_reset     <= '0';
				dds_sdo       <= '0';
				dds_io_reset  <= '1';
				dds_io_update <= '0';
				dds_sclk      <= '0';
		end case;
	end process;
	
	aux_signal_control:
	process (state)
	begin
		case state is
			when ST_STANDBY =>
				dac_wre           <= '1';
				aux_control_clear <= '1';
				aux_profile_clear <= '1';
			when ST_WRITE_CONTROL_FNS =>
				dac_wre           <= '0';
				aux_control_clear <= '0';
				aux_profile_clear <= '1';
			when ST_WRITE_PROFILES =>
				dac_wre           <= '0';
				aux_control_clear <= '0';
				aux_profile_clear <= '0';
			when ST_UPDATE =>
				dac_wre           <= '0';
				aux_control_clear <= '0';
				aux_profile_clear <= '0';
			when ST_FINISH =>
				dac_wre           <= '0';
				aux_control_clear <= '0';
				aux_profile_clear <= '0';
		end case;
	end process;
end behavior;
