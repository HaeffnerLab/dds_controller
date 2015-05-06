-- Constants for communicating with the pulser
library ieee;
use ieee.std_logic_1164.all;

package pulser_lib is
	constant BUS_ADDR_WIDTH:  natural := 3;
	constant LED_ARRAY_WIDTH: natural := 8;
end package;
