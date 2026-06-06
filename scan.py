#!/usr/bin/env python3
"""
Peripage A6 BLE recon script.

Step 1: Scans for nearby BLE devices and looks for anything Peripage-shaped.
Step 2: Connects to it and enumerates all services + characteristics.

Run with:
    python scan.py

Prerequisites:
    - Printer is powered on
    - Printer is NOT currently connected to your phone (BLE only allows one
      central at a time; if the iOS Peripage app is connected, kill it first)
    - Terminal has Bluetooth permission in macOS Settings > Privacy & Security
"""

import asyncio
from bleak import BleakScanner, BleakClient


async def find_printer():
    print("Scanning for BLE devices for 8 seconds...")
    print("(Make sure the printer is on and NOT connected to your phone.)\n")

    devices = await BleakScanner.discover(timeout=8.0, return_adv=True)

    if not devices:
        print("No BLE devices found at all. Check:")
        print("  1. Bluetooth is on (System Settings > Bluetooth)")
        print("  2. Terminal has Bluetooth permission")
        print("     (System Settings > Privacy & Security > Bluetooth)")
        return None

    print(f"Found {len(devices)} device(s):\n")
    candidates = []
    for addr, (device, adv) in devices.items():
        name = device.name or adv.local_name or "<no name>"
        rssi = adv.rssi if adv.rssi is not None else "?"
        print(f"  {addr}  RSSI={rssi}  name={name}")
        if name and "peri" in name.lower():
            candidates.append((addr, name))

    print()
    if not candidates:
        print("No device with 'Peri' in its name was found.")
        print("If your printer shows up above with a different name, paste this")
        print("whole output to Bryan and we'll pick it manually.")
        return None

    if len(candidates) > 1:
        print(f"Found multiple Peripage candidates: {candidates}")
        print("Using the first one.")

    addr, name = candidates[0]
    print(f"Selected: {name} @ {addr}\n")
    return addr


async def enumerate_services(address: str):
    print(f"Connecting to {address}...")
    async with BleakClient(address) as client:
        if not client.is_connected:
            print("Failed to connect.")
            return

        print(f"Connected. MTU (negotiated max packet size): {client.mtu_size}\n")
        print("=" * 70)
        print("SERVICES AND CHARACTERISTICS")
        print("=" * 70)

        for service in client.services:
            print(f"\n[Service] {service.uuid}")
            print(f"  Description: {service.description}")
            for char in service.characteristics:
                props = ",".join(char.properties)
                print(f"  [Char] {char.uuid}")
                print(f"    Handle: {char.handle}  Properties: {props}")
                print(f"    Description: {char.description}")
                for desc in char.descriptors:
                    print(f"    [Descriptor] {desc.uuid} (handle {desc.handle})")

        print("\n" + "=" * 70)
        print("DONE. Copy ALL output above (from 'Scanning' onward) and paste")
        print("it back so we can identify the write characteristic.")
        print("=" * 70)


async def main():
    address = await find_printer()
    if not address:
        return
    try:
        await enumerate_services(address)
    except Exception as e:
        print(f"\nError during enumeration: {e}")
        print("If this says something about pairing, try removing the printer")
        print("from System Settings > Bluetooth and re-running.")


if __name__ == "__main__":
    asyncio.run(main())