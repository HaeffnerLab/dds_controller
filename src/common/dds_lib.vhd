-- Constants for the AD9910
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package dds_lib is
	-- Width of a serial instruction to the DDS
	constant DDS_ADDR_WIDTH: natural := 8;
	constant DDS_WORD_WIDTH: natural := 32;
	-- Number of profile select bits
	constant DDS_PROFILE_SEL_WIDTH: natural := 3;
	-- Parallel port width
	constant DDS_PL_PORT_WIDTH: natural := 16;
	-- Parallel port data destination
	constant DDS_PL_ADDR_WIDTH: natural := 2;
	-- Frequency tuning word address
	constant DDS_FTW_ADDR_BYTE: std_logic_vector(DDS_ADDR_WIDTH - 1 downto 0)
			:= x"07";
	-- Address to read/write DDS RAM
	constant DDS_RAM_ADDR_BYTE: std_logic_vector(DDS_ADDR_WIDTH - 1 downto 0)
			:= x"16";
	-- Profile constant to write entire RAM memory block at once
    constant DDS_RAM_INIT_PROFILE: std_logic_vector(2 * DDS_WORD_WIDTH +
            DDS_ADDR_WIDTH - 1 downto 0) :=
            x"0E000000FFC0000000";

	-- Reusable procedure to simply write a constant (such as an instruction)
    -- to the DDS over the serial port, then stop.
    procedure write_constant (
		P2S_WIDTH:  in natural;
		DATA_WIDTH: in natural;
		data:       in std_logic_vector;
		signal p2s_reset:  out std_logic;
		signal p2s_len:    out natural;
		signal p2s_pdi:    out std_logic_vector;
		signal p2s_finish: in std_logic;
		variable finish:   out boolean
    );

	-- Reusable procedure to write the entire contents of an Altera ROM
    -- component over the serial port in sequence, then stop.
    procedure write_from_rom (
		P2S_WIDTH:  in natural;
		DATA_WIDTH: in natural;
		ADDR_WIDTH: in natural;
		DATA_DEPTH: in natural;
		signal p2s_reset:  out std_logic;
		signal p2s_len:    out natural;
		signal p2s_pdi:    out std_logic_vector;
		signal p2s_finish: in std_logic;
		signal rom_addr:   out std_logic_vector;
		signal rom_q:      in std_logic_vector;
		variable addr_count: inout natural;
		variable finish:     inout boolean
    );
end package;

package body dds_lib is
	-- Reusable procedure to simply write a constant (such as an instruction)
    -- to the DDS over the serial port, then stop.
    procedure write_constant (
		P2S_WIDTH:  in natural;
		DATA_WIDTH: in natural;
		data:       in std_logic_vector;
		signal p2s_reset:  out std_logic;
		signal p2s_len:    out natural;
		signal p2s_pdi:    out std_logic_vector;
		signal p2s_finish: in std_logic;
		variable finish:   out boolean
    ) is
    begin
        if p2s_finish = '1' then
            p2s_reset <= '1';
            finish    := true;
        else
            p2s_reset <= '0';
            p2s_len   <= DATA_WIDTH;
            p2s_pdi(P2S_WIDTH - 1 downto P2S_WIDTH - DATA_WIDTH) <= data;
            finish := false;
        end if;
    end procedure;

    procedure write_from_rom (
		P2S_WIDTH:  in natural;
		DATA_WIDTH: in natural;
		ADDR_WIDTH: in natural;
		DATA_DEPTH: in natural;
		signal p2s_reset:  out std_logic;
		signal p2s_len:    out natural;
		signal p2s_pdi:    out std_logic_vector;
		signal p2s_finish: in std_logic;
		signal rom_addr:   out std_logic_vector;
		signal rom_q:      in std_logic_vector;
		variable addr_count: inout natural;
		variable finish:     inout boolean
    ) is
    begin
        p2s_reset <= '0';
        p2s_len   <= DATA_WIDTH;
        p2s_pdi(P2S_WIDTH - 1 downto P2S_WIDTH - DATA_WIDTH) <= rom_q;
        if addr_count = DATA_DEPTH - 1 then
            -- Can't have an address greater than depth
            rom_addr <= (others => '0');
            if p2s_finish = '1' then
                p2s_reset <= '1';
                addr_count := 0;
                finish := true;
            else
                finish := false;
            end if;
        elsif finish = false then
            rom_addr <= std_logic_vector(to_unsigned(addr_count + 1,
                    ADDR_WIDTH));
            if p2s_finish = '1' then
                addr_count := addr_count + 1;
            end if;
            finish := false;
        end if;
    end procedure;
end dds_lib;
