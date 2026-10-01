#!/usr/bin/env python3
"""
IT SCADA Receiver — Runs on PC_B (IT side)
==========================================
Receives sensor data from the OT network through the FPGA data diode
and displays it in a live dashboard format.

Usage:
    python scada_receiver.py [--port <port>]

Default: listens on UDP port 5000
"""

import socket
import json
import time
import sys
import argparse
from datetime import datetime
from collections import defaultdict


def print_dashboard(stats, last_data, start_time):
    """Print a live dashboard of received sensor data."""
    elapsed = time.time() - start_time
    rate = stats["total"] / elapsed if elapsed > 0 else 0

    # Clear screen (cross-platform)
    print("\033[2J\033[H", end="")

    print(f"{'='*70}")
    print(f"  📊 SCADA Dashboard — FPGA Data Diode Receiver")
    print(f"{'='*70}")
    print(f"  Running for: {elapsed:.0f}s | Packets: {stats['total']} | "
          f"Rate: {rate:.1f} pkt/s")
    print(f"  Lost packets: {stats['lost']} | "
          f"Warnings: {stats['warnings']} | "
          f"Critical: {stats['critical']}")
    print(f"{'='*70}")
    print()

    if last_data:
        print(f"  Latest Reading ({last_data.get('sensor_id', 'unknown')}):")
        print(f"  ┌{'─'*50}┐")
        readings = last_data.get("readings", {})
        print(f"  │ Temperature:  {readings.get('temperature_C', 0):6.1f} °C"
              f"{' ':>18}│")
        print(f"  │ Pressure:     {readings.get('pressure_bar', 0):6.1f} bar"
              f"{' ':>17}│")
        print(f"  │ Flow Rate:    {readings.get('flow_rate_lpm', 0):6.1f} L/min"
              f"{' ':>14}│")
        print(f"  │ Vibration:    {readings.get('vibration_mm_s', 0):6.3f} mm/s"
              f"{' ':>15}│")
        print(f"  │ Humidity:     {readings.get('humidity_pct', 0):6.1f} %"
              f"{' ':>19}│")
        print(f"  │ Status:       {last_data.get('status', 'UNKNOWN'):<20}"
              f"{' ':>15}│")
        print(f"  │ Seq #:        {last_data.get('sequence_no', 0):<20}"
              f"{' ':>15}│")
        print(f"  └{'─'*50}┘")
    print()
    print(f"  Per-sensor packet counts:")
    for sensor_id, count in sorted(stats["sensors"].items()):
        print(f"    {sensor_id}: {count} packets")
    print()
    print(f"  Press Ctrl+C to stop")


def main():
    parser = argparse.ArgumentParser(description="SCADA Receiver for Data Diode Testing")
    parser.add_argument("--port", type=int, default=5000, help="Listen UDP port")
    parser.add_argument("--bind", default="0.0.0.0", help="Bind address")
    parser.add_argument("--log", default=None, help="Log file path")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.bind, args.port))
    sock.settimeout(2.0)

    log_file = None
    if args.log:
        log_file = open(args.log, "a")

    stats = {
        "total": 0,
        "lost": 0,
        "warnings": 0,
        "critical": 0,
        "sensors": defaultdict(int),
    }
    last_data = None
    last_seq = -1
    start_time = time.time()

    print(f"Listening on {args.bind}:{args.port}...")

    try:
        while True:
            try:
                raw, addr = sock.recvfrom(4096)
                data = json.loads(raw.decode("utf-8"))

                stats["total"] += 1
                sensor_id = data.get("sensor_id", "unknown")
                stats["sensors"][sensor_id] += 1

                seq = data.get("sequence_no", 0)
                if last_seq >= 0 and seq > last_seq + 1:
                    stats["lost"] += seq - last_seq - 1
                last_seq = seq

                status = data.get("status", "NORMAL")
                if status == "WARNING":
                    stats["warnings"] += 1
                elif status == "CRITICAL":
                    stats["critical"] += 1

                last_data = data

                if log_file:
                    log_file.write(json.dumps(data) + "\n")
                    log_file.flush()

                # Update dashboard every packet
                print_dashboard(stats, last_data, start_time)

            except socket.timeout:
                print_dashboard(stats, last_data, start_time)

    except KeyboardInterrupt:
        elapsed = time.time() - start_time
        print(f"\n\n{'='*60}")
        print(f"  Session Summary")
        print(f"{'='*60}")
        print(f"  Duration:       {elapsed:.1f}s")
        print(f"  Total Packets:  {stats['total']}")
        print(f"  Lost Packets:   {stats['lost']}")
        print(f"  Throughput:     {stats['total']/elapsed:.1f} pkt/s" if elapsed > 0 else "")
        print(f"{'='*60}")
    finally:
        if log_file:
            log_file.close()
        sock.close()


if __name__ == "__main__":
    main()
