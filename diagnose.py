#!/usr/bin/env python3
"""
Peripage A6 diagnostic: try to make the printer do *something* and listen
for any notifications it sends back.

Tests three commands in sequence with pauses between:
    1. Reset
    2. Paper feed (ESC J 100) -- this should advance paper ~100 dots
    3. Print a single black row 48 bytes wide -- you should see a black line

Subscribes to notifications on ff01 and ff03 throughout, and prints anything
the printer says back.
"""

import asyncio
from bleak import BleakClient, BleakScanner

PRINTER_NAME_PREFIX = "PeriPage"
WRITE_UUID   = "0000ff02-0000-1000-8000-00805f9b34fb"
NOTIFY_FF01  = "0000ff01-0000-1000-8000-00805f9b34fb"
NOTIFY_FF03  = "0000ff03-0000-1000-8000-00805f9b34fb"


def on_notify_ff01(_, data: bytearray):
    print(f"  [ff01 notify] {data.hex()} ({bytes(data)!r})")


def on_notify_ff03(_, data: bytearray):
    print(f"  [ff03 notify] {data.hex()} ({bytes(data)!r})")


async def find_printer() -> str | None:
    print("Scanning...")
    devices = await BleakScanner.discover(timeout=8.0, return_adv=True)
    for addr, (device, adv) in devices.items():
        name = device.name or adv.local_name or ""
        if PRINTER_NAME_PREFIX.lower() in name.lower():
            return addr
    return None


async def write(client: BleakClient, label: str, data: bytes):
    print(f"\n>>> {label}: {data.hex()}")
    # Try chunking just in case, though these are small.
    CHUNK = 120
    for i in range(0, len(data), CHUNK):
        await client.write_gatt_char(WRITE_UUID, data[i:i+CHUNK], response=False)
        await asyncio.sleep(0.01)
    # Wait for any notification reply.
    await asyncio.sleep(0.5)


async def main():
    addr = await find_printer()
    if not addr:
        print("No printer found.")
        return

    print(f"Connecting to {addr}...")
    async with BleakClient(addr) as client:
        print(f"Connected. MTU: {client.mtu_size}")

        # Subscribe to both notify characteristics so we hear ANY response.
        try:
            await client.start_notify(NOTIFY_FF01, on_notify_ff01)
            print("Subscribed to ff01 notifications.")
        except Exception as e:
            print(f"Could not subscribe to ff01: {e}")
        try:
            await client.start_notify(NOTIFY_FF03, on_notify_ff03)
            print("Subscribed to ff03 notifications.")
        except Exception as e:
            print(f"Could not subscribe to ff03: {e}")

        await asyncio.sleep(0.5)

        # Test 1: peripage-python's "reset" sequence.
        # From bitrate16's source: 0x10 0xFF 0xFE 0x01
        await write(client, "RESET (10 ff fe 01)",
                    bytes.fromhex("10fffe01"))

        # Test 2: ESC J 100 -- standard ESC/POS paper feed by 100 dots.
        # If the printer advances paper here, our transport works and the
        # printer at least understands ESC/POS feed commands.
        await write(client, "PAPER FEED (ESC J 100)",
                    bytes.fromhex("1b4a64"))

        await asyncio.sleep(2.0)  # let it actually feed

        # Test 3: print a single black line.
        # Header: GS v 0 m xL xH yL yH  with m=0, xL=48 (bytes per row),
        # xH=0, yL=1, yH=0  (one row).
        # Then 48 bytes of 0xFF = all-black row.
        gs_v_0 = bytes.fromhex("1d76300030000100")
        black_row = b"\xff" * 48
        await write(client, "GS v 0 + 1 black row", gs_v_0 + black_row)

        # Test 4: alternate raw image format some firmwares use.
        # Some Peripage variants want a different prefix. Try the one from
        # peripage-python which uses 1d 76 30 00 then dimensions:
        await write(client, "RAW (1d 76 30 00 30 00 01 00) + black row",
                    bytes.fromhex("1d76300030000100") + black_row)

        # Test 5: feed more paper so we can see the result above the tear bar.
        await write(client, "FEED 200 dots",
                    bytes.fromhex("1b4ac8"))

        print("\nWaiting 3s for any final notifications...")
        await asyncio.sleep(3.0)

    print("\nDone.")
    print("Tell me:")
    print("  1. Did paper advance at all? (after RESET? after PAPER FEED?)")
    print("  2. Did you see any black line(s) on the paper?")
    print("  3. Paste any [ff01] or [ff03] notify lines from above.")


if __name__ == "__main__":
    asyncio.run(main())
