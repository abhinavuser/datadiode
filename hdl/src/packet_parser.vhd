-- packet_parser.vhd
-- parses ethernet frame headers inline to extract ethertype, ip protocol,
-- and dst port. passes data through unchanged with parsed metadata on the side.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity packet_parser is
    port (
        clk         : in  std_logic;

        in_data     : in  std_logic_vector(7 downto 0);
        in_valid    : in  std_logic;
        in_sof      : in  std_logic;
        in_eof      : in  std_logic;

        out_data    : out std_logic_vector(7 downto 0);
        out_valid   : out std_logic;
        out_sof     : out std_logic;
        out_eof     : out std_logic;

        ethertype       : out std_logic_vector(15 downto 0);
        ip_protocol     : out std_logic_vector(7 downto 0);
        dst_port        : out std_logic_vector(15 downto 0);
        frame_hdr_valid : out std_logic;
        is_ipv4         : out std_logic;
        is_arp          : out std_logic;
        is_udp          : out std_logic;
        is_tcp          : out std_logic
    );
end entity packet_parser;

architecture rtl of packet_parser is

    signal byte_cnt : unsigned(15 downto 0) := (others => '0');

    signal r_ethertype   : std_logic_vector(15 downto 0) := (others => '0');
    signal r_ip_protocol : std_logic_vector(7 downto 0)  := (others => '0');
    signal r_dst_port    : std_logic_vector(15 downto 0) := (others => '0');
    signal r_is_ipv4     : std_logic := '0';
    signal r_is_arp      : std_logic := '0';
    signal r_is_udp      : std_logic := '0';
    signal r_is_tcp      : std_logic := '0';
    signal r_hdr_valid   : std_logic := '0';

begin

    -- passthrough
    out_data  <= in_data;
    out_valid <= in_valid;
    out_sof   <= in_sof;
    out_eof   <= in_eof;

    ethertype       <= r_ethertype;
    ip_protocol     <= r_ip_protocol;
    dst_port        <= r_dst_port;
    frame_hdr_valid <= r_hdr_valid;
    is_ipv4         <= r_is_ipv4;
    is_arp          <= r_is_arp;
    is_udp          <= r_is_udp;
    is_tcp          <= r_is_tcp;

    process(clk)
    begin
        if rising_edge(clk) then
            if in_valid = '1' then
                if in_sof = '1' then
                    byte_cnt      <= (others => '0');
                    r_ethertype   <= (others => '0');
                    r_ip_protocol <= (others => '0');
                    r_dst_port    <= (others => '0');
                    r_is_ipv4     <= '0';
                    r_is_arp      <= '0';
                    r_is_udp      <= '0';
                    r_is_tcp      <= '0';
                    r_hdr_valid   <= '0';
                end if;

                -- byte positions in an ethernet frame:
                -- [0..5] dst mac, [6..11] src mac, [12..13] ethertype
                -- [14] ip ver+ihl, [23] ip protocol
                -- [36..37] dst port (udp/tcp)
                case to_integer(byte_cnt) is
                    when 12 =>
                        r_ethertype(15 downto 8) <= in_data;
                    when 13 =>
                        r_ethertype(7 downto 0) <= in_data;
                        if r_ethertype(15 downto 8) = x"08" then
                            if in_data = x"00" then
                                r_is_ipv4 <= '1';
                            elsif in_data = x"06" then
                                r_is_arp <= '1';
                            end if;
                        end if;
                    when 23 =>
                        r_ip_protocol <= in_data;
                        if in_data = x"11" then
                            r_is_udp <= '1';
                        elsif in_data = x"06" then
                            r_is_tcp <= '1';
                        end if;
                    when 36 =>
                        r_dst_port(15 downto 8) <= in_data;
                    when 37 =>
                        r_dst_port(7 downto 0) <= in_data;
                        r_hdr_valid <= '1';
                    when others =>
                        null;
                end case;

                byte_cnt <= byte_cnt + 1;
            end if;

            if in_eof = '1' then
                byte_cnt <= (others => '0');
            end if;
        end if;
    end process;

end architecture rtl;
