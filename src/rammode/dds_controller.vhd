-- Top-level controller for the model AD9910 DDS with RAM modulation.
-- Recommend moving common controller code to a separate entity.
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
		dac_wre:          out std_logic;
		dac_control:      out std_logic_vector(DAC_CONTROL_WIDTH - 1 downto 0)
	);
end dds_controller;

architecture behavior of dds_controller is

	type dds_state is (
		-- Do nothing (except write DAC pins)
		ST_STANDBY,
		ST_WRITE_PROFILES,
		ST_WRITE_RAM_ADDR,
		ST_WRITE_RAM,
		ST_WRITE_CONTROL_FNS,
		ST_WRITE_FTW,
		-- Set io_update high for a few cycles
		ST_UPDATE,
		ST_FINISH
	);
	signal state: dds_state;
	
	signal aux_profile_sdo:         std_logic;
	signal aux_profile_sclk:        std_logic;
	signal aux_profile_clear:       std_logic;
	signal aux_profile_finish_flag: std_logic;
	
	signal aux_control_sdo:         std_logic;
	signal aux_control_sclk:        std_logic;
	signal aux_control_clear:       std_logic;
	signal aux_control_finish_flag: std_logic;

	signal aux_ram_addr_sdo:         std_logic;
	signal aux_ram_addr_sclk:        std_logic;
	signal aux_ram_addr_reset:       std_logic;
	signal aux_ram_addr_finish_flag: std_logic;

	signal aux_ram_sdo:         std_logic;
	signal aux_ram_sclk:        std_logic;
	signal aux_ram_clear:       std_logic;
	signal aux_ram_finish_flag: std_logic;

	signal aux_ftw_sdo:         std_logic;
	signal aux_ftw_sclk:        std_logic;
	signal aux_ftw_reset:       std_logic;
	signal aux_ftw_finish_flag: std_logic;
