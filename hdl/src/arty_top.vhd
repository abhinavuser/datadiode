-- arty_top.vhd
-- top level entity for arty a7-100t data diode.
-- hardware unidirectional diode: rx from onboard phy (mii),
-- tx to lan8720 (rmii) on pmod ja.
-- security: lan8720 rx pins are never read.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity arty_top is
    port (
        CLK100MHZ    : in  std_logic;

        eth_rx_clk   : in  std_logic;
        eth_rx_dv    : in  std_logic;
        eth_rx_er    : in  std_logic;
        eth_rxd      : in  std_logic_vector(3 downto 0);
        eth_rstn     : out std_logic;
        eth_mdc      : out std_logic;
        eth_mdio     : inout std_logic;

        ja           : out std_logic_vector(7 downto 0);
        jb           : out std_logic_vector(7 downto 0);

        led          : out std_logic_vector(3 downto 0);
        sw           : in  std_logic_vector(3 downto 0);
        btn          : in  std_logic_vector(3 downto 0);

        uart_rxd_out : out std_logic
    );
end entity arty_top;

architecture rtl of arty_top is

    signal clk_50mhz     : std_logic := '0';
    signal clk_25mhz     : std_logic := '0';
    signal clk50_toggle  : std_logic := '0';

    signal reset_cnt     : unsigned(23 downto 0) := (others => '0');
    signal reset_n       : std_logic := '0';
    signal reset         : std_logic := '1';

    signal rx_data       : std_logic_vector(7 downto 0);
    signal rx_valid      : std_logic;
    signal rx_sof        : std_logic;
    signal rx_eof        : std_logic;
    signal rx_err        : std_logic;
    signal rx_crc_ok     : std_logic;
    signal rx_frame_cnt  : unsigned(31 downto 0);
    signal rx_error_cnt  : unsigned(31 downto 0);

    signal p_data        : std_logic_vector(7 downto 0);
    signal p_valid       : std_logic;
    signal p_sof         : std_logic;
    signal p_eof         : std_logic;
    signal p_ethertype   : std_logic_vector(15 downto 0);
    signal p_ip_proto    : std_logic_vector(7 downto 0);
    signal p_dst_port    : std_logic_vector(15 downto 0);
    signal p_hdr_valid   : std_logic;
    signal p_is_ipv4     : std_logic;
    signal p_is_arp      : std_logic;
    signal p_is_udp      : std_logic;
    signal p_is_tcp      : std_logic;

    signal f_data        : std_logic_vector(7 downto 0);
    signal f_valid       : std_logic;
    signal f_sof         : std_logic;
    signal f_eof         : std_logic;
    signal f_drop        : std_logic;
    signal f_pass_cnt    : unsigned(31 downto 0);
    signal f_drop_cnt    : unsigned(31 downto 0);

    signal fifo_wr_data  : std_logic_vector(8 downto 0);
    signal fifo_rd_data  : std_logic_vector(8 downto 0);
    signal fifo_wr_en    : std_logic;
    signal fifo_rd_en    : std_logic;
    signal fifo_full     : std_logic;
    signal fifo_empty    : std_logic;
    signal fifo_overflow : unsigned(15 downto 0);

    signal tx_data       : std_logic_vector(7 downto 0);
    signal tx_valid      : std_logic;
    signal tx_eof        : std_logic;
    signal tx_req        : std_logic;
    signal tx_frame_cnt  : unsigned(31 downto 0);
    signal tx_busy       : std_logic;

    signal rmii_txd      : std_logic_vector(1 downto 0);
    signal rmii_txen     : std_logic;

    signal heartbeat_cnt : unsigned(25 downto 0) := (others => '0');

