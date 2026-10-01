-------------------------------------------------------------------------------
-- Title      : eth_rx_mii
-- Project    : FPGA-Based Hardware Data Diode
-------------------------------------------------------------------------------
-- Description: Ethernet receive MAC for MII (Media Independent Interface).
--              Captures frames from the on-board Arty A7 PHY (RTL8211E).
--              Detects preamble + SFD, extracts frame bytes, and computes
--              running CRC-32 for integrity checking.
--
-- Inspired by the Netherlands OSDD project (CyberInnovationHub-NLD),
-- enhanced with full CRC checking and byte-level output.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity eth_rx_mii is
    port (
        -- MII receive interface (directly from PHY)
        rx_clk      : in  std_logic;                     -- 25 MHz MII RX clock
        rx_dv       : in  std_logic;                     -- Data valid
        rx_er       : in  std_logic;                     -- Receive error
        rx_d        : in  std_logic_vector(3 downto 0);  -- 4-bit data nibbles

        -- Output interface (byte-level, rx_clk domain)
        frame_data  : out std_logic_vector(7 downto 0);  -- Received byte
        frame_valid : out std_logic;                      -- Byte is valid
        frame_sof   : out std_logic;                      -- Start of frame (first byte)
        frame_eof   : out std_logic;                      -- End of frame
        frame_err   : out std_logic;                      -- Frame had error (CRC or rx_er)
        crc_ok      : out std_logic;                      -- CRC check passed (valid at EOF)

        -- Statistics
        rx_frame_cnt  : out unsigned(31 downto 0);        -- Total frames received
        rx_error_cnt  : out unsigned(31 downto 0)         -- Frames with errors
    );
end entity eth_rx_mii;

architecture rtl of eth_rx_mii is

    -- CRC-32 polynomial (IEEE 802.3)
    constant CRC_POLY : std_logic_vector(31 downto 0) := x"04C11DB7";
    constant CRC_INIT : std_logic_vector(31 downto 0) := x"FFFFFFFF";
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

    -- Function: update CRC with one nibble
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
            -- Default outputs
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
                    if rx_dv = '1' then
                        if rx_d = x"5" then
                            state <= S_PREAMBLE;
                        end if;
                    end if;

                when S_PREAMBLE =>
                    if rx_dv = '0' then
                        -- Aborted during preamble
                        state <= S_IDLE;
                    elsif rx_d = x"D" then
                        -- SFD detected — next nibble is first data nibble
                        state <= S_DATA_LO;
                    elsif rx_d /= x"5" then
                        -- Invalid preamble
                        state <= S_IDLE;
                    end if;

                when S_DATA_LO =>
                    -- First nibble of a byte (low nibble in MII)
                    if rx_dv = '0' then
                        -- End of frame (shouldn't end on a half-byte normally)
                        frame_eof  <= '1';
                        frame_err  <= '1';
                        had_error  <= '1';
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
                    -- Second nibble of a byte (high nibble in MII)
                    crc_reg <= crc_nibble(crc_reg, rx_d);

                    byte_reg <= rx_d & nibble_lo;
                    frame_data <= rx_d & nibble_lo;
                    frame_valid <= '1';

                    if byte_cnt = 0 then
                        frame_sof <= '1';
                    end if;

                    byte_cnt <= byte_cnt + 1;

                    if rx_er = '1' then
                        had_error <= '1';
                    end if;

                    if rx_dv = '0' then
                        -- This shouldn't happen mid-byte, but handle gracefully
                        frame_eof <= '1';
                        frame_err <= had_error or rx_er;
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

            -- Detect end of frame on DV falling edge (after last DATA_HI)
            if prev_dv = '1' and rx_dv = '0' and state = S_DATA_LO then
                frame_eof <= '1';
                -- Check CRC residual
                if crc_reg = CRC_RESIDUAL and had_error = '0' then
                    crc_ok <= '1';
                else
                    frame_err <= '1';
                    s_error_cnt <= s_error_cnt + 1;
                end if;
                s_frame_cnt <= s_frame_cnt + 1;
                state <= S_IDLE;
            end if;

        end if;
    end process;

end architecture rtl;
