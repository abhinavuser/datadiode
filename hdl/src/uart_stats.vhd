-- uart_stats.vhd
-- uart transmitter for statistics output.
-- sends packet counters over usb-uart (115200 baud, 8n1) every second.
-- format: rx:xxxxxxxx tx:xxxxxxxx dr:xxxxxxxx er:xxxxxxxx\r\n

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_stats is
    generic (
        g_clk_freq : integer := 100000000;
        g_baud     : integer := 115200
    );
    port (
        clk   : in  std_logic;
        reset : in  std_logic;

        rx_frame_cnt    : in  unsigned(31 downto 0);
        tx_frame_cnt    : in  unsigned(31 downto 0);
        filter_pass_cnt : in  unsigned(31 downto 0);
        filter_drop_cnt : in  unsigned(31 downto 0);
        rx_error_cnt    : in  unsigned(31 downto 0);

        uart_tx : out std_logic
    );
end entity uart_stats;

architecture rtl of uart_stats is

    constant BAUD_DIV : integer := g_clk_freq / g_baud;

    type uart_state_t is (U_IDLE, U_START, U_DATA, U_STOP);
    signal u_state   : uart_state_t := U_IDLE;
    signal baud_cnt  : unsigned(15 downto 0) := (others => '0');
    signal bit_cnt   : unsigned(2 downto 0) := (others => '0');
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');

    type msg_state_t is (M_IDLE, M_LOAD, M_SEND, M_WAIT);
    signal m_state   : msg_state_t := M_IDLE;

    type char_buf_t is array (0 to 79) of std_logic_vector(7 downto 0);
    signal msg_buf   : char_buf_t := (others => (others => '0'));
    signal msg_len   : unsigned(6 downto 0) := (others => '0');
    signal msg_idx   : unsigned(6 downto 0) := (others => '0');

    signal tx_busy   : std_logic := '0';
    signal tx_start  : std_logic := '0';
    signal tx_byte   : std_logic_vector(7 downto 0) := (others => '0');

    signal sec_cnt   : unsigned(26 downto 0) := (others => '0');
    signal sec_tick  : std_logic := '0';

    function nib2ascii(n : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable v : unsigned(7 downto 0);
    begin
        v := resize(unsigned(n), 8);
        if v < 10 then
            return std_logic_vector(v + 48);
        else
            return std_logic_vector(v + 55);
        end if;
    end function;

begin

    process(clk)
    begin
        if rising_edge(clk) then
            sec_tick <= '0';
            if reset = '1' then
                sec_cnt <= (others => '0');
            elsif sec_cnt = g_clk_freq - 1 then
                sec_cnt  <= (others => '0');
                sec_tick <= '1';
            else
                sec_cnt <= sec_cnt + 1;
            end if;
        end if;
    end process;

    process(clk)
        variable v : unsigned(31 downto 0);
    begin
        if rising_edge(clk) then
            tx_start <= '0';

            if reset = '1' then
                m_state <= M_IDLE;
            else
                case m_state is
                    when M_IDLE =>
                        if sec_tick = '1' then
                            m_state <= M_LOAD;
                        end if;

                    when M_LOAD =>
                        msg_buf(0) <= x"52"; -- r
                        msg_buf(1) <= x"58"; -- x
                        msg_buf(2) <= x"3A"; -- :
                        v := rx_frame_cnt;
                        for i in 0 to 7 loop
                            msg_buf(3 + i) <= nib2ascii(std_logic_vector(v((7 - i) * 4 + 3 downto (7 - i) * 4)));
                        end loop;
                        msg_buf(11) <= x"20";

                        msg_buf(12) <= x"54"; -- t
                        msg_buf(13) <= x"58"; -- x
                        msg_buf(14) <= x"3A"; -- :
                        v := tx_frame_cnt;
                        for i in 0 to 7 loop
                            msg_buf(15 + i) <= nib2ascii(std_logic_vector(v((7 - i) * 4 + 3 downto (7 - i) * 4)));
                        end loop;
                        msg_buf(23) <= x"20";

                        msg_buf(24) <= x"44"; -- d
                        msg_buf(25) <= x"52"; -- r
                        msg_buf(26) <= x"3A"; -- :
                        v := filter_drop_cnt;
                        for i in 0 to 7 loop
                            msg_buf(27 + i) <= nib2ascii(std_logic_vector(v((7 - i) * 4 + 3 downto (7 - i) * 4)));
                        end loop;
                        msg_buf(35) <= x"20";

                        msg_buf(36) <= x"45"; -- e
                        msg_buf(37) <= x"52"; -- r
                        msg_buf(38) <= x"3A"; -- :
                        v := rx_error_cnt;
                        for i in 0 to 7 loop
                            msg_buf(39 + i) <= nib2ascii(std_logic_vector(v((7 - i) * 4 + 3 downto (7 - i) * 4)));
                        end loop;

                        msg_buf(47) <= x"0D"; -- \r
                        msg_buf(48) <= x"0A"; -- \n
                        msg_len <= to_unsigned(49, 7);
                        msg_idx <= (others => '0');
                        m_state <= M_SEND;

                    when M_SEND =>
                        if tx_busy = '0' then
                            if msg_idx < msg_len then
                                tx_byte  <= msg_buf(to_integer(msg_idx));
                                tx_start <= '1';
                                msg_idx  <= msg_idx + 1;
                                m_state  <= M_WAIT;
                            else
                                m_state <= M_IDLE;
                            end if;
                        end if;

                    when M_WAIT =>
                        if tx_busy = '1' then
                            m_state <= M_SEND;
                        end if;

                    when others =>
                        m_state <= M_IDLE;
                end case;
            end if;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                u_state <= U_IDLE;
                uart_tx <= '1';
                tx_busy <= '0';
            else
                case u_state is
                    when U_IDLE =>
                        uart_tx <= '1';
                        tx_busy <= '0';
                        if tx_start = '1' then
                            shift_reg <= tx_byte;
                            u_state   <= U_START;
                            baud_cnt  <= (others => '0');
                            tx_busy   <= '1';
                        end if;

                    when U_START =>
                        uart_tx <= '0';
                        if baud_cnt = BAUD_DIV - 1 then
                            baud_cnt <= (others => '0');
                            bit_cnt  <= (others => '0');
                            u_state  <= U_DATA;
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;

                    when U_DATA =>
                        uart_tx <= shift_reg(0);
                        if baud_cnt = BAUD_DIV - 1 then
                            baud_cnt  <= (others => '0');
                            shift_reg <= '0' & shift_reg(7 downto 1);
                            if bit_cnt = 7 then
                                u_state <= U_STOP;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;

                    when U_STOP =>
                        uart_tx <= '1';
                        if baud_cnt = BAUD_DIV - 1 then
                            baud_cnt <= (others => '0');
                            u_state  <= U_IDLE;
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;

                    when others =>
                        u_state <= U_IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
