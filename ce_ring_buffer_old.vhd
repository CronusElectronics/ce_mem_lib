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

library ce_mem_lib;

library cronus_lib;
use cronus_lib.ce_types_pkg.all;
use cronus_lib.ce_functions_pkg.all;


entity ce_ring_buffer is
   generic(
            RAM_DEPTH            : natural range 0 to MAX_24_UNSIGNED; -- defines the depth of the RAM
            NUM_PKT_VECT_SIZE    : natural := 16
         );
   port (
            clk_in               : in  std_logic;
            reset_in             : in  std_logic;
            -- Write Port
            write_stream_in      : in  AXI_STREAM_R;
            write_discard_in     : in  std_logic;
            write_stream_rfd_out : out std_logic;
            -- Read Port
            read_stream_out      : out  AXI_STREAM_R;
            read_stream_rfd_in   : in  std_logic;
            -- buffer stats
            num_pkts_out         : out unsigned(NUM_PKT_VECT_SIZE - 1 downto 0)
         );
end ce_ring_buffer;

architecture rtl of ce_ring_buffer is

   constant MAX_PACKETS          : positive := raise_to_power(2, NUM_PKT_VECT_SIZE) - 1;
   constant RAM_ADR_LEN          : positive := number_bits(RAM_DEPTH);
   constant READ_INTER_PKT_GAP   : positive := 3;

   signal write_ptr_ctrl      : COUNTER_CTRL_TYPE;
   signal write_ptr           : natural range 0 to RAM_DEPTH - 1;
   signal write_ptr_saved     : natural range 0 to RAM_DEPTH - 1;

   signal read_ptr_ctrl       : COUNTER_CTRL_TYPE;
   signal read_ptr            : natural range 0 to RAM_DEPTH - 1;

   signal num_pkt_count_ctrl  : COUNTER_CTRL_TYPE;
   signal num_pkt_count       : natural range 0 to MAX_PACKETS - 1;

   signal pkt_gap_count_ctrl  : COUNTER_CTRL_TYPE;
   signal pkt_gap_count       : natural range 0 to READ_INTER_PKT_GAP - 1;

   -- Port A
   signal port_a_we           : std_logic;
   signal port_a_adr          : unsigned(RAM_ADR_LEN - 1 downto 0);
   signal port_a_data_in      : std_logic_vector(write_stream_in.tdata'length downto 0);
   signal port_a_data_out     : std_logic_vector(write_stream_in.tdata'length downto 0);
   -- Port B
   signal port_b_we           : std_logic;
   signal port_b_adr          : unsigned(RAM_ADR_LEN - 1 downto 0);
   signal port_b_data_out     : std_logic_vector(write_stream_in.tdata'length downto 0);
   signal port_b_data_in      : std_logic_vector(write_stream_in.tdata'length downto 0) := (others => '0');

   signal inter_pkt_gap       : std_logic;

   signal save_write_ptr      : std_logic;
   signal discard_pkt         : std_logic := '0';

   signal no_write_complete   : std_logic;

   alias read_tlast_flag is port_b_data_out(port_b_data_out'left);

begin

   --Control the write pointer
   control_write_ptr : process(reset_in, write_discard_in, write_stream_in)
   begin
      if reset_in = '1' then
         write_ptr_ctrl <= rst;
      elsif (write_discard_in = '1' or discard_pkt = '1') and write_stream_in.tlast = '1' then
         write_ptr_ctrl <= load;
      elsif write_stream_in.tvalid = '1' then
         write_ptr_ctrl <= inc;
      else
         write_ptr_ctrl <= hold;
      end if;
   end process;

   --Control the read pointer
   control_read_ptr : process(reset_in, num_pkt_count, read_stream_rfd_in, inter_pkt_gap, read_tlast_flag)
   begin
      if reset_in = '1' then
         read_ptr_ctrl  <= rst;
      -- Increment the read pointer when ever the destination is ready and the 
      elsif num_pkt_count > 0 and read_stream_rfd_in = '1' and inter_pkt_gap = '0' and read_tlast_flag = '0' then
         read_ptr_ctrl  <= inc;
      else
         read_ptr_ctrl  <= hold;
      end if;
   end process;

   --Control the inter packet gap
   control_pkt_gap : process(reset_in, read_tlast_flag, pkt_gap_count)
   begin
      inter_pkt_gap           <= '1';
      if reset_in = '1' then
         pkt_gap_count_ctrl   <= rst;
      elsif read_tlast_flag = '1' then
         pkt_gap_count_ctrl   <= rst;
         inter_pkt_gap        <= '0';
      elsif pkt_gap_count < READ_INTER_PKT_GAP - 1 then
         pkt_gap_count_ctrl   <= inc;
      else
         inter_pkt_gap        <= '0';
         pkt_gap_count_ctrl   <= hold;
      end if;
   end process;

   --Control the packet counter
   control_pkt_counter : process(reset_in, write_stream_in, read_tlast_flag, read_stream_rfd_in, write_discard_in)
   begin
      if reset_in = '1' then
         num_pkt_count_ctrl <= rst;
      -- We want to increment the packet counter when the writing port completes the packet by setting the .tlast flag.
      -- This needs to be further qualified by the .tvalid flag as well as the last opatunity for the sending interface to 
      -- discard the packet
      elsif write_stream_in.tvalid = '1' and write_stream_in.tlast = '1' and write_discard_in = '0' and discard_pkt = '0' then
         num_pkt_count_ctrl <= inc;
      -- We want to decrement the packet counter when the reading port has read a complete packet which is signified by the extra bit added to the RAM.
      -- We need to qualify that this last word was read by the destination by qulaifying with the ready flag
      elsif read_tlast_flag = '1' and read_stream_rfd_in = '1' then
         num_pkt_count_ctrl <= dec;
      else
         num_pkt_count_ctrl <= hold;
      end if;
   end process;

   -- Generate the counters
   counter_gen : process
   begin
      wait until rising_edge(clk_in);
      read_ptr       <= natural_counter(read_ptr_ctrl,      read_ptr,      0,                RAM_DEPTH - 1); -- We do not need the load function for the read pointer
      write_ptr      <= natural_counter(write_ptr_ctrl,     write_ptr,     write_ptr_saved,  RAM_DEPTH - 1); -- Use the load function when we need to discard the current packet
      num_pkt_count  <= natural_counter(num_pkt_count_ctrl, num_pkt_count, 0,                MAX_PACKETS - 1);
      pkt_gap_count  <= natural_counter(pkt_gap_count_ctrl, pkt_gap_count, 0,                READ_INTER_PKT_GAP - 1);

      save_write_ptr <= '0';
      if write_stream_in.tvalid = '1' and write_stream_in.tlast = '1' and write_discard_in = '0' then
         save_write_ptr   <= write_stream_in.tlast;
      end if;
      if save_write_ptr = '1' then
         write_ptr_saved   <= write_ptr;
      end if;

   end process;

   -- Catch a discard event
   catch_discard : process
   begin
      wait until rising_edge(clk_in);
      if write_stream_in.tlast = '1' then
         discard_pkt <= '0';
      elsif write_discard_in = '1' then
         discard_pkt <= '1';
      end if;
   end process;

   

   -- Check behaviour
   behave_check : process
   begin
      wait until rising_edge(clk_in);

      -- Gneerate a semiphore to detect when the first write has been completed
      if reset_in = '1' then
         no_write_complete <= '1';
      elsif port_a_we = '1' then
         no_write_complete <= '0';
      end if;

      if read_ptr = write_ptr and no_write_complete = '0' then
         report "Warning in ring buffer: Read and write pointers are equal" severity note;
         
         if port_a_we = '1' then
            report "Error in ring buffer: Overwrite of data!!!" severity error;
         end if;
      end if;
   end process;

   port_a_we      <= '1' when write_stream_in.tvalid = '1' and write_discard_in = '0' else '0';
   port_a_adr     <= to_unsigned(write_ptr, port_a_adr'length);
   port_a_data_in <= write_stream_in.tlast & write_stream_in.tdata;

   port_b_adr     <= to_unsigned(read_ptr, port_b_adr'length);

   ring_buffer_ram : entity ce_mem_lib.ce_dpram 
   generic map(
            RAM_DEPTH            => RAM_DEPTH
         )
   port map(
            clk_in               => clk_in,
            -- Port A
            port_a_we            => port_a_we,
            port_a_adr           => port_a_adr,
            port_a_data_in       => port_a_data_in,
            port_a_data_out      => port_a_data_out, 
            -- Port B
            port_b_we            => '0',
            port_b_adr           => port_b_adr,
            port_b_data_in       => port_b_data_in,
            port_b_data_out      => port_b_data_out 
         );

   -- Check behaviour
   gen_output : process
   begin
      wait until rising_edge(clk_in);
      if read_ptr_ctrl = inc then
         read_stream_out.tvalid  <= '1';
      else
         read_stream_out.tvalid  <= '0';
      end if;
   end process;

   read_stream_out.tdata   <= port_b_data_out(read_stream_out.tdata'range);
   read_stream_out.tlast   <= '1' when read_tlast_flag = '1' else '0';

   write_stream_rfd_out    <= '1' when no_write_complete = '1' and reset_in = '0' and port_a_adr /= port_b_adr;

   num_pkts_out            <= to_unsigned(num_pkt_count, num_pkts_out'length);

end rtl;