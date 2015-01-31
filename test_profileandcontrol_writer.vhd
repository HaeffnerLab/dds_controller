LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY test_profileandcontrol_writer IS
	GENERIC (profiledata_width: INTEGER := 32);
	PORT (clock, start, reset: IN STD_LOGIC;
			parallel_profiledata_in: IN STD_LOGIC_VECTOR (profiledata_width-1 DOWNTO 0);
			SCLK: OUT STD_LOGIC;
			serial_profiledata_out: OUT STD_LOGIC;
			active_flag: OUT STD_LOGIC);
END test_profileandcontrol_writer;

ARCHITECTURE behavior OF test_profileandcontrol_writer IS
	TYPE state IS (load, write_out, finish);
	SIGNAL pr_state, nx_state: state;
	SIGNAL DST: STD_LOGIC_VECTOR (profiledata_width-1 DOWNTO 0);
	SIGNAL data: STD_LOGIC;
	SIGNAL sclk_enable: STD_LOGIC;
	CONSTANT count: INTEGER := 16;
	CONSTANT extended_count: INTEGER := 32;
	SIGNAL counter: INTEGER RANGE 0 TO 32;
BEGIN
	PROCESS (clock)
		VARIABLE i: INTEGER RANGE 0 TO 32;
	BEGIN
		IF (clock'EVENT AND clock = '1') THEN
			i := i+1;
			IF (i = counter) THEN 
				pr_state <= nx_state;
				i := 0;
			END IF;
		END IF;
	END PROCESS;
	
	PROCESS (pr_state, clock, reset)
	BEGIN
		IF (reset = '1') THEN
			data <= '0';
			DST <= (OTHERS => '0');
		END IF;
		
		CASE pr_state IS
			WHEN load =>
				IF (start = '1') THEN
					data <= '0';
					sclk_enable <= '1';
					DST <= parallel_profiledata_in;
					nx_state <= write_out;
					counter <= 1;
				END IF;
			WHEN write_out =>
				active_flag <= '1';
				nx_state <= finish;
				IF (parallel_profiledata_in(0) = '1') THEN
					counter <= extended_count;
				ELSE counter <= count;
				END IF;
				
				IF (clock'EVENT AND clock = '1') THEN
					data <= DST(profiledata_width-1);
					DST <= DST(profiledata_width-2 DOWNTO 0) & '0';
				END IF;
			WHEN finish =>
				active_flag <= '0';
				IF (start = '1') THEN
					nx_state <= load;
					counter <= 1;
				END IF;
		END CASE;
	END PROCESS;
END behavior;
			
	