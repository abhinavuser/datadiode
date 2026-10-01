# fpga-based data diode 

### the problem
in industrial environments (factories, power plants, water treatment), there are two separate networks:
- **ot network** (operational technology) — controls machines, plcs, sensors
- **it network** (information technology) — office computers, databases, cloud monitoring

these networks must be separated for security. if a hacker gets into the it network, they should never be able to reach back into the ot machines and cause damage.

we build this one-way valve using:
1. **arty a7-100t** — our fpga board (xilinx artix-7)
2. **lan8720 module** — a second ethernet port (because the arty only has one built-in)
3. **vhdl code** — the hardware logic programmed into the fpga

---

## the netherlands open source data diode (osdd)

the open source data diode (osdd) was created by the netherlands ministry of defence. 
github: https://github.com/CyberInnovationHub-NLD/OpenSourceDataDiode

### how their diode works (hardware level)
1. phy_a receives ethernet frames from pc_a (ot side)
2. fpga logic captures these signals and directly drives phy_b's tx pins
3. phy_b has NO rx connection — its receive pins are simply not connected
4. phy_b transmits the frame out to pc_b (it side)

**the key security guarantee**: phy_b's rx pins are not connected to anything in the fpga. even if phy_b receives frames from pc_b, they have nowhere to go. this is a hardware-level guarantee - no software bug can break it.

---


### side-by-side comparison

| aspect | dutch osdd | our project |
|--------|-----------|-------------|
| **fpga** | intel max10 | **xilinx artix-7** (arty a7-100t) |
| **rx phy** | marvell 88e1111 | **realtek rtl8211e** (on arty, mii) |
| **tx phy** | marvell 88e1111 | **lan8720** (external, rmii) |
| **rx interface** | mii (4-bit @ 25 mhz) | **mii** (4-bit @ 25 mhz) |
| **tx interface** | mii (4-bit @ 25 mhz) | **rmii** (2-bit @ 50 mhz) — different! |
| **diode logic** | pass-through only | **parse + filter + crc + stats** |
| **software** | rust proxy framework | **python sensor sim + scada dashboard** |

### what we add beyond the dutch design
our enhancements over the dutch design:
- **packet parser**: extracts ethernet type, ip protocol, ports
- **security filter**: allow/drop based on rules (allows udp, blocks tcp/icmp)
- **fifo buffer**: cross-clock-domain buffering (mii to rmii)
- **crc/integrity check**: validates frame crc32 before forwarding
- **statistics**: packet counts, drop counts via uart

---

## hardware wiring (lan8720 to arty a7 pmod ja)

```
lan8720 module          arty a7 pmod ja
-------------          ----------------
txd0          <------  ja[1] (pin g13)
txd1          <------  ja[2] (pin b11)
tx_en         <------  ja[3] (pin a11)
nint/refclk   ------>  ja[4] (pin d12)  (50 mhz ref clock from fpga)
rxd0          ------>  ja[7] (pin d13)  (not used — diode blocks rx)
rxd1          ------>  ja[8] (pin b18)  (not used)
crs_dv        ------>  ja[9] (pin a18)  (not used)
mdio          <----->  ja[10](pin k16)
mdc           <------  jb[1] (pin e15)
gnd           <------  gnd
vcc (3.3v)    <------  3v3
```

the lan8720's rxd0, rxd1, crs_dv pins are intentionally NOT connected to any fpga logic. this is what creates the hardware-enforced one-way path.

---

## testing plan

### test 1: unidirectional flow (ot -> it)
**purpose**: prove data flows from pc_a to pc_b through the fpga
```bash
# on pc_a (ot side, connected to arty onboard ethernet):
python3 scripts/sensor_simulator.py

# on pc_b (it side, connected to lan8720):
python3 scripts/scada_receiver.py
```
**expected result**: pc_b receives all udp packets sent by pc_a

### test 2: reverse path blocking (it -> ot)
**purpose**: prove data CANNOT flow from pc_b back to pc_a
```bash
# on pc_b (it side):
ping <pc_a_ip>

# on pc_a (ot side):
wireshark  # capture — should see NOTHING from pc_b
```
**expected result**: 0 packets received on pc_a from pc_b. ping gets no response.

### test 3: packet filtering
**purpose**: prove the security filter correctly blocks unwanted protocols
```bash
# on pc_a: send blocked traffic
python3 scripts/sensor_simulator.py --port 80

# on pc_b: check what arrives
wireshark
```
**expected result**: port 80 packets are dropped by the fpga.
