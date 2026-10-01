# fpga data diode

hardware-enforced unidirectional gateway (data diode) implemented on a xilinx artix-7 fpga (arty a7-100t). inspired by the netherlands open source data diode, but enhanced with packet parsing, security filtering, and crc checking.

## hardware setup
- **board:** digilent arty a7-100t
- **rx (ot side):** onboard rtl8211e phy (mii)
- **tx (it side):** lan8720 module via pmod ja (rmii)

**security guarantee:** the lan8720 rx pins are physically connected to the pmod port but are never mapped or read by the fpga logic. no reverse data path exists.

## project structure
- `hdl/src/` - vhdl source files
- `hdl/sim/` - testbenches
- `hdl/constraints/` - xdc pin mappings
- `scripts/` - python test scripts (sensor simulator & scada receiver)
- `docs/` - reference papers and diagrams
- `vivado/` - build directory (run tcl script here)

## how to build
1. open vivado 2024
2. run in tcl console:
   ```tcl
   cd E:/datadiode/vivado
   source ../hdl/build_project.tcl
   ```
3. program the generated bitstream to the arty a7.

## how to test
1. connect pc 1 (ot) to the arty onboard ethernet.
2. connect pc 2 (it) to the lan8720 module.
3. on pc 2 run: `python scripts/scada_receiver.py`
4. on pc 1 run: `python scripts/sensor_simulator.py --ip <pc2_ip>`
