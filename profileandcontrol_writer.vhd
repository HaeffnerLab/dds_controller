--------------------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;
--------------------------------------------------------------------------------------------
ENTITY profileandcontrol_writer IS
	GENERIC (profiledata_width: INTEGER := 73);
	PORT (clk: IN STD_LOGIC;
			bus_in: IN STD_LOGIC_VECTOR (profiledata_width-1 DOWNTO 0);
			async_reset: IN STD_LOGIC;
			sdo_pin: OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
			sclk_pin: OUT STD_LOGIC;
			io_reset_pin: OUT STD_LOGIC;
			io_update_pin: OUT STD_LOGIC;
			profile_write_complete: OUT STD_LOGIC);
END profileandcontrol_writer;
--------------------------------------------------------------------------------------------
ARCHITECTURE behavior OF profileandcontrol_writer IS

	SIGNAL aux_clock: STD_LOGIC;
	SIGNAL aux_parallel_profiledata_in: STD_LOGIC_VECTOR(profiledata_width-1 DOWNTO 0);
	SIGNAL aux_active_flag: STD_LOGIC;
	SIGNAL aux_finish_flag: STD_LOGIC;
	SIGNAL aux_reset: STD_LOGIC;
		
	SIGNAL aux_rdreq: STD_LOGIC;
	SIGNAL aux_wrreq: STD_LOGIC;
	SIGNAL aux_rdclk: STD_LOGIC;
	SIGNAL aux_wrclk: STD_LOGIC;
	SIGNAL aux_empty: STD_LOGIC;
	SIGNAL aux_full: STD_LOGIC;
	SIGNAL aux_fifo_out: STD_LOGIC_VECTOR (profiledata_width-1 DOWNTO 0);
	SIGNAL aux_usedw: STD_LOGIC_VECTOR (3 DOWNTO 0);
	SIGNAL fifo_active: STD_LOGIC;
	
	TYPE state_type IS (standby, wait_state, write_fifo, read_fifo, data_transfer, finish);
	SIGNAL state: state_type := standby;

	
	COMPONENT profilecontrol_bus 
		PORT (clock, reset: IN STD_LOGIC;
			parallel_profiledata_in: IN STD_LOGIC_VECTOR (profiledata_width-1 DOWNTO 0);
			SCLK: OUT STD_LOGIC;
			serial_profiledata_out: OUT STD_LOGIC;
			active_flag: BUFFER STD_LOGIC;
			finish_flag: OUT STD_LOGIC);
	END COMPONENT;
	
	COMPONENT fifo_mf
		PORT (aclr: IN STD_LOGIC ;
				clock: IN STD_LOGIC ;
				data: IN STD_LOGIC_VECTOR (72 DOWNTO 0);
				rdreq: IN STD_LOGIC ;
				wrreq: IN STD_LOGIC ;
				empty: OUT STD_LOGIC ;
				full: OUT STD_LOGIC ;
				q: OUT STD_LOGIC_VECTOR (72 DOWNTO 0);
				usedw: OUT STD_LOGIC_VECTOR (3 DOWNTO 0));
	END COMPONENT;
BEGIN
	dds_profilecontrol_bus: profilecontrol_bus
		PORT MAP (clock => clk,
						reset => aux_reset,
						parallel_profiledata_in => aux_parallel_profiledata_in,
						SCLK => sclk_pin,
						serial_profiledata_out => sdo_pin(1),
						active_flag => aux_active_flag,
						finish_flag => aux_finish_flag);
	
	fifo_mf_instantiation: fifo_mf
		PORT MAP (aclr => async_reset,
						clock => clk,
						data => bus_in (profiledata_width-1 DOWNTO 0),
						rdreq => aux_rdreq,
						wrreq => aux_wrreq,
						empty => aux_empty,
						full => aux_full,
						q => aux_fifo_out,
						usedw => aux_usedw);

	PROCESS (clk, async_reset)
	BEGIN 
		IF (async_reset = '1') THEN
			state <= standby;
		
		ELSIF (clk'EVENT AND clk = '1') THEN
			CASE state IS
				WHEN standby => 
					IF async_reset = '1' THEN
						state <= standby;
					ELSE state <= wait_state;
					END IF;
				WHEN wait_state =>
					state <= write_fifo;
				WHEN write_fifo =>
					IF (aux_usedw = B"1010") THEN
						state <= read_fifo;
					ELSE state <= write_fifo;
					END IF;
				WHEN read_fifo =>
					state <= data_transfer;
				WHEN data_transfer =>
					IF aux_finish_flag = '1' THEN
						IF aux_empty = '1' THEN
							state <= finish;
						ELSE state <= read_fifo;
						END IF;
					ELSE state <= data_transfer;
					END IF;
				WHEN finish =>
					IF (async_reset = '1') THEN
						state <= standby;
					ELSE state <= finish;
					END IF;
			END CASE;
		END IF;		
	END PROCESS;
	
	serial_control: PROCESS (state, async_reset, aux_finish_flag)
	BEGIN 
		CASE state IS 
			WHEN standby =>
				io_reset_pin <= '1';
				aux_wrreq <= '0';
				aux_rdreq <= '0';
				aux_reset <= '1';
				profile_write_complete <= '0';
			
			WHEN write_fifo =>
				io_reset_pin <= '0';
				aux_wrreq <= '1';
				aux_rdreq <= '0';
				fifo_active <= '1';
				aux_reset <= '1';
				profile_write_complete <= '0';
			
			WHEN wait_state =>
				io_reset_pin <= '0';	
				aux_wrreq <= '0';
				aux_rdreq <= '0';
				aux_reset <= '1';
				profile_write_complete <= '0';
				
			WHEN read_fifo => 	
				io_reset_pin <= '0';
				aux_wrreq <= '0';
				aux_rdreq <= '1';
				aux_reset <= '1';
				aux_parallel_profiledata_in <= aux_fifo_out;
				profile_write_complete <= '0';
			
			WHEN data_transfer =>
				aux_rdreq <= '0';
				aux_wrreq <= '0';
				io_reset_pin <= '0';
				aux_reset <= '0';
				profile_write_complete <= '0';
				IF (aux_finish_flag = '1') THEN
					io_update_pin <= '1';
				ELSE io_update_pin <= '0';
				END IF;
			
			WHEN finish =>
				io_reset_pin <= '1';
				aux_wrreq <= '0';
				aux_rdreq <= '0';
				aux_reset <= '1';
				io_update_pin <= '0';
				profile_write_complete <= '1';
		END CASE;
	END PROCESS;
END behavior; 
------------------------------------------------------------------------------------