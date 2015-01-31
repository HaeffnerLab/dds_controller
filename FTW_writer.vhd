LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY FTW_writer IS 
	GENERIC (ftw_data_width: INTEGER := 40);
	PORT (clock, reset: IN STD_LOGIC;
			parallel_ftwdata_in: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			SCLK: OUT STD_LOGIC;
			serial_ftwdata_out: OUT STD_LOGIC;
			io_update: OUT STD_LOGIC;
			finish_flag: OUT STD_LOGIC);
END FTW_writer;

ARCHITECTURE behavior OF FTW_writer IS 
	TYPE state_type IS (load, write_out, finish);
	SIGNAL state: state_type := load;
	SIGNAL DST: STD_LOGIC_VECTOR(39 DOWNTO 0);
	SIGNAL data: STD_LOGIC;
	CONSTANT count: INTEGER := 40;
	SIGNAL counter: INTEGER RANGE 0 TO 80;
	CONSTANT ftw_address_byte: STD_LOGIC_VECTOR (7 DOWNTO 0) := "00000111";
BEGIN
	
	PROCESS (clock)
		VARIABLE i: INTEGER := 0;
	BEGIN
		IF (reset = '1') THEN
			state <= load;
		ELSIF (clock'EVENT AND clock = '1') THEN
			i := i+1;
			IF (i = counter) THEN 
				CASE state IS
					WHEN load => 
						IF reset = '0' THEN
							state <= write_out;
						ELSE state <= load;
						END IF;
					WHEN write_out =>
						state <= finish;
					WHEN finish =>
						IF reset = '0' THEN
							state <= load;
						ELSE state <= finish;
						END IF;
				END CASE;
				i := 0;
			END IF;
		END IF;
	END PROCESS;
	
	signal_control: PROCESS (state, reset, clock)
		VARIABLE sclk_sync: STD_LOGIC_VECTOR (1 DOWNTO 0) := B"00";
	BEGIN
		IF reset = '1' THEN
			finish_flag <= '0';
			io_update <= '0';
		END IF;
		
		CASE state IS
			WHEN load =>
				counter <= 1;
				finish_flag <= '0';
				io_update <= '0';
			WHEN write_out =>
				finish_flag <= '0';
				counter <= 2*ftw_data_width;
				io_update <= '0';
			WHEN finish =>
				finish_flag <= '1';
				io_update <= '1';
				IF reset = '0' THEN
					counter <= 1;
				END IF;
		END CASE;
	END PROCESS;
	
	data_assignments: PROCESS (clock, state, reset)
		VARIABLE sclk_sync: STD_LOGIC_VECTOR (1 DOWNTO 0) := B"00";
	BEGIN
		IF reset = '1' THEN
			data <= '0';
			DST <= (OTHERS => '0');
		ELSIF (clock'EVENT AND clock = '1') THEN
			CASE state IS 
				WHEN load =>
					data <= ftw_address_byte(7);
					DST <= ftw_address_byte(6 DOWNTO 0) & parallel_ftwdata_in & '0';
					SCLK <= '0';
					sclk_sync := B"00";
				WHEN write_out => 
					IF sclk_sync = B"00" THEN
							sclk_sync := B"01";
							SCLK <= '1';
					ELSIF sclk_sync = B"01" THEN
							data <= DST (ftw_data_width-1);
							DST <= DST (ftw_data_width-2 DOWNTO 0) & '0';
							sclk_sync := B"00";
							SCLK <= '0';
					ELSE sclk_sync := B"00";
					END IF;
				WHEN finish => 
					data <= '0';
					DST <= (OTHERS => '0');
					SCLK <= '0';
			END CASE;
		END IF;
	END PROCESS;

	serial_ftwdata_out <= data;

END behavior;		