begin

    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            clk50_toggle <= not clk50_toggle;
        end if;
    end process;
    clk_50mhz <= clk50_toggle;

    clk_25mhz <= eth_rx_clk;

    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if reset_cnt(23) = '0' then
                reset_cnt <= reset_cnt + 1;
                reset_n <= '0';
                reset   <= '1';
            else
                reset_n <= '1';
                reset   <= '0';
            end if;
        end if;
    end process;

    eth_rstn <= reset_n;

    -- pmod ja (lan8720 tx)
    ja(0) <= rmii_txd(0);
    ja(1) <= rmii_txd(1);
    ja(2) <= rmii_txen;
    ja(3) <= clk_50mhz;
    -- ja(4..7) not assigned (security guarantee)
    ja(4) <= '0';
    ja(5) <= '0';
    ja(6) <= '0';
    ja(7) <= '0';

    jb <= (others => '0');

    eth_mdc  <= '0';
    eth_mdio <= 'Z';

    u_rx : entity work.eth_rx_mii
        port map (
            rx_clk       => clk_25mhz,
            rx_dv        => eth_rx_dv,
            rx_er        => eth_rx_er,
            rx_d         => eth_rxd,
            frame_data   => rx_data,
            frame_valid  => rx_valid,
            frame_sof    => rx_sof,
            frame_eof    => rx_eof,
            frame_err    => rx_err,
            crc_ok       => rx_crc_ok,
            rx_frame_cnt => rx_frame_cnt,
            rx_error_cnt => rx_error_cnt
        );

    u_parser : entity work.packet_parser
        port map (
            clk             => clk_25mhz,
            in_data         => rx_data,
            in_valid        => rx_valid,
            in_sof          => rx_sof,
            in_eof          => rx_eof,
            out_data        => p_data,
            out_valid       => p_valid,
            out_sof         => p_sof,
            out_eof         => p_eof,
            ethertype       => p_ethertype,
            ip_protocol     => p_ip_proto,
            dst_port        => p_dst_port,
            frame_hdr_valid => p_hdr_valid,
            is_ipv4         => p_is_ipv4,
            is_arp          => p_is_arp,
            is_udp          => p_is_udp,
            is_tcp          => p_is_tcp
        );

    u_filter : entity work.security_filter
        generic map (
            g_allow_arp  => true,
            g_allow_ipv4 => true,
            g_allow_udp  => true,
            g_allow_tcp  => false,
            g_allow_icmp => false
        )
        port map (
            clk             => clk_25mhz,
            in_data         => p_data,
            in_valid        => p_valid,
            in_sof          => p_sof,
            in_eof          => p_eof,
            is_ipv4         => p_is_ipv4,
            is_arp          => p_is_arp,
            is_udp          => p_is_udp,
            is_tcp          => p_is_tcp,
            ip_protocol     => p_ip_proto,
            hdr_valid       => p_hdr_valid,
            out_data        => f_data,
            out_valid       => f_valid,
            out_sof         => f_sof,
            out_eof         => f_eof,
            out_drop        => f_drop,
            filter_pass_cnt => f_pass_cnt,
            filter_drop_cnt => f_drop_cnt
        );

    fifo_wr_data <= f_eof & f_data;
    fifo_wr_en   <= f_valid;

    u_fifo : entity work.async_fifo
        generic map (
            g_data_width => 9,
            g_addr_width => 11
        )
        port map (
            wr_clk       => clk_25mhz,
            wr_en        => fifo_wr_en,
            wr_data      => fifo_wr_data,
            wr_full      => fifo_full,
            rd_clk       => clk_50mhz,
            rd_en        => fifo_rd_en,
            rd_data      => fifo_rd_data,
            rd_empty     => fifo_empty,
            overflow_cnt => fifo_overflow
        );

    tx_data  <= fifo_rd_data(7 downto 0);
    tx_eof   <= fifo_rd_data(8);
    tx_valid <= not fifo_empty;
    fifo_rd_en <= tx_req;

    u_tx : entity work.eth_tx_rmii
        port map (
            tx_clk       => clk_50mhz,
            rmii_txd     => rmii_txd,
            rmii_txen    => rmii_txen,
            in_data      => tx_data,
            in_valid     => tx_valid,
            in_eof       => tx_eof,
            in_req       => tx_req,
            tx_frame_cnt => tx_frame_cnt,
            tx_busy      => tx_busy
        );

    u_uart : entity work.uart_stats
        generic map (
            g_clk_freq => 100000000,
            g_baud     => 115200
        )
        port map (
            clk             => CLK100MHZ,
            reset           => reset,
            rx_frame_cnt    => rx_frame_cnt,
            tx_frame_cnt    => tx_frame_cnt,
            filter_pass_cnt => f_pass_cnt,
            filter_drop_cnt => f_drop_cnt,
            rx_error_cnt    => rx_error_cnt,
            uart_tx         => uart_rxd_out
        );

    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            heartbeat_cnt <= heartbeat_cnt + 1;
        end if;
    end process;

    led(0) <= heartbeat_cnt(25);
    led(1) <= '1' when rx_frame_cnt > 0 else '0';
    led(2) <= '1' when tx_frame_cnt > 0 else '0';
    led(3) <= '1' when f_drop_cnt > 0 else '0';

end architecture rtl;
