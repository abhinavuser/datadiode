#!/usr/bin/env python3
# sensor_simulator.py
# generates simulated ot sensor data (temperature, pressure, etc.)
# sends it as udp packets to the it network through the fpga data diode.

import socket
import json
import time
import random
import argparse
import sys
from datetime import datetime

def generate_sensor_data():
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
        "sequence_no": 0,
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ip", default="192.168.2.100")
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--count", type=int, default=0)
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    print("=" * 60)
    print("  ot sensor simulator -> fpga data diode test")
    print("=" * 60)
    print(f"  target:   {args.ip}:{args.port}")
    print(f"  interval: {args.interval}s")
    print(f"  count:    {'infinite' if args.count == 0 else args.count}")
    print("=" * 60)
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
                  f"t={data['readings']['temperature_C']:5.1f}C "
                  f"p={data['readings']['pressure_bar']:4.1f}bar "
                  f"[{len(payload)}b sent]")

            seq += 1
            if args.count > 0 and seq >= args.count:
                break
            time.sleep(args.interval)

    except KeyboardInterrupt:
        print(f"\n  stopped. packets sent: {seq}")
    finally:
        sock.close()

if __name__ == "__main__":
    main()
