"""Read a frozen A/B conflict using an integrator-supplied read32 callback."""
import json
from pathlib import Path


def snapshot(read32):
    if not read32(0x2000) & 1:
        return None
    first_len, second_len = read32(0x2008), read32(0x200c)
    if not (72 <= first_len <= 1536 and 72 <= second_len <= 1536):
        raise ValueError('invalid evidence lengths')
    def raw(base, length):
        return b''.join(read32(base + i).to_bytes(4, 'little')
                        for i in range(0, (length + 3) // 4 * 4, 4))[:length]
    first, second = raw(0x2100, first_len), raw(0x2900, second_len)
    differences = []
    for i in range(8, max(first_len, second_len) - 4):
        a = first[i] if i < first_len - 4 else None
        b = second[i] if i < second_len - 4 else None
        if i == 19 and a is not None and b is not None:
            a, b = a & 0x9f, b & 0x9f
        if a != b:
            differences.append({'wire_offset': i, 'first': a, 'second': b})
    route = read32(0x2028)
    return dict(first_wire_hex=first.hex(), second_wire_hex=second.hex(),
                first_length=first_len, second_length=second_len,
                first_cycle=read32(0x2010) | read32(0x2014) << 32,
                second_cycle=read32(0x2018) | read32(0x201c) << 32,
                first_difference=read32(0x2004), differences=differences,
                epoch=read32(0x2024), rule=route >> 2 & 15,
                second_channel=route & 3, lost=read32(0x2020))


def save(record, directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    for name in ('first', 'second'):
        (directory / (name + '_wire.bin')).write_bytes(
            bytes.fromhex(record[name + '_wire_hex']))
    (directory / 'evidence.json').write_text(
        json.dumps(record, indent=2) + '\n', encoding='utf8')
    # Only AFTER a successful durable export should the caller acknowledge:
    # write32(0x2000, 0x41434b31). No acknowledgement is hidden in this function.
