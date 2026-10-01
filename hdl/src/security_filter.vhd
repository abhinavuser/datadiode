-------------------------------------------------------------------------------
-- Title      : security_filter
-- Project    : FPGA-Based Hardware Data Diode
-------------------------------------------------------------------------------
-- Description: Configurable security filter for the data diode.
--              Decides whether each Ethernet frame should be forwarded or
--              dropped based on parsed header fields.
--
-- Default rules (configurable via generics):
--   - Allow: IPv4 UDP (EtherType 0x0800, Protocol 17)
--   - Allow: ARP (EtherType 0x0806) — needed for basic connectivity
--   - Drop:  Everything else (TCP, ICMP, etc.)
--
-- The Dutch OSDD has NO filtering — it passes everything blindly.
-- This is a significant security enhancement.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity security_filter is
    generic (
        -- Configurable filter rules
        g_allow_arp     : boolean := true;   -- Allow ARP frames?
        g_allow_ipv4    : boolean := true;   -- Allow IPv4 frames?
        g_allow_udp     : boolean := true;   -- Allow UDP within IPv4?
        g_allow_tcp     : boolean := false;  -- Allow TCP within IPv4?
        g_allow_icmp    : boolean := false;  -- Allow ICMP within IPv4?
        g_min_frame_len : integer := 60;     -- Minimum frame length (bytes)
        g_max_frame_len : integer := 1518    -- Maximum frame length (bytes)
    );
    port (
        clk         : in  std_logic;

        -- Input from packet_parser
        in_data     : in  std_logic_vector(7 downto 0);
        in_valid    : in  std_logic;
        in_sof      : in  std_logic;
        in_eof      : in  std_logic;

        -- Parsed header info
        is_ipv4     : in  std_logic;
        is_arp      : in  std_logic;
        is_udp      : in  std_logic;
        is_tcp      : in  std_logic;
        ip_protocol : in  std_logic_vector(7 downto 0);
        hdr_valid   : in  std_logic;

        -- Output (filtered)
        out_data    : out std_logic_vector(7 downto 0);
        out_valid   : out std_logic;
        out_sof     : out std_logic;
        out_eof     : out std_logic;
        out_drop    : out std_logic;  -- Pulse: frame was dropped

        -- Statistics
        filter_pass_cnt : out unsigned(31 downto 0);
        filter_drop_cnt : out unsigned(31 downto 0)
    );
end entity security_filter;

architecture rtl of security_filter is

    type filter_state_t is (S_ACCUMULATE, S_FORWARD, S_DROP);
    signal state : filter_state_t := S_ACCUMULATE;

    signal byte_cnt  : unsigned(15 downto 0) := (others => '0');
    signal decision  : std_logic := '0';  -- '1' = pass, '0' = drop
    signal decided   : std_logic := '0';

    signal s_pass_cnt : unsigned(31 downto 0) := (others => '0');
    signal s_drop_cnt : unsigned(31 downto 0) := (others => '0');

    -- Store frame in a small buffer until decision is made
    -- For simplicity, we use a "store-and-forward at header" approach:
    -- buffer the first 38 bytes, then once headers are parsed, decide
    type byte_buf_t is array (0 to 63) of std_logic_vector(7 downto 0);
    signal buf       : byte_buf_t := (others => (others => '0'));
    signal buf_wr    : unsigned(5 downto 0) := (others => '0');
    signal buf_rd    : unsigned(5 downto 0) := (others => '0');
    signal buf_valid : std_logic := '0';

    signal frame_active : std_logic := '0';

begin

    filter_pass_cnt <= s_pass_cnt;
    filter_drop_cnt <= s_drop_cnt;

    process(clk)
        variable allow : std_logic;
    begin
        if rising_edge(clk) then
            out_valid <= '0';
            out_sof   <= '0';
            out_eof   <= '0';
            out_drop  <= '0';
            out_data  <= (others => '0');

            case state is
                when S_ACCUMULATE =>
                    -- Buffer incoming bytes until we can decide
                    if in_valid = '1' then
                        if in_sof = '1' then
                            buf_wr <= (others => '0');
                            buf_rd <= (others => '0');
                            byte_cnt <= (others => '0');
                            frame_active <= '1';
                        end if;

                        if buf_wr < 64 then
                            buf(to_integer(buf_wr)) <= in_data;
                            buf_wr <= buf_wr + 1;
                        end if;
                        byte_cnt <= byte_cnt + 1;
                    end if;

                    -- Once header is parsed, make filtering decision
                    if hdr_valid = '1' and frame_active = '1' then
                        allow := '0';

                        if is_arp = '1' and g_allow_arp then
                            allow := '1';
                        elsif is_ipv4 = '1' and g_allow_ipv4 then
                            if is_udp = '1' and g_allow_udp then
                                allow := '1';
                            elsif is_tcp = '1' and g_allow_tcp then
                                allow := '1';
                            elsif ip_protocol = x"01" and g_allow_icmp then
                                allow := '1';  -- ICMP
                            end if;
                        end if;

                        if allow = '1' then
                            state <= S_FORWARD;
                            -- Start draining buffer
                            buf_rd <= (others => '0');
                        else
                            state <= S_DROP;
                            s_drop_cnt <= s_drop_cnt + 1;
                            out_drop <= '1';
                        end if;
                    end if;

                    -- Frame ended before we could decide (too short)
                    if in_eof = '1' and frame_active = '1' then
                        state <= S_DROP;
                        s_drop_cnt <= s_drop_cnt + 1;
                        out_drop <= '1';
                        frame_active <= '0';
                    end if;

                when S_FORWARD =>
                    -- Drain buffered bytes first
                    if buf_rd < buf_wr then
                        out_data  <= buf(to_integer(buf_rd));
                        out_valid <= '1';
                        if buf_rd = 0 then
                            out_sof <= '1';
                        end if;
                        buf_rd <= buf_rd + 1;
                    elsif in_valid = '1' then
                        -- Forward live data
                        out_data  <= in_data;
                        out_valid <= '1';
                    end if;

                    if in_eof = '1' then
                        out_eof <= '1';
                        s_pass_cnt <= s_pass_cnt + 1;
                        frame_active <= '0';
                        state <= S_ACCUMULATE;
                    end if;

                when S_DROP =>
                    -- Consume and discard the rest of the frame
                    if in_eof = '1' or in_valid = '0' then
                        frame_active <= '0';
                        state <= S_ACCUMULATE;
                    end if;

                when others =>
                    state <= S_ACCUMULATE;
            end case;
        end if;
    end process;

end architecture rtl;
