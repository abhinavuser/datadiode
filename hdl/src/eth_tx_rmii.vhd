-- eth_tx_rmii.vhd
-- ethernet tx mac for rmii interface (to lan8720 module).
-- generates preamble + sfd, serializes frame data as dibits at 50 mhz,
-- appends crc32, enforces inter-frame gap.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity eth_tx_rmii is
    port (
        tx_clk   : in  std_logic;

        rmii_txd : out std_logic_vector(1 downto 0);
        rmii_txen: out std_logic;

        in_data  : in  std_logic_vector(7 downto 0);
        in_valid : in  std_logic;
        in_eof   : in  std_logic;
        in_req   : out std_logic;

        tx_frame_cnt : out unsigned(31 downto 0);
        tx_busy      : out std_logic
    );
end entity eth_tx_rmii;

architecture rtl of eth_tx_rmii is

    constant CRC_POLY : std_logic_vector(31 downto 0) := x"04C11DB7";

    type tx_state_t is (S_IDLE, S_PREAMBLE, S_SFD, S_DATA, S_CRC, S_IFG);
    signal state : tx_state_t := S_IDLE;

    signal dibit_cnt    : unsigned(1 downto 0) := (others => '0');
    signal byte_buf     : std_logic_vector(7 downto 0) := (others => '0');
    signal preamble_cnt : unsigned(5 downto 0) := (others => '0');
    signal ifg_cnt      : unsigned(5 downto 0) := (others => '0');
    signal crc_cnt      : unsigned(3 downto 0) := (others => '0');
    signal crc_reg      : std_logic_vector(31 downto 0) := x"FFFFFFFF";
    signal crc_out      : std_logic_vector(31 downto 0);
    signal s_frame_cnt  : unsigned(31 downto 0) := (others => '0');
    signal got_eof      : std_logic := '0';

    function crc_dibit(crc_in : std_logic_vector(31 downto 0);
                       dib    : std_logic_vector(1 downto 0))
        return std_logic_vector is
        variable c : std_logic_vector(31 downto 0);
        variable b : std_logic;
    begin
        c := crc_in;
        for i in 0 to 1 loop
            b := c(31) xor dib(i);
            c := c(30 downto 0) & '0';
            if b = '1' then
                c := c xor CRC_POLY;
            end if;
        end loop;
        return c;
    end function;

    function crc_finalize(crc_in : std_logic_vector(31 downto 0))
        return std_logic_vector is
        variable c : std_logic_vector(31 downto 0);
        variable r : std_logic_vector(31 downto 0);
    begin
        c := not crc_in;
        for i in 0 to 31 loop
            r(31 - i) := c(i);
        end loop;
        return r;
    end function;

begin

    tx_frame_cnt <= s_frame_cnt;
    tx_busy <= '0' when state = S_IDLE else '1';

    process(tx_clk)
    begin
        if rising_edge(tx_clk) then
            rmii_txd  <= "00";
            rmii_txen <= '0';
            in_req    <= '0';

            case state is
                when S_IDLE =>
                    if in_valid = '1' then
                        state        <= S_PREAMBLE;
                        preamble_cnt <= (others => '0');
                        crc_reg      <= x"FFFFFFFF";
                        got_eof      <= '0';
                    end if;

                when S_PREAMBLE =>
                    rmii_txen    <= '1';
                    rmii_txd     <= "01";
                    preamble_cnt <= preamble_cnt + 1;
                    if preamble_cnt = 27 then
                        state     <= S_SFD;
                        dibit_cnt <= (others => '0');
                    end if;

                when S_SFD =>
                    rmii_txen <= '1';
                    case to_integer(dibit_cnt) is
                        when 0 => rmii_txd <= "01";
                        when 1 => rmii_txd <= "01";
                        when 2 => rmii_txd <= "01";
                        when 3 =>
                            rmii_txd  <= "11";
                            byte_buf  <= in_data;
                            in_req    <= '1';
                            state     <= S_DATA;
                            dibit_cnt <= (others => '0');
                        when others => null;
                    end case;
                    if state = S_SFD then
                        dibit_cnt <= dibit_cnt + 1;
                    end if;

                when S_DATA =>
                    rmii_txen <= '1';
                    rmii_txd  <= byte_buf(1 downto 0);
                    crc_reg   <= crc_dibit(crc_reg, byte_buf(1 downto 0));
                    byte_buf  <= "00" & byte_buf(7 downto 2);
                    dibit_cnt <= dibit_cnt + 1;

                    if dibit_cnt = 3 then
                        dibit_cnt <= (others => '0');
                        if got_eof = '1' then
                            crc_out <= crc_finalize(crc_dibit(crc_reg, byte_buf(1 downto 0)));
                            state   <= S_CRC;
                            crc_cnt <= (others => '0');
                        else
                            byte_buf <= in_data;
                            if in_eof = '1' then
                                got_eof <= '1';
                            end if;
                            in_req <= '1';
                        end if;
                    end if;

                when S_CRC =>
                    rmii_txen <= '1';
                    rmii_txd  <= crc_out(1 downto 0);
                    crc_out   <= "00" & crc_out(31 downto 2);
                    crc_cnt   <= crc_cnt + 1;
                    if crc_cnt = 15 then
                        state       <= S_IFG;
                        ifg_cnt     <= (others => '0');
                        s_frame_cnt <= s_frame_cnt + 1;
                    end if;

                when S_IFG =>
                    rmii_txen <= '0';
                    rmii_txd  <= "00";
                    ifg_cnt   <= ifg_cnt + 1;
                    if ifg_cnt = 47 then
                        state <= S_IDLE;
                    end if;

                when others =>
                    state <= S_IDLE;
            end case;
        end if;
    end process;

end architecture rtl;
