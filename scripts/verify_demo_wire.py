"""Audit the autonomous eight-port demo's emitted Ethernet frames."""
import binascii
import json
import sys
from pathlib import Path
from verify_service_wire import checksum, status_file


def audit(path):
    vl_sequences = {}
    business = loaded = ntp = final = 0
    names = set()
    for line in path.read_text().splitlines():
        raw = bytes.fromhex(line)
        assert raw[:8] == bytes.fromhex('55555555555555d5'), 'preamble'
        body = raw[8:-4]
        assert binascii.crc32(body) == int.from_bytes(raw[-4:], 'little'), 'FCS'
        assert body[12:15] == b'\x08\x00\x45', 'IPv4'
        assert checksum(body[14:34]) == 65535, 'IP checksum'
        ip_length = int.from_bytes(body[16:18], 'big')
        udp_length = int.from_bytes(body[38:40], 'big')
        assert ip_length == udp_length + 20 and 8 <= udp_length <= 524, 'length'
        assert len(body) == max(60, 43 + udp_length - 8), 'AFDX sequence position'
        route = int.from_bytes(body[:6], 'big')
        seq = body[-1]
        expected = 0 if route not in vl_sequences else (1 if vl_sequences[route] == 255 else vl_sequences[route] + 1)
        assert seq == expected, ('sequence', route, seq, expected)
        vl_sequences[route] = seq
        payload = body[42:42 + udp_length - 8]
        sport = int.from_bytes(body[34:36], 'big')
        dport = int.from_bytes(body[36:38], 'big')
        if 0x030000000040 <= route <= 0x030000000043:
            business += 1
            assert len(payload) == 16 and payload[:4] == b'AFDX', 'business payload'
            loaded += bool(payload[12] & 2)
        elif dport == 123:
            ntp += 1
            assert sport == 40001 and len(payload) == 48 and payload[0] == 0x23, 'NTP'
        elif payload[:2] == b'\x00\x01':
            names.add(payload[2:].split(b'\x00')[0].decode('ascii'))
        elif sport == 40002 and payload[:4] == b'\x00\x03\x00\x01':
            final += status_file(payload[4:])['status'] == 3
    assert business >= 4 and loaded >= 4 and ntp >= 1, 'autonomous traffic'
    assert names == {'APP.LUH', 'A.LUP', 'B.LUP'} and final == 1, 'package transaction'
    result = dict(status='PASS', business_frames=business, loaded_status_frames=loaded,
                  ntp_requests=ntp, package_files=sorted(names), final_reports=final)
    path.with_suffix('.audit.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    print('DEMO_WIRE_AUDIT_PASS', json.dumps(audit(Path(sys.argv[1]))))
