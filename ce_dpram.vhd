----------------------------------------------------------------------------------
-- _____
--/  __ \
--| /  \/_ __ ___  _ __  _   _ ___
--| |   | '__/ _ \| '_ \| | | / __|
--| \__/\ | | (_) | | | | |_| \__ \
-- \____/_|  \___/|_| |_|\__,_|___/
--
-- _____ _           _                   _
--|  ___| |         | |                 (_)
--| |__ | | ___  ___| |_ _ __ ___  _ __  _  ___ ___
--|  __|| |/ _ \/ __| __| '__/ _ \| '_ \| |/ __/ __|
--| |___| |  __/ (__| |_| | | (_) | | | | | (__\__ \
--\____/|_|\___|\___|\__|_|  \___/|_| |_|_|\___|___/
--
-- Designer       : Ben Horton
-- Create Date    : 11/05/2017 22:17:02
-- Design Name    :
-- Module Name    : ce_dpram - Behavioral
-- Project Name   : Cronus IP module
-- Target Devices :
-- Description    : Simple DP RAM module
--
-- Revision       : 0.01 - File Created
-- Additional Comments:
--
---------------------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library cronus_lib;
use cronus_lib.ce_types_pkg.all;
use cronus_lib.ce_functions_pkg.all;


entity ce_dpram is
   generic(
            RAM_DEPTH           : natural range 0 to MAX_16_UNSIGNED -- defines the depth of the RAM
         );
   port (
            clk_in               : in  std_logic;
            -- Port A
            port_a_we            : in  std_logic;
            port_a_adr           : in  unsigned;
            port_a_data_in       : in  std_logic_vector;
            port_a_data_out      : out std_logic_vector;
            -- Port B
            port_b_we            : in  std_logic;
            port_b_adr           : in  unsigned;
            port_b_data_in       : in  std_logic_vector;
            port_b_data_out      : out std_logic_vector
         );
end ce_dpram;

architecture rtl of ce_dpram is

   -- define a RAM type
   type ram_type is array (RAM_DEPTH - 1 downto 0) of std_logic_vector(port_a_data_in'range);
   -- Define RAM
   shared variable ram     : ram_type := (others => (others => '0'));

begin

   -- PORT A
   port_a : process
   begin
      wait until rising_edge(clk_in);
      port_a_data_out <= ram(to_integer(port_a_adr));
      if port_a_we = '1' then
         ram(to_integer(port_a_adr)) := port_a_data_in;
      end if;
   end process;

   -- PORT B
   port_b : process
   begin
      wait until rising_edge(clk_in);
      port_b_data_out <= ram(to_integer(port_b_adr));
      if port_b_we = '1' then
         ram(to_integer(port_b_adr)) := port_b_data_in;
      end if;
   end process;

   gen_reports : process
   variable port_a_adr_int : integer := to_integer(port_a_adr);
   begin
      wait until rising_edge(clk_in);
      if (port_a_adr = port_b_adr) and port_a_we = '1' and port_b_we = '1' then
         report"concurrent writing to RAM cell at address " & integer'image(port_a_adr_int) severity warning;
      end if;

   end process;

end rtl;