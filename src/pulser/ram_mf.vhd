library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.all;

entity ram_mf is
	generic (
		WRITE_WIDTH:      natural := 16;
		WRITE_ADDR_WIDTH: natural := 12;
		WRITE_DEPTH:      natural := 4096;
		READ_WIDTH:       natural := 64;
		READ_ADDR_WIDTH:  natural := 10;
		READ_DEPTH:       natural := 1024
	);
	port (
		data:      in std_logic_vector(WRITE_WIDTH - 1 downto 0);
		wraddress: in std_logic_vector(WRITE_ADDR_WIDTH - 1 downto 0);
		wrclock:   in std_logic := '1';
		wren:      in std_logic := '0';
		rdaddress: in std_logic_vector(READ_ADDR_WIDTH - 1 downto 0);
		rdclock:   in std_logic;
		q:         out std_logic_vector(READ_WIDTH - 1 downto 0)
	);
end ram_mf;

architecture syn of ram_mf is

	signal sub_wire0: std_logic_vector(READ_WIDTH - 1 downto 0);

	component altsyncram
	generic (
		address_reg_b:          string;
		clock_enable_input_a:   string;
		clock_enable_input_b:   string;
		clock_enable_output_a:  string;
		clock_enable_output_b:  string;
		intended_device_family: string;
		lpm_type:               string;
		numwords_a:             natural;
		numwords_b:             natural;
		operation_mode:         string;
		outdata_aclr_b:         string;
		outdata_reg_b:          string;
		power_up_uninitialized: string;
		widthad_a:              natural;
		widthad_b:              natural;
		width_a:                natural;
		width_b:                natural;
		width_byteena_a:        natural
	);
	port (
		address_a: in std_logic_vector(WRITE_ADDR_WIDTH - 1 downto 0);
		clock0:    in std_logic;
		data_a:    in std_logic_vector(WRITE_WIDTH - 1 downto 0);
		q_b:       out std_logic_vector(READ_WIDTH - 1 downto 0);
		wren_a:    in std_logic;
		address_b: in std_logic_vector(READ_ADDR_WIDTH - 1 downto 0);
		clock1:    in std_logic
	);
	end component;

	begin
	q <= sub_wire0(63 downto 0);

	altsyncram_component: altsyncram
	generic map (
		address_reg_b          => "clock1",
		clock_enable_input_a   => "bypass",
		clock_enable_input_b   => "bypass",
		clock_enable_output_a  => "bypass",
		clock_enable_output_b  => "bypass",
		intended_device_family => "cyclone ii",
		lpm_type               => "altsyncram",
		numwords_a             => WRITE_DEPTH,
		numwords_b             => READ_DEPTH,
		operation_mode         => "dual_port",
		outdata_aclr_b         => "none",
		outdata_reg_b          => "clock1",
		power_up_uninitialized => "false",
		widthad_a              => WRITE_ADDR_WIDTH,
		widthad_b              => READ_ADDR_WIDTH,
		width_a                => WRITE_WIDTH,
		width_b                => READ_WIDTH,
		width_byteena_a        => 1
	)
	port map (
		address_a => wraddress,
		clock0    => wrclock,
		data_a    => data,
		wren_a    => wren,
		address_b => rdaddress,
		clock1    => rdclock,
		q_b       => sub_wire0
	);

end syn;
