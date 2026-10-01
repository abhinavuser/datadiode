#!/usr/bin/env python3
"""
OT Sensor Simulator — Runs on PC_A (OT side)
==============================================
Generates simulated industrial sensor data (temperature, pressure, flow rate)
and sends it as UDP packets to the IT network through the FPGA data diode.

Usage:
    python sensor_simulator.py [--ip <target_ip>] [--port <port>] [--interval <seconds>]

Default: sends to 192.168.2.100:5000 every 1 second
"""

import socket
import json
import time
import random
import argparse
import sys
from datetime import datetime


def generate_sensor_data():
    """Generate realistic simulated sensor readings."""
    return {
        "timestamp": datetime.now().isoformat(),
        "sensor_id": f"OT-SENSOR-{random.randint(1, 5):03d}",
        "readings": {
            "temperature_C": round(random.uniform(20.0, 85.0), 2),
            "pressure_bar": round(random.uniform(1.0, 10.0), 2),
            "flow_rate_lpm": round(random.uniform(0.5, 50.0), 2),
            "vibration_mm_s": round(random.uniform(0.1, 5.0), 3),
            "humidity_pct": round(random.uniform(30.0, 90.0), 1),
        },
        "status": random.choice(["NORMAL", "NORMAL", "NORMAL", "WARNING", "CRITICAL"]),
        "sequence_no": 0,  # Will be updated
    }


def main():
    parser = argparse.ArgumentParser(description="OT Sensor Simulator for Data Diode Testing")
    parser.add_argument("--ip", default="192.168.2.100", help="Target IP (IT side PC_B)")
    parser.add_argument("--port", type=int, default=5000, help="Target UDP port")
    parser.add_argument("--interval", type=float, default=1.0, help="Send interval (seconds)")
    parser.add_argument("--count", type=int, default=0, help="Number of packets (0=infinite)")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    print(f"{'='*60}")
    print(f"  OT Sensor Simulator — FPGA Data Diode Test")
    print(f"{'='*60}")
    print(f"  Target:   {args.ip}:{args.port}")
    print(f"  Interval: {args.interval}s")
    print(f"  Count:    {'infinite' if args.count == 0 else args.count}")
    print(f"{'='*60}")
    print()

    seq = 0
    try:
        while True:
            data = generate_sensor_data()
            data["sequence_no"] = seq

            payload = json.dumps(data).encode("utf-8")
            sock.sendto(payload, (args.ip, args.port))

            status_char = "✓" if data["status"] == "NORMAL" else "⚠" if data["status"] == "WARNING" else "✗"
            print(f"  [{seq:06d}] {status_char} {data['sensor_id']} | "
                  f"T={data['readings']['temperature_C']:5.1f}°C  "
                  f"P={data['readings']['pressure_bar']:4.1f}bar  "
                  f"F={data['readings']['flow_rate_lpm']:5.1f}L/min  "
                  f"[{len(payload)}B sent]")

            seq += 1
            if args.count > 0 and seq >= args.count:
                break

            time.sleep(args.interval)

    except KeyboardInterrupt:
        print(f"\n  Stopped. Total packets sent: {seq}")
    finally:
        sock.close()


if __name__ == "__main__":
    main()
