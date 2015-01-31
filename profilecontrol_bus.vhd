LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY profilecontrol_bus IS
	GENERIC (profiledata_width: INTEGER := 73);
	PORT (clock, reset: IN STD_LOGIC;
			parallel_profiledata_in: IN STD_LOGIC_VECTOR (profiledata_width-1 DOWNTO 0);
			SCLK: OUT STD_LOGIC;
			serial_profiledata_out: OUT STD_LOGIC;
			active_flag: BUFFER STD_LOGIC;
			finish_flag: OUT STD_LOGIC);
END profilecontrol_bus;

ARCHITECTURE behavior OF profilecontrol_bus IS
	TYPE state_type IS (load, write_out, finish);
	SIGNAL state: state_type := load;
	SIGNAL DST: STD_LOGIC_VECTOR (profiledata_width-1 DOWNTO 0);
	SIGNAL data: STD_LOGIC;
	SIGNAL sclk_enable: STD_LOGIC;
	CONSTANT count: INTEGER := 40;
	CONSTANT extended_count: INTEGER := 72;
	SIGNAL counter: INTEGER RANGE 0 TO 144;

BEGIN
	state_control: PROCESS (clock, reset)
		VARIABLE i: INTEGER := 0;
	BEGIN
		IF reset = '1' THEN
			state <= load;
		ELSIF (clock'EVENT AND clock = '1' AND sclk_enable = '1') THEN
			i := i+1;
			IF (i = counter+1) THEN 
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
	
	signalandstate_control: PROCESS (state, clock, reset)
	BEGIN
		IF (reset = '1') THEN
			active_flag <= '0';
			finish_flag <= '0';
		END IF;
		
		CASE state IS
			WHEN load =>
				counter <= 0;
				active_flag <= '0';
				finish_flag <= '0';
				IF (reset = '0') THEN
					sclk_enable <= '1';
				END IF;
			
			WHEN write_out =>
				active_flag <= '1';
				finish_flag <= '0';
				IF (parallel_profiledata_in(0) = '1') THEN
					counter <= (2*extended_count);
				ELSE counter <= (2*count);
				END IF;
				
			WHEN finish =>
				active_flag <= '0';
				finish_flag <= '1';
				sclk_enable <= '0';
				IF (reset = '0') THEN
					counter <= 0;
				END IF;
		END CASE;
	END PROCESS;
	
	data_assignments: PROCESS (clock, state, reset)
		VARIABLE sdo_counter: STD_LOGIC_VECTOR (1 DOWNTO 0) := B"00";
	BEGIN
		IF (clock'EVENT AND clock = '1') THEN 
			CASE state IS
				WHEN load =>
					data <= parallel_profiledata_in(profiledata_width-1);
					DST <= parallel_profiledata_in(profiledata_width-2 DOWNTO 0) & '0';
					SCLK <= '0';
					sdo_counter := B"00";
				WHEN write_out => 
					IF sdo_counter = B"00" THEN
						sdo_counter := B"01";
						SCLK <= '1';
					ELSIF (sdo_counter = B"01") THEN
						data <= DST(profiledata_width-1);
						DST <= DST(profiledata_width-2 DOWNTO 0) & '0';
					sdo_counter := B"00";
						SCLK <= '0';
					ELSE sdo_counter := B"00";
					END IF;
				WHEN finish =>
					data <= '0';
					DST <= (OTHERS => '0');
					SCLK <= '0';
					SDO_counter := B"00";
			END CASE;
		END IF;
		
		IF reset = '1' THEN
			data <= '0';
			DST <= (OTHERS => '0');
		END IF;
		
	END PROCESS;
	serial_profiledata_out <= data;
END behavior;