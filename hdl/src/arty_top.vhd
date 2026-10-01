-------------------------------------------------------------------------------
-- Title      : arty_top
-- Project    : FPGA-Based Hardware Data Diode
-------------------------------------------------------------------------------
-- Description: Top-level entity for the Digilent Arty A7-100T.
--              Implements a hardware-enforced unidirectional data diode
--              from the on-board Ethernet PHY (RX only, MII) to an
--              external LAN8720 module (TX only, RMII) via Pmod JA.
--
-- Architecture inspired by the Netherlands Open Source Data Diode
-- (CyberInnovationHub-NLD), ported from Intel MAX10 to Xilinx Artix-7,
-- with added packet parsing, security filtering, CRC checking,
-- and UART statistics monitoring.
--
-- SECURITY GUARANTEE: The LAN8720's RX signals (RXD, CRS_DV) are NOT
-- connected to any FPGA logic. No reverse data path exists in hardware.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity arty_top is
    port (
        -- System
        CLK100MHZ : in  std_logic;              -- 100 MHz system clock

        -- On-board Ethernet PHY (RTL8211E) — RX ONLY (MII interface)
        eth_rx_clk   : in  std_logic;                     -- 25 MHz MII RX clock
        eth_rx_dv    : in  std_logic;                     -- Data valid
        eth_rx_er    : in  std_logic;                     -- Receive error
        eth_rxd      : in  std_logic_vector(3 downto 0);  -- 4-bit RX data
        eth_rstn     : out std_logic;                     -- PHY reset (active low)
        eth_mdc      : out std_logic;                     -- MDIO clock
        eth_mdio     : inout std_logic;                   -- MDIO data (bidirectional)

        -- NOTE: On-board PHY TX pins (eth_txd, eth_tx_en, eth_tx_clk)
        -- are intentionally NOT used — the on-board PHY is RX-only.
        -- This prevents any FPGA-generated frames from being sent back
        -- to the OT network.

        -- LAN8720 Module via Pmod JA — TX ONLY (RMII interface)
        -- JA[1] = ja_txd0,  JA[2] = ja_txd1
        -- JA[3] = ja_txen,  JA[4] = ja_refclk (50 MHz output to LAN8720)
        ja : inout std_logic_vector(7 downto 0);  -- Pmod JA pins

        -- NOTE: LAN8720's RX pins (RXD0, RXD1, CRS_DV) on Pmod JA pins 7-9
        -- are intentionally NOT read by the FPGA — this is the hardware
        -- guarantee that no data can flow from IT back to OT.

        -- LAN8720 MDIO via Pmod JB
        -- JB[1] = lan_mdc
        jb : inout std_logic_vector(7 downto 0);  -- Pmod JB pins

        -- User interface
        led    : out std_logic_vector(3 downto 0);  -- LEDs
        sw     : in  std_logic_vector(3 downto 0);  -- Switches
        btn    : in  std_logic_vector(3 downto 0);  -- Buttons

        -- UART (via USB-UART bridge)
        uart_rxd_out : out std_logic                -- TX to host PC
    );
end entity arty_top;

architecture rtl of arty_top is

    -- =========================================================================
    -- Internal signals
    -- =========================================================================

    -- Clock signals
    signal clk_50mhz  : std_logic := '0';  -- 50 MHz for RMII
    signal clk_25mhz  : std_logic := '0';  -- Alias for MII RX clock

    -- Reset
    signal reset_cnt   : unsigned(23 downto 0) := (others => '0');
    signal reset_n     : std_logic := '0';
    signal reset       : std_logic := '1';

    -- RX MAC to Parser
    signal rx_data     : std_logic_vector(7 downto 0);
    signal rx_valid    : std_logic;
    signal rx_sof      : std_logic;
    signal rx_eof      : std_logic;
    signal rx_err      : std_logic;
    signal rx_crc_ok   : std_logic;
    signal rx_frame_cnt: unsigned(31 downto 0);
    signal rx_error_cnt: unsigned(31 downto 0);

    -- Parser to Filter
    signal p_data      : std_logic_vector(7 downto 0);
    signal p_valid     : std_logic;
    signal p_sof       : std_logic;
    signal p_eof       : std_logic;
    signal p_ethertype : std_logic_vector(15 downto 0);
    signal p_ip_proto  : std_logic_vector(7 downto 0);
    signal p_dst_port  : std_logic_vector(15 downto 0);
    signal p_hdr_valid : std_logic;
    signal p_is_ipv4   : std_logic;
    signal p_is_arp    : std_logic;
    signal p_is_udp    : std_logic;
    signal p_is_tcp    : std_logic;

    -- Filter to FIFO
    signal f_data      : std_logic_vector(7 downto 0);
    signal f_valid     : std_logic;
    signal f_sof       : std_logic;
    signal f_eof       : std_logic;
    signal f_drop      : std_logic;
    signal f_pass_cnt  : unsigned(31 downto 0);
    signal f_drop_cnt  : unsigned(31 downto 0);

    -- FIFO signals
    signal fifo_wr_data : std_logic_vector(8 downto 0);  -- 8 data + 1 EOF
    signal fifo_rd_data : std_logic_vector(8 downto 0);
    signal fifo_wr_en   : std_logic;
    signal fifo_rd_en   : std_logic;
    signal fifo_full    : std_logic;
    signal fifo_empty   : std_logic;
    signal fifo_overflow: unsigned(15 downto 0);

    -- FIFO to TX
    signal tx_data      : std_logic_vector(7 downto 0);
    signal tx_valid     : std_logic;
    signal tx_eof       : std_logic;
    signal tx_req       : std_logic;
    signal tx_frame_cnt : unsigned(31 downto 0);
    signal tx_busy      : std_logic;

    -- RMII output signals
    signal rmii_txd     : std_logic_vector(1 downto 0);
    signal rmii_txen    : std_logic;

    -- LED blink counter for heartbeat
    signal heartbeat_cnt : unsigned(25 downto 0) := (others => '0');

    -- 50 MHz clock generation (simple divider from 100 MHz)
    signal clk50_toggle : std_logic := '0';

