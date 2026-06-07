#!/usr/bin/env python3
"""
Parse an Apple PacketLogger .pklg file and dump the bytes the iPhone
wrote to BLE GATT characteristics during a print job from the official
Peripage app.

Record format (little-endian length, big-endian timestamp):
    4-byte LE length         (length of timestamp + type + payload)
    4-byte BE seconds
    4-byte BE microseconds
    1-byte type
    N-byte payload

Type codes we care about:
    0x00 = HCI Command  (Host → Controller)
    0x01 = HCI Event    (Controller → Host)
    0x02 = HCI ACL Data — sent (Host → Controller, i.e. iPhone → printer)
    0x03 = HCI ACL Data — received (Controller → Host)
    0xfc = Diagnostic / annotation (Apple-specific text)

Inside ACL data is L2CAP, inside L2CAP is ATT for our purposes.

Run: python fixtures/parse_pklg.py <file.pklg>
"""
import struct
import sys
from pathlib import Path
from collections import defaultdict


def iter_records(data: bytes):
    off = 0
    while off + 4 <= len(data):
        (length,) = struct.unpack_from("<I", data, off)
        off += 4
        if length < 9 or off + length > len(data):
            break
        sec, usec = struct.unpack_from(">II", data, off)
        ptype = data[off + 8]
        payload = data[off + 9 : off + length]
        off += length
        yield sec + usec / 1_000_000, ptype, payload


def parse_acl(payload: bytes):
    # ACL header: 2-byte handle+flags, 2-byte data length
    if len(payload) < 4:
        return None
    handle_flags, dlen = struct.unpack_from("<HH", payload, 0)
    handle = handle_flags & 0x0FFF
    pb = (handle_flags >> 12) & 0x3
    bc = (handle_flags >> 14) & 0x3
    data = payload[4 : 4 + dlen]
    return handle, pb, bc, data


def parse_att(l2cap_payload: bytes):
    """L2CAP fragment payload: 2-byte length, 2-byte CID, then payload."""
    if len(l2cap_payload) < 4:
        return None
    _length, cid = struct.unpack_from("<HH", l2cap_payload, 0)
    if cid != 0x0004:  # ATT
        return None
    return l2cap_payload[4:]


# ATT opcodes
ATT_WRITE_REQ = 0x12
ATT_WRITE_RSP = 0x13
ATT_WRITE_CMD = 0x52  # write without response
ATT_HANDLE_VALUE_NTF = 0x1B
ATT_FIND_INFO_RSP = 0x05  # handle -> uuid mapping
ATT_READ_BY_TYPE_RSP = 0x09  # service discovery


