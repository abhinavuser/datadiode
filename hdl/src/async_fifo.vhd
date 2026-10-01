-------------------------------------------------------------------------------
-- Title      : async_fifo
-- Project    : FPGA-Based Hardware Data Diode
-------------------------------------------------------------------------------
-- Description: Asynchronous FIFO for cross-clock-domain transfer.
--              Used to bridge between the MII RX clock domain (25 MHz)
--              and the RMII TX clock domain (50 MHz).
--
--              Uses gray-code pointers for safe clock domain crossing.
--              Depth is configurable (must be power of 2).
--
-- The Dutch OSDD doesn't need this because both PHYs use the same
-- MII interface. We need it because LAN8720 uses RMII (different clock).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity async_fifo is
    generic (
        g_data_width : integer := 9;    -- 8 data bits + 1 EOF marker
        g_addr_width : integer := 11    -- 2^11 = 2048 entries
    );
    port (
        -- Write side (MII RX clock domain, 25 MHz)
        wr_clk   : in  std_logic;
        wr_en    : in  std_logic;
        wr_data  : in  std_logic_vector(g_data_width - 1 downto 0);
        wr_full  : out std_logic;

        -- Read side (RMII TX clock domain, 50 MHz)
        rd_clk   : in  std_logic;
        rd_en    : in  std_logic;
        rd_data  : out std_logic_vector(g_data_width - 1 downto 0);
        rd_empty : out std_logic;

        -- Status
        overflow_cnt : out unsigned(15 downto 0)
    );
end entity async_fifo;

architecture rtl of async_fifo is

    constant DEPTH : integer := 2**g_addr_width;

    type mem_t is array (0 to DEPTH - 1) of std_logic_vector(g_data_width - 1 downto 0);
    signal mem : mem_t := (others => (others => '0'));

    -- Binary pointers
    signal wr_ptr_bin : unsigned(g_addr_width downto 0) := (others => '0');
    signal rd_ptr_bin : unsigned(g_addr_width downto 0) := (others => '0');

    -- Gray-code pointers
    signal wr_ptr_gray     : std_logic_vector(g_addr_width downto 0) := (others => '0');
    signal rd_ptr_gray     : std_logic_vector(g_addr_width downto 0) := (others => '0');

    -- Synchronized gray pointers
    signal wr_ptr_gray_rd1 : std_logic_vector(g_addr_width downto 0) := (others => '0');
    signal wr_ptr_gray_rd2 : std_logic_vector(g_addr_width downto 0) := (others => '0');
    signal rd_ptr_gray_wr1 : std_logic_vector(g_addr_width downto 0) := (others => '0');
    signal rd_ptr_gray_wr2 : std_logic_vector(g_addr_width downto 0) := (others => '0');

    signal s_full  : std_logic := '0';
    signal s_empty : std_logic := '1';

    signal s_overflow : unsigned(15 downto 0) := (others => '0');

    -- Function: binary to gray
    function bin2gray(b : unsigned) return std_logic_vector is
    begin
        return std_logic_vector(b xor ('0' & b(b'left downto 1)));
    end function;

begin

    wr_full  <= s_full;
    rd_empty <= s_empty;
    overflow_cnt <= s_overflow;

    -- Full condition: wr_gray MSBs differ, rest matches
    s_full <= '1' when (wr_ptr_gray(g_addr_width) /= rd_ptr_gray_wr2(g_addr_width)) and
                       (wr_ptr_gray(g_addr_width - 1) /= rd_ptr_gray_wr2(g_addr_width - 1)) and
                       (wr_ptr_gray(g_addr_width - 2 downto 0) = rd_ptr_gray_wr2(g_addr_width - 2 downto 0))
              else '0';

    -- Empty condition: gray pointers match exactly
    s_empty <= '1' when wr_ptr_gray_rd2 = rd_ptr_gray else '0';

    -- Write process
    process(wr_clk)
    begin
        if rising_edge(wr_clk) then
            -- Synchronize rd_ptr_gray into wr_clk domain
            rd_ptr_gray_wr1 <= rd_ptr_gray;
            rd_ptr_gray_wr2 <= rd_ptr_gray_wr1;

            if wr_en = '1' then
                if s_full = '0' then
                    mem(to_integer(wr_ptr_bin(g_addr_width - 1 downto 0))) <= wr_data;
                    wr_ptr_bin  <= wr_ptr_bin + 1;
                    wr_ptr_gray <= bin2gray(wr_ptr_bin + 1);
                else
                    s_overflow <= s_overflow + 1;
                end if;
            end if;
        end if;
    end process;

    -- Read process
    process(rd_clk)
    begin
        if rising_edge(rd_clk) then
            -- Synchronize wr_ptr_gray into rd_clk domain
            wr_ptr_gray_rd1 <= wr_ptr_gray;
            wr_ptr_gray_rd2 <= wr_ptr_gray_rd1;

            rd_data <= mem(to_integer(rd_ptr_bin(g_addr_width - 1 downto 0)));

            if rd_en = '1' and s_empty = '0' then
                rd_ptr_bin  <= rd_ptr_bin + 1;
                rd_ptr_gray <= bin2gray(rd_ptr_bin + 1);
            end if;
        end if;
    end process;

end architecture rtl;
