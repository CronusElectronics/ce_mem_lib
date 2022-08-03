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
-- Create Date    : 31.04.2017 18:07:32
-- Design Name    : 
-- Module Name    : ce_functions_pkg
-- Project Name   : Cronus Common Module
-- Target Devices : None
-- Description    :
--
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.math_real.all;

library cronus_lib;
use cronus_lib.ce_types_pkg.all;

package ce_functions_pkg is

   -- Counter contrl signals
   type COUNTER_CTRL_TYPE is (rst, inc, dec, hold, load);

   function integer_counter(counter_ctrl : COUNTER_CTRL_TYPE; counter : integer; load_val : integer; COUNT_MAX : integer := integer'high; COUNT_MIN : integer := integer'low)  return integer;
   
   function natural_counter(counter_ctrl : COUNTER_CTRL_TYPE; counter : natural; load_val : natural; COUNT_MAX : natural := natural'high)  return natural;

   function raise_to_power (base, index:integer) return integer;
   
   function number_bits (value:integer) return integer;

   function nibble_to_ascii (value : std_logic_vector(3 downto 0)) return std_logic_vector;
   function nibble_to_ascii (value : unsigned(3 downto 0)) return std_logic_vector;
   function nibble_to_ascii (value : signed(3 downto 0)) return std_logic_vector;

   function word_to_ascii (value : std_logic_vector; nibble_idx : natural := 0) return std_logic_vector;
   function word_to_ascii (value : unsigned;         nibble_idx : natural := 0) return std_logic_vector;
   function word_to_ascii (value : signed;           nibble_idx : natural := 0) return std_logic_vector;

   function ascii_to_nibble (value : std_logic_vector(7 downto 0)) return std_logic_vector;

   -- Functions to convert between an array of vectors to a single larger vector and back
   -- Big endian 
   function vector2regs_be(vector : std_logic_vector) return SLV8_ARRAY;
   function vector2regs_be(vector : unsigned) return SLV8_ARRAY;
   function regs2vector_be (regs : SLV8_ARRAY) return std_logic_vector;
   function regs2vector_be (regs : SLV8_ARRAY) return unsigned;
   -- Little endian 
   function vector2regs_le(vector : std_logic_vector) return SLV8_ARRAY;
   function vector2regs_le(vector : unsigned) return SLV8_ARRAY;
   function regs2vector_le (regs : SLV8_ARRAY) return std_logic_vector;
   function regs2vector_le (regs : SLV8_ARRAY) return unsigned;

   -- Depreciated do not use, they are kept for legacy reasons
   function regs2vector_little(regs : SLV8_ARRAY) return std_logic_vector;
   function regs2vector_little(regs : SLV8_ARRAY) return unsigned;
   function vector2regs_little(vector : std_logic_vector) return SLV8_ARRAY;
   function vector2regs_little(vector : unsigned) return SLV8_ARRAY;

   function rand_slv(len : integer) return std_logic_vector;
   function rand_int(min_val, max_val : integer) return integer;
   function rand_time(min_val, max_val : time; unit : time := ns) return time;

end ce_functions_pkg;

package body ce_functions_pkg is   

   function integer_counter(counter_ctrl : COUNTER_CTRL_TYPE; counter : integer; load_val : integer; COUNT_MAX : integer:= integer'high; COUNT_MIN : integer := integer'low)  return integer is
      variable res : integer;
   begin 
      if counter_ctrl = rst then
         res := 0;
      elsif counter_ctrl = inc then      
         if counter /= COUNT_MAX then
            res := counter + 1;
         else
            res := 0;
         end if;
      elsif counter_ctrl = dec then  
         if counter /= COUNT_MIN then    
            res := counter - 1;
         end if;
      elsif counter_ctrl = load then
         res := load_val;
      else
         res := counter;
      end if;
         return res;
   end integer_counter; 

   function natural_counter(counter_ctrl : COUNTER_CTRL_TYPE; counter : natural; load_val : natural; COUNT_MAX : natural := natural'high)  return natural is
      variable res : natural;
   begin 
      if counter_ctrl = rst then
         res := 0;
      elsif counter_ctrl = inc then      
         if counter /= COUNT_MAX then
           res := counter + 1;
         else
           res := 0;
         end if;
      elsif counter_ctrl = dec then  
         if counter /= 0 then    
            res := counter - 1;
         end if;
       elsif counter_ctrl = load then
            res := load_val;
         else
            res := counter;
         end if;
         return res;
   end natural_counter;

   function raise_to_power(base, index:integer) return integer is  
      variable temp:integer;
   begin             
      temp:=base;   
      --handle zero-th power
      if (index=0) then
         temp:=1;      
         --handle unitary power        
      elsif (index=1) then
         temp:=temp;
      else             
         --powers greater than 1 
         for n in 1 to index-1 loop
            temp:=temp*base;
         end loop;                 
      end if;
      return temp;
   end function raise_to_power;       
   
   
   function number_bits(value:natural) return natural is
      variable bits:integer;
      variable division:integer;
   begin
      bits:=0;
      division:=value;
      
      --check for 1
      if division <= 1 then
         bits:=1;
      else   
         -- all other values  
         while division>1 loop
            bits:=bits+1;
            --check for even values
            if (division rem 2)=0 then
               division:=(division/2);
            else  
               --correct for odd values
               division:=(division/2)+1;  
            end if;
         end loop;                
      end if;
      
      return bits;
   end function number_bits;

   function nibble_to_ascii (value : std_logic_vector(3 downto 0)) return std_logic_vector is
      variable res : std_logic_vector(7 downto 0);
   begin

      case value is
         when x"A" =>
            res   := ASCII_A;
         when x"B" =>
            res   := ASCII_B;
         when x"C" =>
            res   := ASCII_C;
         when x"D" =>
            res   := ASCII_D;
         when x"E" =>
            res   := ASCII_E;
         when x"F" =>
            res   := ASCII_F;
         when others =>
            res   := x"3" & value;
      end case;
      
      return res;
   end nibble_to_ascii;

   function nibble_to_ascii (value : unsigned(3 downto 0)) return std_logic_vector is
      variable res : std_logic_vector(7 downto 0);
   begin

      case value is
         when x"A" =>
            res   := ASCII_A;
         when x"B" =>
            res   := ASCII_B;
         when x"C" =>
            res   := ASCII_C;
         when x"D" =>
            res   := ASCII_D;
         when x"E" =>
            res   := ASCII_E;
         when x"F" =>
            res   := ASCII_F;
         when others =>
            res   := x"3" & std_logic_vector(value);
      end case;
      
      return res;
   end nibble_to_ascii;

   function nibble_to_ascii (value : signed(3 downto 0)) return std_logic_vector is
      variable res : std_logic_vector(7 downto 0);
   begin

      case value is
         when x"A" =>
            res   := ASCII_A;
         when x"B" =>
            res   := ASCII_B;
         when x"C" =>
            res   := ASCII_C;
         when x"D" =>
            res   := ASCII_D;
         when x"E" =>
            res   := ASCII_E;
         when x"F" =>
            res   := ASCII_F;
         when others =>
            res   := x"3" & std_logic_vector(value);
      end case;
      
      return res;
   end nibble_to_ascii;

   function ascii_to_nibble (value : std_logic_vector(7 downto 0)) return std_logic_vector is
      variable res : std_logic_vector(3 downto 0);
   begin
      case value is
         when ASCII_A =>
            res   := x"A";
         when ASCII_B =>
            res   := x"B";
         when ASCII_C =>
            res   := x"C";
         when ASCII_D =>
            res   := x"D";
         when ASCII_E =>
            res   := x"E";
         when ASCII_F =>
            res   := x"F";
         when others =>
            res   := value(3 downto 0);
      end case;

      return res;
   end ascii_to_nibble;

   function word_to_ascii (value : std_logic_vector; nibble_idx : natural := 0) return std_logic_vector is
      variable res      : std_logic_vector(7 downto 0);
      variable nibble   : std_logic_vector(3 downto 0);
   begin

      nibble := value(nibble_idx + 3 downto nibble_idx);

      case nibble is
         when x"A" =>
            res   := ASCII_A;
         when x"B" =>
            res   := ASCII_B;
         when x"C" =>
            res   := ASCII_C;
         when x"D" =>
            res   := ASCII_D;
         when x"E" =>
            res   := ASCII_E;
         when x"F" =>
            res   := ASCII_F;
         when others =>
            res   := x"3" & nibble;
      end case;
      
      return res;
   end word_to_ascii;

   function word_to_ascii (value : unsigned; nibble_idx : natural := 0) return std_logic_vector is
      variable res      : std_logic_vector(7 downto 0);
      variable nibble   : std_logic_vector(3 downto 0);
   begin

      nibble := std_logic_vector(value(nibble_idx + 3 downto nibble_idx));

      case nibble is
         when x"A" =>
            res   := ASCII_A;
         when x"B" =>
            res   := ASCII_B;
         when x"C" =>
            res   := ASCII_C;
         when x"D" =>
            res   := ASCII_D;
         when x"E" =>
            res   := ASCII_E;
         when x"F" =>
            res   := ASCII_F;
         when others =>
            res   := x"3" & nibble;
      end case;
      
      return res;
   end word_to_ascii;

   function word_to_ascii (value : signed; nibble_idx : natural := 0) return std_logic_vector is
      variable res      : std_logic_vector(7 downto 0);
      variable nibble   : std_logic_vector(3 downto 0);
   begin

      nibble := std_logic_vector(value(nibble_idx + 3 downto nibble_idx));

      case nibble is
         when x"A" =>
            res   := ASCII_A;
         when x"B" =>
            res   := ASCII_B;
         when x"C" =>
            res   := ASCII_C;
         when x"D" =>
            res   := ASCII_D;
         when x"E" =>
            res   := ASCII_E;
         when x"F" =>
            res   := ASCII_F;
         when others =>
            res   := x"3" & nibble;
      end case;
      
      return res;
   end word_to_ascii;

   -- Function to extract a vector (n * 8 bits) from an array of vectors (length n), the MBbyte
   -- is extracted from the highest address
   function regs2vector_be (regs : SLV8_ARRAY) return std_logic_vector is
      variable res : std_logic_vector((regs'length * 8) - 1 downto 0);
   begin
      for ii in 0 to regs'length - 1 loop
         -- Take the lowest register and write it to the lowest bit slice
         res(((ii + 1) * 8) - 1 downto (ii * 8)) := regs(regs'low + ii);
      end loop;
      
      return res;
   end regs2vector_be;

   -- Function to extract a vector (n * 8 bits) from an array of vectors (length n), the MBbyte
   -- is extracted from the highest address
   function regs2vector_be (regs : SLV8_ARRAY) return unsigned is
      variable res : unsigned((regs'length * 8) - 1 downto 0);
   begin
      for ii in 0 to regs'length - 1 loop
         -- Take the lowest register and write it to the lowest bit slice
         res(((ii + 1) * 8) - 1 downto (ii * 8)) := unsigned(regs(regs'low + ii));
      end loop;
      
      return res;
   end regs2vector_be;

   function vector2regs_be(vector : std_logic_vector) return SLV8_ARRAY is
      variable res : SLV8_ARRAY((vector'length / 8) - 1 downto 0);
   begin
      for ii in 0 to (vector'length / 8) - 1 loop
         res(ii) := vector((ii + 1) * 8 - 1 downto (ii * 8));
      end loop;
      
      return res;
   end vector2regs_be;

   function vector2regs_be(vector : unsigned) return SLV8_ARRAY is
      variable res : SLV8_ARRAY((vector'length / 8) - 1 downto 0);
   begin
      for ii in 0 to (vector'length / 8) - 1 loop
         res(ii) := std_logic_vector(vector((ii + 1) * 8 - 1 downto (ii * 8)));
      end loop;
      
      return res;
   end vector2regs_be;

   -- Function to extract a vector (n * 8 bits) from an array of vectors (length n), the MBbyte
   -- is extracted from the highest address
   function regs2vector_le (regs : SLV8_ARRAY) return std_logic_vector is
      variable res : std_logic_vector((regs'length * 8) - 1 downto 0);
   begin
      for ii in 0 to regs'length - 1 loop
         -- Take the lowest register and write it to the lowest bit slice
         res((ii + 1) * 8 - 1 downto (ii * 8)) := regs(regs'high - ii);
      end loop;
      
      return res;
   end regs2vector_le;

   -- Function to extract a vector (n * 8 bits) from an array of vectors (length n), the MBbyte
   -- is extracted from the highest address
   function regs2vector_le (regs : SLV8_ARRAY) return unsigned is
      variable res : unsigned((regs'length * 8) - 1 downto 0);
   begin
      for ii in 0 to regs'length - 1 loop
         -- Take the lowest register and write it to the lowest bit slice
         res((ii + 1) * 8 - 1 downto (ii * 8)) := unsigned(regs(regs'high - ii));
      end loop;
      
      return res;
   end regs2vector_le;

   function vector2regs_le(vector : std_logic_vector) return SLV8_ARRAY is
      variable res : SLV8_ARRAY((vector'length / 8) - 1 downto 0);
   begin
      for ii in 0 to (vector'length / 8) - 1 loop
         res(((vector'length / 8) - 1) - ii) := vector((ii + 1) * 8 - 1 downto (ii * 8));
      end loop;
      
      return res;
   end vector2regs_le;

   function vector2regs_le(vector : unsigned) return SLV8_ARRAY is
      variable res : SLV8_ARRAY((vector'length / 8) - 1 downto 0);
   begin
      for ii in 0 to (vector'length / 8) - 1 loop
         res(((vector'length / 8) - 1) - ii) := std_logic_vector(vector((ii + 1) * 8 - 1 downto (ii * 8)));
      end loop;
      
      return res;
   end vector2regs_le;

   ----------------------------------------------------------------------
   -- These functions are wrong and do not correctly handle the endian
   -- however I need to preserve them to for legacy (caleva)
   ----------------------------------------------------------------------
   function vector2regs_little(vector : std_logic_vector) return SLV8_ARRAY is
      variable res : SLV8_ARRAY((vector'length / 8) - 1 downto 0);
   begin
      for ii in 0 to (vector'length / 8) - 1 loop
         res(ii) := vector((ii + 1) * 8 - 1 downto (ii * 8));
      end loop;
      
      return res;
   end vector2regs_little;

   function vector2regs_little(vector : unsigned) return SLV8_ARRAY is
      variable res : SLV8_ARRAY((vector'length / 8) - 1 downto 0);
   begin
      for ii in 0 to (vector'length / 8) - 1 loop
         res(ii) := std_logic_vector(vector((ii + 1) * 8 - 1 downto (ii * 8)));
      end loop;
      
      return res;
   end vector2regs_little;

   -- Function to extract a vector (n * 8 bits) from an array of vectors (length n), the MBbyte
   -- is extracted from the lowest address
   function regs2vector_little (regs : SLV8_ARRAY) return std_logic_vector is
      variable res : std_logic_vector((regs'length * 8) - 1 downto 0);
   begin
      for ii in 0 to regs'length - 1 loop
         res((ii + 1) * 8 - 1 downto (ii * 8)) := regs(regs'high - ii);
      end loop;
      
      return res;
   end regs2vector_little;

   -- Function to extract a vector (n * 8 bits) from an array of vectors (length n), the MBbyte
   -- is extracted from the lowest register address
   function regs2vector_little (regs : SLV8_ARRAY) return unsigned is
      variable res : unsigned((regs'length * 8) - 1 downto 0);
   begin
      for ii in 0 to regs'length - 1 loop
         res((ii + 1) * 8 - 1 downto (ii * 8)) := unsigned(regs(regs'high - ii));
      end loop;
      
      return res;
   end regs2vector_little;


   function rand_slv(len : integer) return std_logic_vector is
      variable r   : real;
      variable seed1, seed2 : positive := 1;
      variable slv : std_logic_vector(len - 1 downto 0);
   begin
       uniform(seed1, seed2, r);
       r := r * real(2**len);
       slv := std_logic_vector(to_unsigned(integer(r), len));
     return slv;
   end function;

   function rand_int(min_val, max_val : integer) return integer is
      variable seed1, seed2 : positive := 1;
      variable r : real;
   begin
      uniform(seed1, seed2, r);
      return integer(round(r * real(max_val - min_val + 1) + real(min_val) - 0.5));
   end function;

   function rand_time(min_val, max_val : time; unit : time := ns) return time is
      variable r, r_scaled, min_real, max_real : real;
      variable seed1, seed2 : positive := 1;
   begin
      uniform(seed1, seed2, r);
      min_real := real(min_val / unit);
      max_real := real(max_val / unit);
      r_scaled := r * (max_real - min_real) + min_real;
      return real(r_scaled) * unit;
   end function;

end ce_functions_pkg;