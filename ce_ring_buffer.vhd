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
-- Module Name    : ce_ring_buffer - rtl
-- Project Name   : Cronus IP module
-- Target Devices :
-- Description    : Ring buffer with a discard function
--
-- Revisions      : 0.02 - Updating comments
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

   type write_port_ctl_T is (  
                              idle,
                              write_packet,
                              discard_packet
                            );

   signal write_port_state, write_port_state_n : write_port_ctl_T;

   type read_port_ctl_T is (  
                              idle,
                              read_packet,
                              wait_ipg
                            );

   signal read_port_state, read_port_state_n : read_port_ctl_T;

   signal write_ptr_ctrl      : COUNTER_CTRL_TYPE;
   signal write_ptr           : natural range 0 to RAM_DEPTH - 1;
   signal write_ptr_saved     : natural range 0 to RAM_DEPTH - 1;
   signal save_write_ptr      : std_logic;
   signal write_complete      : std_logic;

   signal read_ptr_ctrl       : COUNTER_CTRL_TYPE;
   signal read_ptr            : natural range 0 to RAM_DEPTH - 1;
   signal read_complete       : std_logic;

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

   signal first_write, first_write_n   : std_logic;

   alias read_tlast_flag is port_b_data_out(port_b_data_out'left);

begin

   ---------------------------------------------------------
   ------ Main sync process SM  
   ---------------------------------------------------------
   main_sync_sm : process
   begin
      wait until rising_edge(clk_in);

      -- Control the SM and registered signals
      if reset_in = '1' then
         write_port_state        <= idle;
         read_port_state         <= idle;
         first_write             <= '0';
         write_ptr_saved         <= 0;
      else
         write_port_state        <= write_port_state_n;
         read_port_state         <= read_port_state_n;
         first_write             <= first_write_n;
         if save_write_ptr = '1' then
            write_ptr_saved         <= write_ptr;
         end if;
      end if;

      -- Update the counters
      read_ptr       <= natural_counter(read_ptr_ctrl,      read_ptr,      0,                RAM_DEPTH - 1); -- We do not need the load function for the read pointer
      write_ptr      <= natural_counter(write_ptr_ctrl,     write_ptr,     write_ptr_saved,  RAM_DEPTH - 1); -- Use the load function when we need to discard the current packet
      num_pkt_count  <= natural_counter(num_pkt_count_ctrl, num_pkt_count, 0,                MAX_PACKETS - 1);
      pkt_gap_count  <= natural_counter(pkt_gap_count_ctrl, pkt_gap_count, 0,                READ_INTER_PKT_GAP - 1);

   end process;

   ---------------------------------------------------------
   ------ Main async process for the write
   ---------------------------------------------------------
   write_async_sm : process(write_port_state, write_discard_in, write_stream_in, reset_in, first_write)
   begin
      write_port_state_n   <= write_port_state; -- update the state
      save_write_ptr       <= '0';
      write_complete       <= '0';
      first_write_n        <= first_write;
      port_a_we            <= '0';
      
      -- Ckeck for the reset to see if the write pointer should be reset
      if reset_in = '1' then
         write_ptr_ctrl    <= rst;
      else
         write_ptr_ctrl    <= hold;
      end if;

      case write_port_state is

         -- Look out for new packets, we should also check that the packet is not
         -- discarded
         when idle =>
            save_write_ptr          <= '1';
            if write_discard_in = '1' then
               write_port_state_n   <= discard_packet;
            elsif write_stream_in.tvalid = '1' then
               write_ptr_ctrl       <= inc;
               write_port_state_n   <= write_packet;
               first_write_n        <= '1';
               port_a_we            <= '1';
            end if;

         -- Increment the write pointer for every valid, check for the discard and 
         -- end of the packet
         when write_packet =>
            if write_discard_in = '1' then
               if write_stream_in.tlast = '1' then
                  write_port_state_n   <= idle;
                  write_ptr_ctrl       <= load;
               else
                  write_port_state_n      <= discard_packet;
               end if;
               
            elsif write_stream_in.tvalid = '1' then
               port_a_we               <= '1';
               write_ptr_ctrl          <= inc;
               if write_stream_in.tlast = '1' then
                  write_port_state_n   <= idle;
                  write_complete       <= '1';
               end if;
            end if;

         -- Wait for the end of the discarded packet
         when others => -- discard_packet
            if write_stream_in.tlast = '1' then
               write_port_state_n   <= idle;
               write_ptr_ctrl       <= load;
            end if;

      end case;

   end process;

   ---------------------------------------------------------
   ------ Main async process for the read
   ---------------------------------------------------------
   read_async_sm : process(read_port_state, reset_in, read_stream_rfd_in, pkt_gap_count, read_tlast_flag, num_pkt_count)
   begin
      read_port_state_n    <= read_port_state; -- update the state
      read_complete        <= '0';
      pkt_gap_count_ctrl   <= rst;

      -- Ckeck for the reset to see if the write pointer should be reset
      if reset_in = '1' then
         read_ptr_ctrl     <= rst;
      else
         read_ptr_ctrl     <= hold;
      end if;

      case read_port_state is

         -- Look out for new packets
         when idle =>
            if num_pkt_count > 0 then
               read_port_state_n <= read_packet;
            end if;

         -- Increment the read pointer for every read_stream_rfd_in, check for the end of the packet
         when read_packet =>
            if read_stream_rfd_in = '1' then
               if read_tlast_flag = '1' then
                  read_port_state_n <= wait_ipg;
                  read_complete     <= '1';
               else
                  read_ptr_ctrl     <= inc;
               end if;
            end if;

         -- Wait for the inter packet gap
         when others => -- wait_ipg
            pkt_gap_count_ctrl      <= inc;
            if pkt_gap_count = READ_INTER_PKT_GAP - 1 then
               read_port_state_n    <= idle;
            end if;

      end case;
   end process;

   --Control the packet counter
   control_pkt_counter : process(reset_in, write_complete, read_complete)
   begin
      if reset_in = '1' then
         num_pkt_count_ctrl <= rst;
      elsif write_complete = '1' and read_complete = '0' then
         num_pkt_count_ctrl <= inc;
      elsif write_complete = '0' and read_complete = '1' then
         num_pkt_count_ctrl <= dec;
      else -- Either neither flag is set or both, in which case we can hold the value
         num_pkt_count_ctrl <= hold;
      end if;
   end process;

   -- Check behaviour
   behave_check : process
   begin
      wait until rising_edge(clk_in);

      if read_ptr = write_ptr and num_pkt_count > 0 and write_stream_in.tlast = '0' and read_tlast_flag = '0' then
         report "Warning in ring buffer: Read and write pointers are equal" severity note;
         
         if port_a_we = '1' then
            report "Error in ring buffer: Overwrite of data!!!" severity error;
         end if;
      end if;
   end process;

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

   write_stream_rfd_out    <= '1' when num_pkt_count = 0 or port_a_adr /= port_b_adr else '0';

   num_pkts_out            <= to_unsigned(num_pkt_count, num_pkts_out'length);

end rtl;