LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.all;

ENTITY ram_mf IS
	PORT (
		data:      IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		rdaddress: IN STD_LOGIC_VECTOR (9 DOWNTO 0);
		rdclock:   IN STD_LOGIC ;
		wraddress: IN STD_LOGIC_VECTOR (11 DOWNTO 0);
		wrclock:   IN STD_LOGIC  := '1';
		wren:      IN STD_LOGIC  := '0';
		q:         OUT STD_LOGIC_VECTOR (63 DOWNTO 0)
	);
END ram_mf;

ARCHITECTURE SYN OF ram_mf IS

	SIGNAL sub_wire0: STD_LOGIC_VECTOR (63 DOWNTO 0);

	COMPONENT altsyncram
	GENERIC (
		address_reg_b:          STRING;
		clock_enable_input_a:   STRING;
		clock_enable_input_b:   STRING;
		clock_enable_output_a:  STRING;
		clock_enable_output_b:  STRING;
		intended_device_family: STRING;
		lpm_type:               STRING;
		numwords_a:             NATURAL;
		numwords_b:             NATURAL;
		operation_mode:         STRING;
		outdata_aclr_b:         STRING;
		outdata_reg_b:          STRING;
		power_up_uninitialized: STRING;
		widthad_a:              NATURAL;
		widthad_b:              NATURAL;
		width_a:                NATURAL;
		width_b:                NATURAL;
		width_byteena_a:        NATURAL
	);
	PORT (
		address_a: IN STD_LOGIC_VECTOR (11 DOWNTO 0);
		clock0:    IN STD_LOGIC ;
		data_a:    IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		q_b:       OUT STD_LOGIC_VECTOR (63 DOWNTO 0);
		wren_a:    IN STD_LOGIC ;
		address_b: IN STD_LOGIC_VECTOR (9 DOWNTO 0);
		clock1:    IN STD_LOGIC
	);
	END COMPONENT;

	BEGIN
	q <= sub_wire0(63 DOWNTO 0);

	altsyncram_component: altsyncram
	GENERIC MAP (
		address_reg_b          => "CLOCK1",
		clock_enable_input_a   => "BYPASS",
		clock_enable_input_b   => "BYPASS",
		clock_enable_output_a  => "BYPASS",
		clock_enable_output_b  => "BYPASS",
		intended_device_family => "Cyclone II",
		lpm_type               => "altsyncram",
		numwords_a             => 4096,
		numwords_b             => 1024,
		operation_mode         => "DUAL_PORT",
		outdata_aclr_b         => "NONE",
		outdata_reg_b          => "CLOCK1",
		power_up_uninitialized => "FALSE",
		widthad_a              => 12,
		widthad_b              => 10,
		width_a                => 16,
		width_b                => 64,
		width_byteena_a        => 1
	)
	PORT MAP (
		address_a => wraddress,
		clock0    => wrclock,
		data_a    => data,
		wren_a    => wren,
		address_b => rdaddress,
		clock1    => rdclock,
		q_b       => sub_wire0
	);

END SYN;
