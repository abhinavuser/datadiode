-- data_diode_tb.vhd
-- testbench for data diode pipeline
-- tests valid udp frame and blocked tcp frame

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity data_diode_tb is
end entity data_diode_tb;

architecture sim of data_diode_tb is

    signal clk_100mhz : std_logic := '0';
    signal rx_clk     : std_logic := '0';

    signal rx_dv : std_logic := '0';
    signal rx_er : std_logic := '0';
    signal rx_d  : std_logic_vector(3 downto 0) := (others => '0');

    signal eth_rstn    : std_logic;
    signal ja          : std_logic_vector(7 downto 0);
    signal jb          : std_logic_vector(7 downto 0);
    signal led         : std_logic_vector(3 downto 0);
    signal uart_tx_out : std_logic;

    signal eth_mdc  : std_logic;
    signal eth_mdio : std_logic := 'Z';

    signal sw  : std_logic_vector(3 downto 0) := (others => '0');
    signal btn : std_logic_vector(3 downto 0) := (others => '0');

    signal test_done : boolean := false;

    procedure send_nibble(signal clk : in std_logic;
                          signal dv  : out std_logic;
                          signal d   : out std_logic_vector(3 downto 0);
                          nib : std_logic_vector(3 downto 0)) is
    begin
        wait until rising_edge(clk);
        dv <= '1';
        d  <= nib;
    end procedure;

    procedure send_byte(signal clk : in std_logic;
                        signal dv  : out std_logic;
                        signal d   : out std_logic_vector(3 downto 0);
                        byt : std_logic_vector(7 downto 0)) is
    begin
        send_nibble(clk, dv, d, byt(3 downto 0));
        send_nibble(clk, dv, d, byt(7 downto 4));
    end procedure;

    procedure send_preamble(signal clk : in std_logic;
                            signal dv  : out std_logic;
                            signal d   : out std_logic_vector(3 downto 0)) is
    begin
        for i in 0 to 13 loop
            send_nibble(clk, dv, d, x"5");
        end loop;
        send_nibble(clk, dv, d, x"5");
        send_nibble(clk, dv, d, x"D");
    end procedure;

    procedure end_frame(signal clk : in std_logic;
                        signal dv  : out std_logic;
                        signal d   : out std_logic_vector(3 downto 0)) is
    begin
        wait until rising_edge(clk);
        dv <= '0';
        d  <= (others => '0');
        for i in 0 to 23 loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

begin

    clk_100mhz <= not clk_100mhz after 5 ns when not test_done;
    rx_clk <= not rx_clk after 20 ns when not test_done;

    dut : entity work.arty_top
        port map (
            CLK100MHZ    => clk_100mhz,
            eth_rx_clk   => rx_clk,
            eth_rx_dv    => rx_dv,
            eth_rx_er    => rx_er,
            eth_rxd      => rx_d,
            eth_rstn     => eth_rstn,
            eth_mdc      => eth_mdc,
            eth_mdio     => eth_mdio,
            ja           => ja,
            jb           => jb,
            led          => led,
            sw           => sw,
            btn          => btn,
            uart_rxd_out => uart_tx_out
        );

    stim : process
    begin
        wait for 200 us;

        report "test 1: send udp frame" severity note;

        send_preamble(rx_clk, rx_dv, rx_d);

        -- dst mac
        for i in 0 to 5 loop send_byte(rx_clk, rx_dv, rx_d, x"FF"); end loop;
        -- src mac
        for i in 0 to 5 loop send_byte(rx_clk, rx_dv, rx_d, x"11"); end loop;
        -- ethertype ipv4
        send_byte(rx_clk, rx_dv, rx_d, x"08");
        send_byte(rx_clk, rx_dv, rx_d, x"00");

        -- ip header
        send_byte(rx_clk, rx_dv, rx_d, x"45");
        send_byte(rx_clk, rx_dv, rx_d, x"00");
        send_byte(rx_clk, rx_dv, rx_d, x"00");
        send_byte(rx_clk, rx_dv, rx_d, x"1C");
        send_byte(rx_clk, rx_dv, rx_d, x"00");
        send_byte(rx_clk, rx_dv, rx_d, x"01");
        send_byte(rx_clk, rx_dv, rx_d, x"00");
        send_byte(rx_clk, rx_dv, rx_d, x"00");
        send_byte(rx_clk, rx_dv, rx_d, x"40");
        send_byte(rx_clk, rx_dv, rx_d, x"11"); -- udp
        send_byte(rx_clk, rx_dv, rx_d, x"00");
        send_byte(rx_clk, rx_dv, rx_d, x"00");
        for i in 0 to 3 loop send_byte(rx_clk, rx_dv, rx_d, x"C0"); end loop;
        for i in 0 to 3 loop send_byte(rx_clk, rx_dv, rx_d, x"C0"); end loop;

        -- udp header
        for i in 0 to 7 loop send_byte(rx_clk, rx_dv, rx_d, x"22"); end loop;

        -- padding
        for i in 0 to 17 loop send_byte(rx_clk, rx_dv, rx_d, x"AA"); end loop;

        -- crc
        for i in 0 to 3 loop send_byte(rx_clk, rx_dv, rx_d, x"00"); end loop;

        end_frame(rx_clk, rx_dv, rx_d);
        wait for 100 us;

        report "test 2: send tcp frame (should be dropped)" severity note;

        send_preamble(rx_clk, rx_dv, rx_d);
        for i in 0 to 5 loop send_byte(rx_clk, rx_dv, rx_d, x"FF"); end loop;
        for i in 0 to 5 loop send_byte(rx_clk, rx_dv, rx_d, x"11"); end loop;
        send_byte(rx_clk, rx_dv, rx_d, x"08");
        send_byte(rx_clk, rx_dv, rx_d, x"00");

        send_byte(rx_clk, rx_dv, rx_d, x"45");
        send_byte(rx_clk, rx_dv, rx_d, x"00");
        send_byte(rx_clk, rx_dv, rx_d, x"00");
        send_byte(rx_clk, rx_dv, rx_d, x"28");
        send_byte(rx_clk, rx_dv, rx_d, x"00");
        send_byte(rx_clk, rx_dv, rx_d, x"01");
        send_byte(rx_clk, rx_dv, rx_d, x"00");
        send_byte(rx_clk, rx_dv, rx_d, x"00");
        send_byte(rx_clk, rx_dv, rx_d, x"40");
        send_byte(rx_clk, rx_dv, rx_d, x"06"); -- tcp
        send_byte(rx_clk, rx_dv, rx_d, x"00");
        send_byte(rx_clk, rx_dv, rx_d, x"00");
        for i in 0 to 7 loop send_byte(rx_clk, rx_dv, rx_d, x"C0"); end loop;

        for i in 0 to 23 loop send_byte(rx_clk, rx_dv, rx_d, x"BB"); end loop;
        for i in 0 to 3 loop send_byte(rx_clk, rx_dv, rx_d, x"00"); end loop;

        end_frame(rx_clk, rx_dv, rx_d);

        wait for 50 us;
        test_done <= true;
        wait;
    end process;

end architecture sim;