begin

    -- =========================================================================
    -- Clock Generation
    -- =========================================================================

    -- Generate 50 MHz from 100 MHz (simple toggle divider)
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            clk50_toggle <= not clk50_toggle;
        end if;
    end process;
    clk_50mhz <= clk50_toggle;

    -- MII RX clock comes from the PHY
    clk_25mhz <= eth_rx_clk;

    -- =========================================================================
    -- Reset Generation (hold reset for ~167ms after power-up)
    -- =========================================================================
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

    -- PHY reset
    eth_rstn <= reset_n;

    -- =========================================================================
    -- Pmod JA Pin Mapping (LAN8720 TX ONLY)
    -- =========================================================================
    -- JA[0] = TXD0,  JA[1] = TXD1
    -- JA[2] = TX_EN, JA[3] = REF_CLK (50 MHz output)
    -- JA[4..7] = LAN8720 RX pins — LEFT UNCONNECTED IN LOGIC
    ja(0) <= rmii_txd(0);
    ja(1) <= rmii_txd(1);
    ja(2) <= rmii_txen;
    ja(3) <= clk_50mhz;       -- 50 MHz reference clock to LAN8720

    -- CRITICAL SECURITY: ja(4), ja(5), ja(6), ja(7) are physically connected
    -- to LAN8720's RXD0, RXD1, CRS_DV, and MDIO, but we NEVER read them.
    -- This is the hardware-enforced one-way guarantee.

    -- Pmod JB: LAN8720 MDC
    jb(0) <= '0';  -- MDC — simple pull-low for now (no management needed)

    -- MDIO — unused, leave as input
    eth_mdc  <= '0';
    eth_mdio <= 'Z';

    -- =========================================================================
    -- Ethernet RX MAC (MII, from on-board PHY)
    -- =========================================================================
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

    -- =========================================================================
    -- Packet Parser
    -- =========================================================================
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

    -- =========================================================================
    -- Security Filter
    -- =========================================================================
    u_filter : entity work.security_filter
        generic map (
            g_allow_arp  => true,
            g_allow_ipv4 => true,
            g_allow_udp  => true,
            g_allow_tcp  => false,  -- Block TCP
            g_allow_icmp => false   -- Block ICMP (no ping!)
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

    -- =========================================================================
    -- Async FIFO (MII 25 MHz → RMII 50 MHz clock domain crossing)
    -- =========================================================================
    fifo_wr_data <= f_eof & f_data;
    fifo_wr_en   <= f_valid;

    u_fifo : entity work.async_fifo
        generic map (
            g_data_width => 9,
            g_addr_width => 11  -- 2048 entries
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

    -- FIFO read interface
    tx_data  <= fifo_rd_data(7 downto 0);
    tx_eof   <= fifo_rd_data(8);
    tx_valid <= not fifo_empty;
    fifo_rd_en <= tx_req;

    -- =========================================================================
    -- Ethernet TX MAC (RMII, to LAN8720)
    -- =========================================================================
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

    -- =========================================================================
    -- UART Statistics Monitor
    -- =========================================================================
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

    -- =========================================================================
    -- LED Indicators
    -- =========================================================================
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            heartbeat_cnt <= heartbeat_cnt + 1;
        end if;
    end process;

    led(0) <= heartbeat_cnt(25);          -- Heartbeat (blink ~1.5 Hz)
    led(1) <= '1' when rx_frame_cnt > 0 else '0';  -- RX activity
    led(2) <= '1' when tx_frame_cnt > 0 else '0';  -- TX activity
    led(3) <= '1' when f_drop_cnt > 0 else '0';    -- Drop indicator

end architecture rtl;
