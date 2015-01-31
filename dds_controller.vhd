LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY dds_controller IS
	PORT (dds_clk: IN STD_LOGIC;
			dds_reset: IN STD_LOGIC;
			profile_select: IN STD_LOGIC_VECTOR (2 DOWNTO 0);
			dds_ftw: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			-- Only write to SDIO, never SDO
			dds_sdo_pin: OUT STD_LOGIC_VECTOR (1 DOWNTO 0);
			dds_io_reset_pin: OUT STD_LOGIC;
			dds_io_update_pin: OUT STD_LOGIC;
			dds_sclk_pin: OUT STD_LOGIC;
			dds_profile_pins: OUT STD_LOGIC_VECTOR (2 DOWNTO 0);
			dds_cs: OUT STD_LOGIC);
END dds_controller;

ARCHITECTURE behavior OF dds_controller IS
	
	TYPE state_type IS (standby, write_ftw, write_ram, write_profiles, finish);
	SIGNAL state: state_type;
	
	SIGNAL aux_profile_sdo: STD_LOGIC_VECTOR (1 DOWNTO 0);
	SIGNAL aux_profile_io_reset: STD_LOGIC;
	SIGNAL aux_profile_io_update: STD_LOGIC;
	SIGNAL aux_profile_sclk: STD_LOGIC;
	SIGNAL aux_profile_master_reset: STD_LOGIC;
	SIGNAL aux_profile_write_complete: STD_LOGIC;
	
	SIGNAL aux_ftw_sdo: STD_LOGIC_VECTOR (1 DOWNTO 0);
	SIGNAL aux_ftw_io_update: STD_LOGIC;
	SIGNAL aux_ftw_sclk: STD_LOGIC;
	SIGNAL aux_ftw_write_complete: STD_LOGIC;
	SIGNAL aux_ftw_reset: STD_LOGIC;
	
	SIGNAL aux_ram_sclk: STD_LOGIC;
	SIGNAL aux_ram_sdo: STD_LOGIC_VECTOR (1 DOWNTO 0);
	SIGNAL aux_ram_io_update: STD_LOGIC;
	SIGNAL aux_ram_io_reset: STD_LOGIC;
	SIGNAL aux_RAM_write_complete: STD_LOGIC;
	
	COMPONENT top_profilecontrol_writer
		PORT (top_clk: IN STD_LOGIC;
			top_async_clear: IN STD_LOGIC;
			top_sdo_pin: OUT STD_LOGIC_VECTOR (1 DOWNTO 0);
			top_io_reset_pin: OUT STD_LOGIC;
			top_io_update_pin: OUT STD_LOGIC;
			top_sclk_pin: OUT STD_LOGIC;
			top_profile_write_complete: OUT STD_LOGIC);
	END COMPONENT;
	
	COMPONENT RAM_writer
		PORT (ram_clk: IN STD_LOGIC;
			async_reset: IN STD_LOGIC;
			ram_SCLK: OUT STD_LOGIC;
			ram_sdo: OUT STD_LOGIC_VECTOR (1 DOWNTO 0);
			ram_io_update: OUT STD_LOGIC;
			ram_io_reset: OUT STD_LOGIC;
			write_complete: OUT STD_LOGIC);
	END COMPONENT; 
	
	COMPONENT FTW_writer
		PORT (clock, reset: IN STD_LOGIC;
			parallel_ftwdata_in: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			SCLK: OUT STD_LOGIC;
			serial_ftwdata_out: OUT STD_LOGIC;
			io_update: OUT STD_LOGIC;
			finish_flag: OUT STD_LOGIC);
	END COMPONENT;
BEGIN
	profile_writer: top_profilecontrol_writer
		PORT MAP (top_clk => dds_clk,
					top_async_clear => aux_profile_master_reset,
					top_sdo_pin => aux_profile_sdo,
					top_io_reset_pin => aux_profile_io_reset,
					top_io_update_pin => aux_profile_io_update,
					top_sclk_pin => aux_profile_sclk,
					top_profile_write_complete => aux_profile_write_complete);
	
	RAM_writer_inst: RAM_writer
		PORT MAP (ram_clk => dds_clk,
					async_reset => dds_reset,
					ram_SCLK => aux_ram_sclk,
					ram_sdo => aux_ram_sdo,
					ram_io_update => aux_ram_io_update,
					ram_io_reset => aux_ram_io_reset,
					write_complete => aux_RAM_write_complete);
	
	FTW_writer_inst: FTW_writer
		PORT MAP (clock => dds_clk,
					 reset => aux_ftw_reset,
					 parallel_ftwdata_in => dds_ftw,
					 SCLK => aux_ftw_sclk,
					 serial_ftwdata_out => aux_ftw_sdo(1),
					 io_update => aux_ftw_io_update,
					 finish_flag => aux_ftw_write_complete);
	
	aux_profile_master_reset <= NOT aux_RAM_write_complete;
	aux_ftw_reset <= NOT aux_profile_write_complete;
	
	dds_cs <= '0';
	
	PROCESS (dds_clk, dds_reset, aux_RAM_write_complete)
	BEGIN
		IF (dds_reset = '1') THEN
			state <= standby;
		ELSIF (dds_clk'EVENT AND dds_clk = '1') THEN
			CASE state IS 
				WHEN standby => 
					IF (dds_reset = '0') THEN 
						state <= write_RAM;
						--state <= write_profiles;
					ELSE state <= standby;
					END IF;
				WHEN write_RAM => 
					IF (aux_RAM_write_complete = '1') THEN
						state <= write_profiles;
					ELSE state <= write_RAM;
					END IF;
				WHEN write_profiles => 
					IF (aux_profile_write_complete = '1') THEN
						state <= finish;
					ELSE state <= write_profiles;
					END IF;
				WHEN write_ftw => 
					IF (aux_ftw_write_complete = '1') THEN
						state <= finish;
					END IF;
				WHEN finish =>
					state <= finish;
			END CASE;
		END IF;
	END PROCESS;
	
	PROCESS (state)
	BEGIN 
		CASE state IS
			WHEN standby =>
				dds_sdo_pin <= B"00";
				dds_io_reset_pin <= '1';
				dds_io_update_pin <= '0';
				dds_sclk_pin <= '0';
			WHEN write_RAM =>
				dds_sdo_pin <= aux_ram_sdo;
				dds_io_reset_pin <= aux_ram_io_reset;
				dds_io_update_pin <= aux_ram_io_update;
				dds_sclk_pin <= aux_ram_sclk;
			WHEN write_profiles =>
				dds_sdo_pin <= aux_profile_sdo;
				dds_io_reset_pin <= aux_profile_io_reset;
				dds_io_update_pin <= aux_profile_io_update;
				dds_sclk_pin <= aux_profile_sclk;
			WHEN write_ftw =>
				dds_sdo_pin <= aux_ftw_sdo;
				dds_io_reset_pin <= '0';
				dds_io_update_pin <= aux_ftw_io_update;
				dds_sclk_pin <= aux_ftw_sclk;
			WHEN finish =>
				dds_sdo_pin <= B"00";
				dds_io_reset_pin <= '1';
				dds_io_update_pin <= '0';
				dds_sclk_pin <= '0';
				dds_profile_pins <= profile_select;
		END CASE;
	END PROCESS;
END behavior;