begin
	profile_writer: entity work.rom_writer
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

	-- TODO: replace with "instruction_writer" and "ST_WRITE_INSTRUCTION"
	ram_addr_witer: entity work.p2s_bus
	generic map (
		DATA_WIDTH => DDS_ADDR_WIDTH
	)
	port map (
		clock       => clock,
		reset       => aux_ram_addr_reset,
		pdi         => DDS_RAM_ADDR_BYTE,
		sclk        => aux_ram_addr_sclk,
		sdo         => aux_ram_addr_sdo,
		finish_flag => aux_ram_addr_finish_flag
	);

	ram_writer: entity work.rom_writer
	generic map (
		ROM_DATA_WIDTH    => DDS_WORD_WIDTH,
		ROM_ADDRESS_WIDTH => 10,
		ROM_DEPTH         => 1024,
		ROM_INIT_FILE     => "../data/ram_data.mif",
		BURST_COUNT       => 40,
		BURST_PAUSE       => 1
	)
	port map (
		clock         => clock,
		async_clear   => aux_ram_clear,
		finish_flag   => aux_ram_finish_flag,
		dds_sclk      => aux_ram_sclk,
		dds_sdo       => aux_ram_sdo
	);

	control_writer: entity work.rom_writer
	generic map (
		ROM_DATA_WIDTH    => DDS_WORD_WIDTH + DDS_ADDR_WIDTH,
		ROM_ADDRESS_WIDTH => 2,
		ROM_DEPTH         => 3,
		ROM_INIT_FILE     => "../data/control_function_data.mif"
	)
	port map (
		clock         => clock,
		async_clear   => aux_control_clear,
		finish_flag   => aux_control_finish_flag,
		dds_sclk      => aux_control_sclk,
		dds_sdo       => aux_control_sdo
	);

	ftw_writer: entity work.p2s_bus
	generic map (
		DATA_WIDTH => DDS_WORD_WIDTH + DDS_ADDR_WIDTH
	)
	port map (
		clock       => clock,
		reset       => aux_ftw_reset,
		pdi         => DDS_FTW_ADDR_BYTE & x"01101000", -- Test data
		sclk        => aux_ftw_sclk,
		sdo         => aux_ftw_sdo,
		finish_flag => aux_ftw_finish_flag
	);

	dds_profile_addr <= b"000";
	
	dds_cs      <= '0';
	dac_control <= DAC_CONTROL_PINS_CONST;
	
	state_control:
	process (clock, reset)
	begin
		if reset = '1' then
			state <= ST_STANDBY;
		elsif rising_edge(clock) then
			case state is 
			when ST_STANDBY => 
				if reset = '1' then
					state <= ST_STANDBY;
				else
					state <= ST_WRITE_PROFILES;
				end if;
			when ST_WRITE_PROFILES => 
				if aux_profile_finish_flag = '1' then
					state <= ST_WRITE_RAM_ADDR;
				else
					state <= ST_WRITE_PROFILES;
				end if;
			when ST_WRITE_RAM_ADDR =>
				if aux_ram_addr_finish_flag = '1' then
					state <= ST_WRITE_RAM;
				else
					state <= ST_WRITE_RAM_ADDR;
				end if;
			when ST_WRITE_RAM => 
				if aux_ram_finish_flag = '1' then
					state <= ST_WRITE_CONTROL_FNS;
				else
					state <= ST_WRITE_RAM;
				end if;
			when ST_WRITE_CONTROL_FNS =>
				if aux_control_finish_flag = '1' then
					state <= ST_WRITE_FTW;
				else
					state <= ST_WRITE_CONTROL_FNS;
				end if;
			when ST_WRITE_FTW =>
				if aux_ftw_finish_flag = '1' then
					state <= ST_UPDATE;
				else
					state <= ST_WRITE_FTW;
				end if;
			when ST_UPDATE =>
				state <= ST_FINISH;
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
			when ST_WRITE_PROFILES =>
				dds_reset     <= '0';
				dds_sdo       <= aux_profile_sdo;
				dds_sclk      <= aux_profile_sclk;
				dds_io_reset  <= aux_profile_finish_flag;
				dds_io_update <= aux_profile_finish_flag;
			when ST_WRITE_RAM_ADDR =>
				dds_reset     <= '0';
				dds_sdo       <= aux_ram_addr_sdo;
				dds_sclk      <= aux_ram_addr_sclk;
				dds_io_reset  <= '0';
				dds_io_update <= '0';
			when ST_WRITE_RAM =>
				dds_reset     <= '0';
				dds_sdo       <= aux_ram_sdo;
				dds_sclk      <= aux_ram_sclk;
				dds_io_reset  <= aux_ram_finish_flag;
				dds_io_update <= aux_ram_finish_flag;
			when ST_WRITE_CONTROL_FNS =>
				dds_reset     <= '0';
				dds_sdo       <= aux_control_sdo;
				dds_sclk      <= aux_control_sclk;
				dds_io_reset  <= aux_control_finish_flag;
				dds_io_update <= aux_control_finish_flag;
			when ST_WRITE_FTW =>
				dds_reset     <= '0';
				dds_sdo       <= aux_ftw_sdo;
				dds_sclk      <= aux_ftw_sclk;
				dds_io_reset  <= '0';
				dds_io_update <= '0';
			when ST_UPDATE =>
				dds_reset     <= '0';
				dds_sdo       <= '0';
				dds_sclk      <= '0';
				dds_io_reset  <= '0';
				dds_io_update <= '1';
			when ST_FINISH =>
				dds_reset     <= '0';
				dds_sdo       <= '0';
				dds_sclk      <= '0';
				dds_io_reset  <= '1';
				dds_io_update <= '0';
		end case;
	end process;
	
	aux_signal_control:
	process (state)
	begin
		case state is
			when ST_STANDBY =>
				dac_wre            <= '1';
				aux_profile_clear  <= '1';
				aux_ram_addr_reset <= '1';
				aux_ram_clear      <= '1';
				aux_control_clear  <= '1';
				aux_ftw_reset      <= '1';
			when ST_WRITE_PROFILES =>
				dac_wre            <= '0';
				aux_profile_clear  <= '0';
				aux_ram_addr_reset <= '1';
				aux_ram_clear      <= '1';
				aux_control_clear  <= '1';
				aux_ftw_reset      <= '1';
			when ST_WRITE_RAM_ADDR =>
				dac_wre            <= '0';
				aux_profile_clear  <= '0';
				aux_ram_addr_reset <= '0';
				aux_ram_clear      <= '1';
				aux_control_clear  <= '1';
				aux_ftw_reset      <= '1';
			when ST_WRITE_RAM =>
				dac_wre            <= '0';
				aux_profile_clear  <= '0';
				aux_ram_addr_reset <= '1';
				aux_ram_clear      <= '0';
				aux_control_clear  <= '1';
				aux_ftw_reset      <= '1';
			when ST_WRITE_CONTROL_FNS =>
				dac_wre            <= '0';
				aux_profile_clear  <= '0';
				aux_ram_addr_reset <= '1';
				aux_ram_clear      <= '0';
				aux_control_clear  <= '0';
				aux_ftw_reset      <= '1';
			when ST_WRITE_FTW =>
				dac_wre            <= '0';
				aux_profile_clear  <= '0';
				aux_ram_addr_reset <= '1';
				aux_ram_clear      <= '0';
				aux_control_clear  <= '0';
				aux_ftw_reset      <= '0';
			when ST_UPDATE =>
				dac_wre            <= '0';
				aux_profile_clear  <= '0';
				aux_ram_addr_reset <= '1';
				aux_ram_clear      <= '0';
				aux_control_clear  <= '0';
				aux_ftw_reset      <= '1';
			when ST_FINISH =>
				dac_wre            <= '0';
				aux_profile_clear  <= '0';
				aux_ram_addr_reset <= '1';
				aux_ram_clear      <= '0';
				aux_control_clear  <= '0';
				aux_ftw_reset      <= '1';
		end case;
	end process;
end behavior;
