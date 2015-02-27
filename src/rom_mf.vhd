-- Generic implementation of Altera single-port ROM component.
library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.all;

entity rom_mf is
	generic (
		DATA_WIDTH:    natural;
		ADDRESS_WIDTH: natural;
		DEPTH:         natural;
		INIT_FILE:     string
	);
	port (
		address: in std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
		clock:   in std_logic := '1';
		q:       out std_logic_vector(DATA_WIDTH - 1 downto 0)
	);
end rom_mf;

architecture syn of rom_mf is
	signal sub_wire0: std_logic_vector (DATA_WIDTH - 1 downto 0);

	component altsyncram
	generic (
		clock_enable_input_a:   string;
		clock_enable_output_a:  string;
		init_file:              string;
		intended_device_family: string;
		lpm_hint:               string;
		lpm_type:               string;
		numwords_a:             natural;
		operation_mode:         string;
		outdata_aclr_a:         string;
		outdata_reg_a:          string;
		widthad_a:              natural;
		width_a:                natural;
		width_byteena_a:        natural
	);
	port (
		address_a: in std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
		clock0:    in std_logic;
		q_a:       out std_logic_vector(DATA_WIDTH - 1 downto 0)
	);
	end component;

begin
	q <= sub_wire0(DATA_WIDTH - 1 downto 0);

	altsyncram_component : altsyncram
	generic map (
		clock_enable_input_a   => "bypass",
		clock_enable_output_a  => "bypass",
		init_file              => INIT_FILE,
		intended_device_family => "cyclone ii",
		lpm_hint               => "enable_runtime_mod=yes,instance_name=rom1",
		lpm_type               => "altsyncram",
		numwords_a             => DEPTH,
		operation_mode         => "rom",
		outdata_aclr_a         => "none",
		outdata_reg_a          => "clock0",
		widthad_a              => ADDRESS_WIDTH,
		width_a                => DATA_WIDTH,
		width_byteena_a        => 1
	)
	port map (
		address_a => address,
		clock0    => clock,
		q_a       => sub_wire0
	);
end syn;
