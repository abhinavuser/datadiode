-- eth_rx_mii.vhd
-- ethernet rx mac for mii interface (from arty onboard phy)
-- captures frames nibble by nibble, detects preamble/sfd,
-- outputs byte stream with sof/eof markers and crc32 check

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity eth_rx_mii is
    port (
        rx_clk      : in  std_logic;
        rx_dv       : in  std_logic;
        rx_er       : in  std_logic;
        rx_d        : in  std_logic_vector(3 downto 0);

        frame_data  : out std_logic_vector(7 downto 0);
        frame_valid : out std_logic;
        frame_sof   : out std_logic;
        frame_eof   : out std_logic;
        frame_err   : out std_logic;
        crc_ok      : out std_logic;

        rx_frame_cnt  : out unsigned(31 downto 0);
        rx_error_cnt  : out unsigned(31 downto 0)
    );
end entity eth_rx_mii;

architecture rtl of eth_rx_mii is

    constant CRC_POLY     : std_logic_vector(31 downto 0) := x"04C11DB7";
    constant CRC_INIT     : std_logic_vector(31 downto 0) := x"FFFFFFFF";
    constant CRC_RESIDUAL : std_logic_vector(31 downto 0) := x"C704DD7B";

    type rx_state_t is (S_IDLE, S_PREAMBLE, S_DATA_HI, S_DATA_LO);
    signal state     : rx_state_t := S_IDLE;

    signal nibble_lo : std_logic_vector(3 downto 0) := (others => '0');
    signal byte_reg  : std_logic_vector(7 downto 0) := (others => '0');
    signal crc_reg   : std_logic_vector(31 downto 0) := CRC_INIT;
    signal crc_next  : std_logic_vector(31 downto 0);
    signal byte_cnt  : unsigned(15 downto 0) := (others => '0');
    signal had_error : std_logic := '0';
    signal s_frame_cnt : unsigned(31 downto 0) := (others => '0');
    signal s_error_cnt : unsigned(31 downto 0) := (others => '0');
    signal prev_dv   : std_logic := '0';

    function crc_nibble(crc_in : std_logic_vector(31 downto 0);
                        nib    : std_logic_vector(3 downto 0))
        return std_logic_vector is
        variable c : std_logic_vector(31 downto 0);
        variable b : std_logic;
    begin
        c := crc_in;
        for i in 0 to 3 loop
            b := c(31) xor nib(i);
            c := c(30 downto 0) & '0';
            if b = '1' then
                c := c xor CRC_POLY;
            end if;
        end loop;
        return c;
    end function;

begin

    rx_frame_cnt <= s_frame_cnt;
    rx_error_cnt <= s_error_cnt;

    process(rx_clk)
    begin
        if rising_edge(rx_clk) then
            frame_valid <= '0';
            frame_sof   <= '0';
            frame_eof   <= '0';
            frame_err   <= '0';
            crc_ok      <= '0';
            frame_data  <= (others => '0');
            prev_dv <= rx_dv;

            case state is
                when S_IDLE =>
                    crc_reg   <= CRC_INIT;
                    byte_cnt  <= (others => '0');
                    had_error <= '0';
                    if rx_dv = '1' and rx_d = x"5" then
                        state <= S_PREAMBLE;
                    end if;

                when S_PREAMBLE =>
                    if rx_dv = '0' then
                        state <= S_IDLE;
                    elsif rx_d = x"D" then
                        state <= S_DATA_LO;
                    elsif rx_d /= x"5" then
                        state <= S_IDLE;
                    end if;

                when S_DATA_LO =>
                    if rx_dv = '0' then
                        frame_eof   <= '1';
                        frame_err   <= '1';
                        had_error   <= '1';
                        s_frame_cnt <= s_frame_cnt + 1;
                        s_error_cnt <= s_error_cnt + 1;
                        state <= S_IDLE;
                    else
                        nibble_lo <= rx_d;
                        crc_reg   <= crc_nibble(crc_reg, rx_d);
                        if rx_er = '1' then
                            had_error <= '1';
                        end if;
                        state <= S_DATA_HI;
                    end if;

                when S_DATA_HI =>
                    crc_reg     <= crc_nibble(crc_reg, rx_d);
                    byte_reg    <= rx_d & nibble_lo;
                    frame_data  <= rx_d & nibble_lo;
                    frame_valid <= '1';

                    if byte_cnt = 0 then
                        frame_sof <= '1';
                    end if;
                    byte_cnt <= byte_cnt + 1;

                    if rx_er = '1' then
                        had_error <= '1';
                    end if;

                    if rx_dv = '0' then
                        frame_eof   <= '1';
                        frame_err   <= had_error or rx_er;
                        s_frame_cnt <= s_frame_cnt + 1;
                        if had_error = '1' or rx_er = '1' then
                            s_error_cnt <= s_error_cnt + 1;
                        end if;
                        state <= S_IDLE;
                    else
                        state <= S_DATA_LO;
                    end if;

                when others =>
                    state <= S_IDLE;
            end case;

            if prev_dv = '1' and rx_dv = '0' and state = S_DATA_LO then
                frame_eof <= '1';
                if crc_reg = CRC_RESIDUAL and had_error = '0' then
                    crc_ok <= '1';
                else
                    frame_err   <= '1';
                    s_error_cnt <= s_error_cnt + 1;
                end if;
                s_frame_cnt <= s_frame_cnt + 1;
                state <= S_IDLE;
            end if;

        end if;
    end process;

end architecture rtl;