def main():
    if len(sys.argv) != 2:
        print("Usage: parse_pklg.py <file.pklg>")
        sys.exit(1)
    path = Path(sys.argv[1])
    data = path.read_bytes()

    # Reassemble ACL fragments per connection per direction.
    # Key: (handle, direction) → bytes-so-far + expected-length
    ongoing = defaultdict(lambda: {"buf": b"", "want": 0})
    annotations = []
    writes_by_handle = defaultdict(list)  # handle → list of payloads
    notifies_by_handle = defaultdict(list)
    handle_to_uuid = {}

    for ts, ptype, payload in iter_records(data):
        if ptype == 0xFC:
            try:
                annotations.append(payload.decode("utf-8", errors="replace"))
            except Exception:
                pass
            continue
        if ptype not in (0x02, 0x03):
            continue
        acl = parse_acl(payload)
        if acl is None:
            continue
        handle, pb, _bc, body = acl
        direction = "tx" if ptype == 0x02 else "rx"
        key = (handle, direction)

        # PB flags:
        #   0x00 = start of NON-automatically-flushable L2CAP frame (BR/EDR)
        #   0x01 = continuation
        #   0x02 = start of automatically-flushable L2CAP frame (LE / BR-EDR)
        if pb in (0x00, 0x02):
            ongoing[key] = {"buf": body, "want": 0}
            if len(body) >= 2:
                l2cap_len = struct.unpack_from("<H", body, 0)[0]
                ongoing[key]["want"] = 4 + l2cap_len
        elif pb == 0x01:
            ongoing[key]["buf"] += body
        else:
            continue

        # Have a full L2CAP frame?
        if ongoing[key]["want"] and len(ongoing[key]["buf"]) >= ongoing[key]["want"]:
            frame = ongoing[key]["buf"][: ongoing[key]["want"]]
            ongoing[key] = {"buf": b"", "want": 0}
            att = parse_att(frame)
            if att is None or len(att) < 1:
                continue
            opcode = att[0]
            if opcode == ATT_WRITE_REQ or opcode == ATT_WRITE_CMD:
                if len(att) < 3:
                    continue
                handle_v = struct.unpack_from("<H", att, 1)[0]
                value = att[3:]
                writes_by_handle[handle_v].append((ts, value))
            elif opcode == ATT_HANDLE_VALUE_NTF:
                if len(att) < 3:
                    continue
                handle_v = struct.unpack_from("<H", att, 1)[0]
                value = att[3:]
                notifies_by_handle[handle_v].append((ts, value))
            elif opcode == ATT_FIND_INFO_RSP:
                # Format 0x01 = 16-bit UUID, format 0x02 = 128-bit UUID
                if len(att) < 2:
                    continue
                fmt = att[1]
                entry_size = 4 if fmt == 0x01 else 18
                off = 2
                while off + entry_size <= len(att):
                    hndl = struct.unpack_from("<H", att, off)[0]
                    uuid_bytes = att[off + 2 : off + entry_size]
                    if fmt == 0x01:
                        uuid = f"{struct.unpack_from('<H', uuid_bytes, 0)[0]:04X}"
                    else:
                        uuid = bytes(reversed(uuid_bytes)).hex()
                    handle_to_uuid[hndl] = uuid
                    off += entry_size

    print(f"=== Annotations ({len(annotations)}) ===")
    for a in annotations[:20]:
        print(f"  {a}")

    print(f"\n=== Handle → UUID map ({len(handle_to_uuid)} entries) ===")
    for h, u in sorted(handle_to_uuid.items()):
        print(f"  0x{h:04X} → {u}")

    print(f"\n=== Writes per handle ===")
    for h in sorted(writes_by_handle.keys()):
        chunks = writes_by_handle[h]
        total = sum(len(v) for _, v in chunks)
        uuid = handle_to_uuid.get(h, "?")
        print(f"  handle 0x{h:04X} ({uuid}): {len(chunks)} chunks, {total} bytes")
        if chunks and h not in (0x0011,):  # skip CCCD writes
            first = chunks[0][1]
            print(f"    first chunk ({len(first)}B): {first[:32].hex()}{'…' if len(first) > 32 else ''}")

    print(f"\n=== Notifications per handle ===")
    for h in sorted(notifies_by_handle.keys()):
        chunks = notifies_by_handle[h]
        total = sum(len(v) for _, v in chunks)
        uuid = handle_to_uuid.get(h, "?")
        print(f"  handle 0x{h:04X} ({uuid}): {len(chunks)} notifies, {total} bytes")
        if chunks:
            first_hexes = [v.hex() for _, v in chunks[:5]]
            print(f"    first samples: {first_hexes}")

    # Dump the largest write-handle as a .bin
    if writes_by_handle:
        biggest_h = max(writes_by_handle.keys(),
                        key=lambda h: sum(len(v) for _, v in writes_by_handle[h]))
        blob = b"".join(v for _, v in writes_by_handle[biggest_h])
        if blob:
            out = path.with_suffix(".bin")
            out.write_bytes(blob)
            print(f"\nWrote {len(blob)} bytes (handle 0x{biggest_h:04X}) → {out}")


if __name__ == "__main__":
    main()
