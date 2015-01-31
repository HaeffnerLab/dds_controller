LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY test_profilecontrol_writer2 IS
	GENERIC (profiledata_width: INTEGER := 32);
	PORT (clock, start, reset: IN STD_LOGIC;
			parallel_profiledata_in: IN STD_LOGIC_VECTOR (profiledata_width-1 DOWNTO 0);
			SCLK: OUT STD_LOGIC;
			serial_profiledata_out: OUT STD_LOGIC;
			active_flag: BUFFER STD_LOGIC);
END test_profilecontrol_writer2;

ARCHITECTURE behavior OF test_profilecontrol_writer2 IS
	TYPE state IS (load, write_out, finish);
	SIGNAL pr_state: state := load;
	SIGNAL nx_state: state;
	SIGNAL DST: STD_LOGIC_VECTOR (profiledata_width-1 DOWNTO 0);
	SIGNAL data: STD_LOGIC;
	SIGNAL sclk_enable: STD_LOGIC;
	CONSTANT count: INTEGER := 16;
	CONSTANT extended_count: INTEGER := 32;
	SIGNAL counter: INTEGER RANGE 0 TO 64;
BEGIN
	PROCESS (clock)
		VARIABLE i: INTEGER := 0;
		VARIABLE clk_counter: STD_LOGIC_VECTOR (1 DOWNTO 0) := B"00";
	BEGIN
		IF (clock'EVENT AND clock = '1' AND sclk_enable = '1') THEN
			i := i+1;
			IF (i = counter+1) THEN 
				pr_state <= nx_state;
				i := 0;
			END IF;
			CASE clk_counter IS
				WHEN B"00" =>
					IF active_flag = '1' THEN
					SCLK <= '1';
					END IF;
					clk_counter := B"01";
				WHEN B"01" =>
					SCLK <= '0';
					clk_counter := B"00";
				WHEN OTHERS =>
					clk_counter := B"00";
					SCLK <= '0';
			END CASE;
		ELSIF clk_counter = B"00" THEN
			SCLK <= '0';
		END IF;
	END PROCESS;
	
	PROCESS (pr_state, clock, reset)
		VARIABLE sdo_counter: STD_LOGIC_VECTOR (1 DOWNTO 0) := B"00";
	BEGIN
		IF (reset = '1') THEN
			data <= '0';
			DST <= (OTHERS => '0');
			active_flag <= '0';
		END IF;
		
		CASE pr_state IS
			WHEN load =>
				IF (start = '1') THEN
					data <= '0';
					sclk_enable <= '1';
					DST <= parallel_profiledata_in;
					nx_state <= write_out;
					counter <= 0;
					active_flag <= '0';
				END IF;
			WHEN write_out =>
				active_flag <= '1';
				nx_state <= finish;
				IF (parallel_profiledata_in(0) = '1') THEN
					counter <= (2*extended_count);
				ELSE counter <= (2*count);
				END IF;
				
				IF (clock'EVENT AND clock = '1') THEN
					CASE sdo_counter IS
						WHEN B"00" => 	
							data <= DST(profiledata_width-1);
							DST <= DST(profiledata_width-2 DOWNTO 0) & '0';
							sdo_counter := B"01";
						WHEN B"01" => 
							sdo_counter := B"00";
						WHEN OTHERS =>
							sdo_counter := B"00";
					END CASE;
				END IF;
			WHEN finish =>
				data <= '0';
				active_flag <= '0';
				IF (start = '1') THEN
					nx_state <= load;
					counter <= 0;
				END IF;
		END CASE;
	END PROCESS;
	serial_profiledata_out <= data;
END behavior;
			
	