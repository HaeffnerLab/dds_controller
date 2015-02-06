LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY top_profilecontrol_writer IS
	PORT (top_clk: IN STD_LOGIC;
			top_async_clear: IN STD_LOGIC;
			top_sdo_pin: OUT STD_LOGIC_VECTOR (1 DOWNTO 0);
			top_io_reset_pin: OUT STD_LOGIC;
			top_io_update_pin: OUT STD_LOGIC;
			top_sclk_pin: OUT STD_LOGIC;
			top_profile_write_complete: OUT STD_LOGIC);
END top_profilecontrol_writer;

ARCHITECTURE behavior OF top_profilecontrol_writer IS
	constant ROM_DEPTH: natural := 11;

	TYPE state_type IS (standby, wait_state, read_ROM, data_transfer, finish);
	SIGNAL state: state_type;
	
	SIGNAL aux_parallel_profiledata_in: STD_LOGIC_VECTOR (72 DOWNTO 0);
	SIGNAL aux_ROM_data_out: STD_LOGIC_VECTOR (72 DOWNTO 0);
	SIGNAL aux_finish_flag: STD_LOGIC;
	SIGNAL aux_active_flag: STD_LOGIC;
	SIGNAL aux_ROM_address: STD_LOGIC_VECTOR (3 DOWNTO 0);
	SIGNAL aux_reset: STD_LOGIC;
	
	SIGNAL address_counter: INTEGER := 0;
	
	COMPONENT profilecontrol_bus 
		PORT(clock, reset: IN STD_LOGIC;
			parallel_profiledata_in: IN STD_LOGIC_VECTOR (72 DOWNTO 0);
			SCLK: OUT STD_LOGIC;
			serial_profiledata_out: OUT STD_LOGIC;
			active_flag: BUFFER STD_LOGIC;
			finish_flag: OUT STD_LOGIC);
	END COMPONENT;
	
	COMPONENT rom_mf
		PORT (address: IN STD_LOGIC_VECTOR (3 DOWNTO 0);
				clock: IN STD_LOGIC  := '1';
				q: OUT STD_LOGIC_VECTOR (72 DOWNTO 0));
	END COMPONENT;
BEGIN
	
	parallel_to_serial: profilecontrol_bus
		PORT MAP (clock => top_clk,
					 reset => aux_reset,
					 parallel_profiledata_in => aux_parallel_profiledata_in,
					 SCLK => top_sclk_pin,
					 serial_profiledata_out => top_sdo_pin(1),
					 active_flag => aux_active_flag,
					 finish_flag => aux_finish_flag);
	
	rom_mf_instantiation: rom_mf
		PORT MAP (address => aux_ROM_address,
					 clock => top_clk,
					 q => aux_ROM_data_out);
					 
	top_io_update_pin <= aux_finish_flag;
	
	PROCESS (top_clk, top_async_clear)
	BEGIN
		IF (top_async_clear = '1') THEN
			state <= standby;
		ELSIF (top_clk'EVENT AND top_clk = '1') THEN
			CASE state IS 
				WHEN standby =>
					IF top_async_clear = '1' THEN
						state <= standby;
					ELSE state <= wait_state;
					END IF;
				WHEN wait_state =>
					state <= read_ROM;
				WHEN read_ROM => 
					state <= data_transfer;
				WHEN data_transfer => 
					IF aux_finish_flag = '1' THEN
						IF address_counter = ROM_DEPTH THEN 
							state <= finish;
						ELSE 
							state <= read_ROM;
							address_counter <= address_counter + 1;
						END IF;
					ELSE state <= data_transfer;
					END IF;
				WHEN finish =>
					IF top_async_clear = '1' THEN
						state <= standby;
					ELSE state <= finish;
					END IF;
			END CASE;
			
			aux_ROM_address <= std_logic_vector(to_unsigned(address_counter,4));
			
		END IF;
	END PROCESS;
	
	aux_parallel_profiledata_in <= aux_ROM_data_out;

	signal_assignments: PROCESS (state)
	BEGIN
		CASE state IS 
			WHEN standby =>
				aux_reset <= '1';
				top_io_reset_pin <= '1';
				top_profile_write_complete <= '0';
			WHEN wait_state => 
				aux_reset <= '1';
				top_io_reset_pin <= '0';
				top_profile_write_complete <= '0';
			WHEN read_ROM => 
				aux_reset <= '1';
				top_io_reset_pin <= '0';
				top_profile_write_complete <= '0';
			WHEN data_transfer =>
				aux_reset <= '0';
				top_io_reset_pin <= '0';
				top_profile_write_complete <= '0';
			WHEN finish =>
				top_io_reset_pin <= '1';
				aux_reset <= '1';
				top_profile_write_complete <= '1';
		END CASE;
	END PROCESS;
END behavior;						