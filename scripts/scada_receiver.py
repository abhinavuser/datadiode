#!/usr/bin/env python3
# scada_receiver.py
# receives sensor data from the ot network through the fpga data diode
# displays it in a live dashboard format.

import socket
import json
import time
import sys
import argparse
from datetime import datetime
from collections import defaultdict

def print_dashboard(stats, last_data, start_time):
    elapsed = time.time() - start_time
    rate = stats["total"] / elapsed if elapsed > 0 else 0

    print("\033[2J\033[H", end="")

    print("=" * 60)
    print("  scada dashboard -> fpga data diode receiver")
    print("=" * 60)
    print(f"  running: {elapsed:.0f}s | packets: {stats['total']} | rate: {rate:.1f} pkt/s")
    print(f"  lost: {stats['lost']} | warnings: {stats['warnings']} | critical: {stats['critical']}")
    print("=" * 60)
    print()

    if last_data:
        readings = last_data.get("readings", {})
        print(f"  latest reading ({last_data.get('sensor_id', 'unknown')}):")
        print(f"    temperature: {readings.get('temperature_C', 0):.1f} c")
        print(f"    pressure:    {readings.get('pressure_bar', 0):.1f} bar")
        print(f"    flow rate:   {readings.get('flow_rate_lpm', 0):.1f} lpm")
        print(f"    status:      {last_data.get('status', 'UNKNOWN')}")
        print(f"    seq #:       {last_data.get('sequence_no', 0)}")
    print()
    print("  per-sensor counts:")
    for sensor_id, count in sorted(stats["sensors"].items()):
        print(f"    {sensor_id}: {count} packets")
    print("\n  press ctrl+c to stop")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--log", default=None)
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.bind, args.port))
    sock.settimeout(2.0)

    log_file = open(args.log, "a") if args.log else None

    stats = {
        "total": 0, "lost": 0, "warnings": 0, "critical": 0,
        "sensors": defaultdict(int),
    }
    last_data = None
    last_seq = -1
    start_time = time.time()

    print(f"listening on {args.bind}:{args.port}...")

    try:
        while True:
            try:
                raw, _ = sock.recvfrom(4096)
                data = json.loads(raw.decode("utf-8"))

                stats["total"] += 1
                sensor_id = data.get("sensor_id", "unknown")
                stats["sensors"][sensor_id] += 1

                seq = data.get("sequence_no", 0)
                if last_seq >= 0 and seq > last_seq + 1:
                    stats["lost"] += seq - last_seq - 1
                last_seq = seq

                status = data.get("status", "NORMAL")
                if status == "WARNING": stats["warnings"] += 1
                elif status == "CRITICAL": stats["critical"] += 1

                last_data = data
                if log_file:
                    log_file.write(json.dumps(data) + "\n")
                    log_file.flush()

                print_dashboard(stats, last_data, start_time)

            except socket.timeout:
                print_dashboard(stats, last_data, start_time)

    except KeyboardInterrupt:
        elapsed = time.time() - start_time
        print("\n\n" + "=" * 60)
        print("  session summary")
        print("=" * 60)
        print(f"  duration:      {elapsed:.1f}s")
        print(f"  total packets: {stats['total']}")
        print(f"  lost packets:  {stats['lost']}")
        print("=" * 60)
    finally:
        if log_file: log_file.close()
        sock.close()

if __name__ == "__main__":
    main()
