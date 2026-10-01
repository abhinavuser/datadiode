## =============================================================================
## Arty A7-100T — FPGA Data Diode Pin Constraints
## =============================================================================
## Target: xc7a100tcsg324-1
## Reference: Digilent Arty A7 Reference Manual + Schematic
## =============================================================================

## ---- System Clock (100 MHz) ----
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }];
create_clock -name sys_clk -period 10.000 [get_ports { CLK100MHZ }];

## ---- On-board Ethernet PHY (RTL8211E) — RX ONLY ----
## These are the RECEIVE pins — the FPGA listens to the OT network
set_property -dict { PACKAGE_PIN F15 IOSTANDARD LVCMOS33 } [get_ports { eth_rx_clk }];
set_property -dict { PACKAGE_PIN G16 IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[0] }];
set_property -dict { PACKAGE_PIN H14 IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[1] }];
set_property -dict { PACKAGE_PIN J14 IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[2] }];
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[3] }];
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports { eth_rx_dv }];
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 } [get_ports { eth_rx_er }];

## PHY Reset and Management (active low reset)
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports { eth_rstn }];
set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 } [get_ports { eth_mdc }];
set_property -dict { PACKAGE_PIN K14 IOSTANDARD LVCMOS33 } [get_ports { eth_mdio }];

## IMPORTANT: On-board PHY TX pins are NOT used!
## The on-board PHY is RX-only in our data diode design.
## We do NOT map eth_txd, eth_tx_en, eth_tx_clk — this ensures
## no FPGA logic can ever send data back to the OT network.

## ---- MII RX clock constraint ----
create_clock -name mii_rx_clk -period 40.000 [get_ports { eth_rx_clk }];

## ---- Pmod JA: LAN8720 Module (TX ONLY — RMII interface) ----
## Pin mapping for LAN8720 connected via Pmod JA header
##   JA[0] = G13 = TXD0     (FPGA → LAN8720)
##   JA[1] = B11 = TXD1     (FPGA → LAN8720)
##   JA[2] = A11 = TX_EN    (FPGA → LAN8720)
##   JA[3] = D12 = REF_CLK  (FPGA → LAN8720, 50 MHz)
##   JA[4] = D13 = RXD0     (LAN8720 → NOT USED — diode guarantee)
##   JA[5] = B18 = RXD1     (LAN8720 → NOT USED)
##   JA[6] = A18 = CRS_DV   (LAN8720 → NOT USED)
##   JA[7] = K16 = MDIO     (bidirectional, optional)

set_property -dict { PACKAGE_PIN G13 IOSTANDARD LVCMOS33 } [get_ports { ja[0] }];
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports { ja[1] }];
set_property -dict { PACKAGE_PIN A11 IOSTANDARD LVCMOS33 } [get_ports { ja[2] }];
set_property -dict { PACKAGE_PIN D12 IOSTANDARD LVCMOS33 } [get_ports { ja[3] }];
set_property -dict { PACKAGE_PIN D13 IOSTANDARD LVCMOS33 } [get_ports { ja[4] }];
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports { ja[5] }];
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports { ja[6] }];
set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports { ja[7] }];

## ---- Pmod JB: LAN8720 MDC ----
set_property -dict { PACKAGE_PIN E15 IOSTANDARD LVCMOS33 } [get_ports { jb[0] }];
set_property -dict { PACKAGE_PIN E16 IOSTANDARD LVCMOS33 } [get_ports { jb[1] }];
set_property -dict { PACKAGE_PIN D15 IOSTANDARD LVCMOS33 } [get_ports { jb[2] }];
set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 } [get_ports { jb[3] }];
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports { jb[4] }];
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports { jb[5] }];
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { jb[6] }];
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports { jb[7] }];

## ---- 50 MHz RMII clock constraint ----
## Generated internally from CLK100MHZ ÷ 2
create_generated_clock -name rmii_clk -source [get_ports CLK100MHZ] \
    -divide_by 2 [get_pins {clk50_toggle_reg/Q}]

## ---- LEDs ----
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

## ---- Switches ----
set_property -dict { PACKAGE_PIN A8  IOSTANDARD LVCMOS33 } [get_ports { sw[0] }];
set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports { sw[1] }];
set_property -dict { PACKAGE_PIN C10 IOSTANDARD LVCMOS33 } [get_ports { sw[2] }];
set_property -dict { PACKAGE_PIN A10 IOSTANDARD LVCMOS33 } [get_ports { sw[3] }];

## ---- Buttons ----
set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports { btn[0] }];
set_property -dict { PACKAGE_PIN C9  IOSTANDARD LVCMOS33 } [get_ports { btn[1] }];
set_property -dict { PACKAGE_PIN B9  IOSTANDARD LVCMOS33 } [get_ports { btn[2] }];
set_property -dict { PACKAGE_PIN B8  IOSTANDARD LVCMOS33 } [get_ports { btn[3] }];

## ---- UART (USB-UART bridge for statistics output) ----
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports { uart_rxd_out }];

## ---- I/O Timing Constraints ----
## MII RX input timing (data valid within 10ns of rx_clk edge)
set_input_delay -clock mii_rx_clk -max 10.0 [get_ports { eth_rxd[*] eth_rx_dv eth_rx_er }];
set_input_delay -clock mii_rx_clk -min 0.0  [get_ports { eth_rxd[*] eth_rx_dv eth_rx_er }];

## RMII TX output timing
set_output_delay -clock rmii_clk -max 5.0  [get_ports { ja[0] ja[1] ja[2] }];
set_output_delay -clock rmii_clk -min -2.0 [get_ports { ja[0] ja[1] ja[2] }];

## ---- Clock Domain Crossing ----
## Async FIFO gray-code pointers — mark as false path
set_false_path -from [get_clocks mii_rx_clk] -to [get_clocks rmii_clk]
set_false_path -from [get_clocks rmii_clk]   -to [get_clocks mii_rx_clk]

## ---- Configuration ----
set_property CFGBVS VCCO [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design];
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design];
