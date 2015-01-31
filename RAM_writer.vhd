LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY RAM_writer IS
	PORT (ram_clk: IN STD_LOGIC;
			async_reset: IN STD_LOGIC;
			ram_SCLK: OUT STD_LOGIC;
			ram_sdo: OUT STD_LOGIC_VECTOR (1 DOWNTO 0);
			ram_io_update: OUT STD_LOGIC;
			ram_io_reset: OUT STD_LOGIC;
			write_complete: OUT STD_LOGIC);
END RAM_writer;

ARCHITECTURE behavior OF RAM_writer IS
	TYPE state_type IS (standby, wait_state, read_ROM, data_transfer, finish);
	SIGNAL state: state_type;
	
	SIGNAL aux_parallel_ramdata_in: STD_LOGIC_VECTOR (31 DOWNTO 0);
	SIGNAL aux_ROM_data_out: STD_LOGIC_VECTOR (31 DOWNTO 0);
	SIGNAL aux_finish_flag: STD_LOGIC;
	SIGNAL aux_active_flag: STD_LOGIC;
	SIGNAL aux_ROM_address: STD_LOGIC_VECTOR (9 DOWNTO 0);
	SIGNAL aux_reset: STD_LOGIC;
	
	SIGNAL address_counter: INTEGER := 0;
	
	COMPONENT RAM_p2s_bus 
		PORT(clock, reset: IN STD_LOGIC;
			parallel_ramdata_in: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			SCLK: OUT STD_LOGIC;
			serial_ramdata_out: OUT STD_LOGIC;
			active_flag: BUFFER STD_LOGIC;
			finish_flag: OUT STD_LOGIC);
	END COMPONENT;
	
	COMPONENT data_rom_test
		PORT (address: IN STD_LOGIC_VECTOR (9 DOWNTO 0);
				clock: IN STD_LOGIC  := '1';
				q: OUT STD_LOGIC_VECTOR (31 DOWNTO 0));
	END COMPONENT;
BEGIN
	
	parallel_to_serial: RAM_p2s_bus
		PORT MAP (clock => ram_clk,
					 reset => aux_reset,
					 parallel_ramdata_in => aux_parallel_ramdata_in,
					 SCLK => RAM_SCLK,
					 serial_ramdata_out => ram_sdo(1),
					 active_flag => aux_active_flag,
					 finish_flag => aux_finish_flag);
	
	data_rom_inst: data_rom_test
		PORT MAP (address => aux_ROM_address,
					 clock => ram_clk,
					 q => aux_ROM_data_out);
	
	PROCESS (ram_clk, async_reset)
	BEGIN
		IF (async_reset = '1') THEN
			state <= standby;
		ELSIF (ram_clk'EVENT AND ram_clk = '1') THEN
			CASE state IS 
				WHEN standby =>
					IF async_reset = '1' THEN
						state <= standby;
					ELSE state <= wait_state;
					END IF;
				WHEN wait_state =>
					state <= read_ROM;
				WHEN read_ROM => 
					state <= data_transfer;
				WHEN data_transfer => 
					IF aux_finish_flag = '1' THEN
						IF address_counter = 1023 THEN 
							state <= finish;
						ELSE 
							state <= read_ROM;
							address_counter <= address_counter + 1;
						END IF;
					ELSE state <= data_transfer;
					END IF;
				WHEN finish =>
					IF async_reset = '1' THEN
						state <= standby;
					ELSE state <= finish;
					END IF;
			END CASE;
			
			aux_ROM_address <= std_logic_vector(to_unsigned(address_counter,10));
			
		END IF;
	END PROCESS;
	
	aux_parallel_ramdata_in <= aux_ROM_data_out;

	
	signal_assignments: PROCESS (state)
	BEGIN
		CASE state IS 
			WHEN standby =>
				aux_reset <= '1';
				ram_io_reset <= '1';
				ram_io_update <= '0';
				write_complete <= '0';
			WHEN wait_state => 
				aux_reset <= '1';
				ram_io_reset <= '0';
				ram_io_update <= '0';
				write_complete <= '0';
			WHEN read_ROM => 
				aux_reset <= '1';
				ram_io_reset <= '0';
				ram_io_update <= '0';
				write_complete <= '0';
			WHEN data_transfer =>
				aux_reset <= '0';
				ram_io_reset <= '0';
				write_complete <= '0';
				IF aux_finish_flag = '1' THEN
					ram_io_update <= '1';
				ELSE ram_io_update <= '0';
				END IF;
			WHEN finish =>
				ram_io_reset <= '1';
				aux_reset <= '1';
				ram_io_update <= '1';
				write_complete <= '1';
		END CASE;
	END PROCESS;
END behavior;						