LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY top_profilecontrol_writer IS
	GENERIC (profiledata_width: INTEGER := 73);
	PORT (top_clk: IN STD_LOGIC;
			top_async_clear: IN STD_LOGIC;
			top_sdo_pin: OUT STD_LOGIC_VECTOR (1 DOWNTO 0);
			top_io_reset_pin: OUT STD_LOGIC;
			top_io_update_pin: OUT STD_LOGIC;
			top_sclk_pin: OUT STD_LOGIC;
			top_profile_write_complete: OUT STD_LOGIC);
END top_profilecontrol_writer;

ARCHITECTURE behavior OF top_profilecontrol_writer IS

	SIGNAL int_address: STD_LOGIC_VECTOR (3 DOWNTO 0);
	SIGNAL int_clock: STD_LOGIC;
	SIGNAL aux_bus_in: STD_LOGIC_VECTOR (profiledata_width-1 DOWNTO 0);
	SIGNAL aux_ROM_out: STD_LOGIC_VECTOR (profiledata_width-1 DOWNTO 0);
	
	COMPONENT profileandcontrol_writer
		PORT (clk: IN STD_LOGIC;
			bus_in: IN STD_LOGIC_VECTOR (profiledata_width-1 DOWNTO 0);
			async_reset: IN STD_LOGIC;
			sdo_pin: OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
			sclk_pin: OUT STD_LOGIC;
			io_reset_pin: OUT STD_LOGIC;
			io_update_pin: OUT STD_LOGIC;
			profile_write_complete: OUT STD_LOGIC);
	END COMPONENT;
	
	COMPONENT rom_mf
		PORT (address: IN STD_LOGIC_VECTOR (3 DOWNTO 0);
				clock: IN STD_LOGIC  := '1';
				q: OUT STD_LOGIC_VECTOR (72 DOWNTO 0));
	END COMPONENT;
BEGIN
	
	dds_profilewriter:profileandcontrol_writer
		PORT MAP (clk => top_clk,
					bus_in => aux_bus_in,
					async_reset => top_async_clear,
					sdo_pin => top_sdo_pin,
					sclk_pin => top_sclk_pin,
					io_reset_pin => top_io_reset_pin,
					io_update_pin => top_io_update_pin,
					profile_write_complete => top_profile_write_complete);
	
	rom_mf_instantiation:rom_mf
		PORT MAP (address => int_address,
					clock => top_clk,
					q => aux_ROM_out);
	
	aux_bus_in <= aux_ROM_out;
	
	PROCESS (top_clk)
		VARIABLE address_counter: INTEGER := 1;
	BEGIN
		IF top_async_clear = '0' THEN
			IF (top_clk'EVENT AND top_clk = '1') THEN
				address_counter := address_counter + 1;
				IF address_counter = 1 THEN
					int_address <= B"0000";
				ELSIF address_counter = 2 THEN
					int_address <= B"0001";
				ELSIF address_counter = 3 THEN
					int_address <= B"0010";
				ELSIF address_counter = 4 THEN
					int_address <= B"0011";
				ELSIF address_counter = 5 THEN
					int_address <= B"0100";
				ELSIF address_counter = 6 THEN
					int_address <= B"0101";
				ELSIF address_counter = 7 THEN
					int_address <= B"0110";
				ELSIF address_counter = 8 THEN
					int_address <= B"0111";
				ELSIF address_counter = 9 THEN
					int_address <= B"1000";
				ELSIF address_counter = 10 THEN
					int_address <= B"1001";
				ELSIF address_counter = 11 THEN
					int_address <= B"1010";
				ELSE int_address <= B"0000";
				END IF;
			END IF;
		ELSE int_address <= B"0000";
		END IF;
	END PROCESS;
END behavior;