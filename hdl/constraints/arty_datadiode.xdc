# arty_datadiode.xdc
# constraints for arty a7-100t data diode

# 100 mhz system clock
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }];
create_clock -name sys_clk -period 10.000 [get_ports { CLK100MHZ }];

# onboard phy (rtl8211e) rx pins only
set_property -dict { PACKAGE_PIN F15 IOSTANDARD LVCMOS33 } [get_ports { eth_rx_clk }];
set_property -dict { PACKAGE_PIN G16 IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[0] }];
set_property -dict { PACKAGE_PIN H14 IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[1] }];
set_property -dict { PACKAGE_PIN J14 IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[2] }];
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[3] }];
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports { eth_rx_dv }];
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 } [get_ports { eth_rx_er }];

set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports { eth_rstn }];
set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 } [get_ports { eth_mdc }];
set_property -dict { PACKAGE_PIN K14 IOSTANDARD LVCMOS33 } [get_ports { eth_mdio }];

create_clock -name mii_rx_clk -period 40.000 [get_ports { eth_rx_clk }];

# pmod ja: lan8720 tx pins only
set_property -dict { PACKAGE_PIN G13 IOSTANDARD LVCMOS33 } [get_ports { ja[0] }]; # txd0
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports { ja[1] }]; # txd1
set_property -dict { PACKAGE_PIN A11 IOSTANDARD LVCMOS33 } [get_ports { ja[2] }]; # tx_en
set_property -dict { PACKAGE_PIN D12 IOSTANDARD LVCMOS33 } [get_ports { ja[3] }]; # ref_clk
set_property -dict { PACKAGE_PIN D13 IOSTANDARD LVCMOS33 } [get_ports { ja[4] }];
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports { ja[5] }];
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports { ja[6] }];
set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports { ja[7] }];

# pmod jb: lan8720 mdc
set_property -dict { PACKAGE_PIN E15 IOSTANDARD LVCMOS33 } [get_ports { jb[0] }];
set_property -dict { PACKAGE_PIN E16 IOSTANDARD LVCMOS33 } [get_ports { jb[1] }];
set_property -dict { PACKAGE_PIN D15 IOSTANDARD LVCMOS33 } [get_ports { jb[2] }];
set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 } [get_ports { jb[3] }];
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports { jb[4] }];
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports { jb[5] }];
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { jb[6] }];
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports { jb[7] }];

# rmii clock
create_generated_clock -name rmii_clk -source [get_ports CLK100MHZ] \
    -divide_by 2 [get_pins {clk50_toggle_reg/Q}]

# leds, sw, btn
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

set_property -dict { PACKAGE_PIN A8  IOSTANDARD LVCMOS33 } [get_ports { sw[0] }];
set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports { sw[1] }];
set_property -dict { PACKAGE_PIN C10 IOSTANDARD LVCMOS33 } [get_ports { sw[2] }];
set_property -dict { PACKAGE_PIN A10 IOSTANDARD LVCMOS33 } [get_ports { sw[3] }];

set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports { btn[0] }];
set_property -dict { PACKAGE_PIN C9  IOSTANDARD LVCMOS33 } [get_ports { btn[1] }];
set_property -dict { PACKAGE_PIN B9  IOSTANDARD LVCMOS33 } [get_ports { btn[2] }];
set_property -dict { PACKAGE_PIN B8  IOSTANDARD LVCMOS33 } [get_ports { btn[3] }];

# uart
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports { uart_rxd_out }];

# timing
set_input_delay -clock mii_rx_clk -max 10.0 [get_ports { eth_rxd[*] eth_rx_dv eth_rx_er }];
set_input_delay -clock mii_rx_clk -min 0.0  [get_ports { eth_rxd[*] eth_rx_dv eth_rx_er }];

set_output_delay -clock rmii_clk -max 5.0  [get_ports { ja[0] ja[1] ja[2] }];
set_output_delay -clock rmii_clk -min -2.0 [get_ports { ja[0] ja[1] ja[2] }];

set_false_path -from [get_clocks mii_rx_clk] -to [get_clocks rmii_clk]
set_false_path -from [get_clocks rmii_clk]   -to [get_clocks mii_rx_clk]

set_property CFGBVS VCCO [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design];
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design];
