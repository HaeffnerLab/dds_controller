-- Subcomponent code to write parallel data serially in time
library ieee;
use ieee.std_logic_1164.all;

library work;
use work.dds_lib.all;

entity p2s_bus is
	generic (
		DATA_WIDTH: natural
	);
	port (
		clock:       in std_logic;
		reset:       in std_logic; -- Stop writing, active high
		-- Parallel data in
		pdi:         in std_logic_vector(DATA_WIDTH - 1 downto 0);
		sclk:        out std_logic;
		sdo:         out std_logic; -- Serial data out
		active_flag: out std_logic; -- Active high
		finish_flag: out std_logic -- Active high
	);
end p2s_bus;

architecture behavior of p2s_bus is
	type state_type is (
		-- Sit around and keep register updated
		ST_RESET,
		-- This component uses a shift register to write to serial: on the
		-- falling edge of sclk, the highest bit is written and the register
		-- is shifter left one bit. sclk runs at half clock speed to meet
		-- setup and hold time requirements.
		ST_WRITE,
		-- Set finish flag for one cycle
		ST_FINISH
	);

	signal state: state_type := ST_RESET;

	-- Counter for number of bits written, tells when to go to finish state.
	-- A variable would be nice, but state and signal control are separate this
	-- way. I doubt this gets synthesized into sort of counter.
	signal bits_written: natural := 0;

	-- Data shift register
	-- DST_LEN is DATA_WIDTH - 1 because the first address bit is
	-- immediately written to serial output.
	constant DST_LEN: natural := DATA_WIDTH - 1;
	signal dst: std_logic_vector(DST_LEN - 1 downto 0) := (others => '0');
begin
	state_control:
	process (clock, reset)
	begin
		if reset = '1' then
			state <= ST_RESET;
		elsif rising_edge(clock) then
			case state is
			when ST_RESET => 
				state <= ST_WRITE;
			when ST_WRITE =>
				-- Finish state while last bit is written.
				if bits_written = DATA_WIDTH then
					state <= ST_FINISH;
				end if;
			when ST_FINISH =>
				state <= ST_WRITE;
			end case;
		end if;
	end process;
	
	flag_control:
	process (state, reset)
	begin
		if reset = '1' then
			finish_flag <= '0';
		else
			case state is
			when ST_RESET =>
				active_flag <= '0';
				finish_flag <= '0';
			when ST_WRITE =>
				active_flag <= '1';
				finish_flag <= '0';
			when ST_FINISH =>
				active_flag <= '1';
				finish_flag <= '1';
			end case;
		end if;
	end process;
	
	data_assignments:
	process (clock, state, reset)
		-- Internally track the value of sclk
		variable sclk_sync: std_logic := '0';
	begin
		if reset = '1' then
			sclk_sync    := '0';
			sclk         <= '0';
			bits_written <= 0;
			sdo          <= pdi(DATA_WIDTH - 1);
			dst          <= pdi(DATA_WIDTH - 2 downto 0);
		elsif rising_edge(clock) then
			case state is 
			when ST_RESET =>
				sclk_sync    := '0';
				sclk         <= '0';
				bits_written <= 0;
				sdo          <= pdi(DATA_WIDTH - 1);
				dst          <= pdi(DATA_WIDTH - 2 downto 0);
			when ST_WRITE => 
				if sclk_sync = '0' then
					sclk_sync    := '1';
					sclk         <= '1';
					bits_written <= bits_written + 1;
				else
					sclk_sync := '0';
					sclk      <= '0';
					-- Write out highest bit
					sdo       <= dst(DST_LEN - 1);
					dst       <= dst(DST_LEN - 2 downto 0) & '0';
				end if;
			when ST_FINISH => 
				if sclk_sync = '1' then
					sclk_sync := '0';
					sclk      <= '0';
				else
					sclk_sync := '1';
					sclk      <= '1';
				end if;
				bits_written <= 0;
				-- Update data register
				sdo <= pdi(DATA_WIDTH - 1);
				dst <= pdi(DATA_WIDTH - 2 downto 0);
			end case;
		end if;
	end process;
end behavior;
