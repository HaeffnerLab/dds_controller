-- Genericized version of an Altera MegaFunction file
library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.all;

entity pll_mf is
	generic (
		MULTIPLIER: natural := 4
	);
	port (
		inclk0: in std_logic  := '0';
		c0: out std_logic 
	);
end pll_mf;

architecture syn of pll_mf is

signal sub_wire0: std_logic_vector (5 downto 0);
signal sub_wire1: std_logic ;
signal sub_wire2: std_logic ;
signal sub_wire3: std_logic_vector (1 downto 0);
signal sub_wire4_bv: bit_vector (0 downto 0);
signal sub_wire4: std_logic_vector (0 downto 0);

component altpll
	generic (
		clk0_divide_by: natural;
		clk0_duty_cycle: natural;
		clk0_multiply_by: natural;
		clk0_phase_shift: string;
		compensate_clock: string;
		inclk0_input_frequency: natural;
		intended_device_family: string;
		lpm_hint: string;
		lpm_type: string;
		operation_mode: string;
		port_activeclock: string;
		port_areset: string;
		port_clkbad0: string;
		port_clkbad1: string;
		port_clkloss: string;
		port_clkswitch: string;
		port_configupdate: string;
		port_fbin: string;
		port_inclk0: string;
		port_inclk1: string;
		port_locked: string;
		port_pfdena: string;
		port_phasecounterselect: string;
		port_phasedone: string;
		port_phasestep: string;
		port_phaseupdown: string;
		port_pllena: string;
		port_scanaclr: string;
		port_scanclk: string;
		port_scanclkena: string;
		port_scandata: string;
		port_scandataout: string;
		port_scandone: string;
		port_scanread: string;
		port_scanwrite: string;
		port_clk0: string;
		port_clk1: string;
		port_clk2: string;
		port_clk3: string;
		port_clk4: string;
		port_clk5: string;
		port_clkena0: string;
		port_clkena1: string;
		port_clkena2: string;
		port_clkena3: string;
		port_clkena4: string;
		port_clkena5: string;
		port_extclk0: string;
		port_extclk1: string;
		port_extclk2: string;
		port_extclk3: string
	);
	port (
		clk: out std_logic_vector (5 downto 0);
		inclk: in std_logic_vector (1 downto 0)
	);
end component;

begin
	sub_wire4_bv(0 downto 0) <= "0";
	sub_wire4    <= to_stdlogicvector(sub_wire4_bv);
	sub_wire1    <= sub_wire0(0);
	c0    <= sub_wire1;
	sub_wire2    <= inclk0;
	sub_wire3    <= sub_wire4(0 downto 0) & sub_wire2;

	altpll_component : altpll

	generic map (
		clk0_divide_by => 1,
		clk0_duty_cycle => 50,
		clk0_multiply_by => MULTIPLIER,
		clk0_phase_shift => "0",
		compensate_clock => "clk0",
		inclk0_input_frequency => 40000,
		intended_device_family => "cyclone ii",
		lpm_hint => "cbx_module_prefix=pll_mf",
		lpm_type => "altpll",
		operation_mode => "normal",
		port_activeclock => "port_unused",
		port_areset => "port_unused",
		port_clkbad0 => "port_unused",
		port_clkbad1 => "port_unused",
		port_clkloss => "port_unused",
		port_clkswitch => "port_unused",
		port_configupdate => "port_unused",
		port_fbin => "port_unused",
		port_inclk0 => "port_used",
		port_inclk1 => "port_unused",
		port_locked => "port_unused",
		port_pfdena => "port_unused",
		port_phasecounterselect => "port_unused",
		port_phasedone => "port_unused",
		port_phasestep => "port_unused",
		port_phaseupdown => "port_unused",
		port_pllena => "port_unused",
		port_scanaclr => "port_unused",
		port_scanclk => "port_unused",
		port_scanclkena => "port_unused",
		port_scandata => "port_unused",
		port_scandataout => "port_unused",
		port_scandone => "port_unused",
		port_scanread => "port_unused",
		port_scanwrite => "port_unused",
		port_clk0 => "port_used",
		port_clk1 => "port_unused",
		port_clk2 => "port_unused",
		port_clk3 => "port_unused",
		port_clk4 => "port_unused",
		port_clk5 => "port_unused",
		port_clkena0 => "port_unused",
		port_clkena1 => "port_unused",
		port_clkena2 => "port_unused",
		port_clkena3 => "port_unused",
		port_clkena4 => "port_unused",
		port_clkena5 => "port_unused",
		port_extclk0 => "port_unused",
		port_extclk1 => "port_unused",
		port_extclk2 => "port_unused",
		port_extclk3 => "port_unused"
	)
	port map (
		inclk => sub_wire3,
		clk => sub_wire0
	);

end syn;
