"""Audit captured MAC bytes independently of the RTL/peer packet builders.

The acceptance fixture is one A4 upload of APP.LUH plus A.LUP/B.LUP and
one NTP exchange. Missing packets, stale single-image checks, incomplete
TFTP transfers, or unmatched NTP replies must never produce PASS.
"""
from pathlib import Path
import argparse
import binascii
import json
import struct


def require(condition, message):
    if not condition:
        raise ValueError(message)


def checksum(data):
    data += b'\0' * (len(data) % 2)
    value = sum(int.from_bytes(data[i:i+2], 'big') for i in range(0, len(data), 2))
    while value >> 16:
        value = (value & 65535) + (value >> 16)
    return value


def load_crc32(data, value=0xffffffff):
    for byte in data:
        value ^= byte << 24
        for _ in range(8):
            value = ((value << 1) ^ (0x04c11db7 if value & 0x80000000 else 0)) & 0xffffffff
    return value


def zstring(buf, pos):
    require(pos < len(buf), 'A4 string length missing')
    n = buf[pos]
    pos += 1
    require(n >= 1 and pos+n <= len(buf), 'A4 string boundary')
    value = buf[pos:pos+n]
    require(value[-1] == 0 and 0 not in value[:-1], 'A4 string termination')
    return value[:-1].decode('ascii'), pos+n


def status_file(buf):
    require(int.from_bytes(buf[:4], 'big') == len(buf) and buf[4:6] == b'A4', 'LUS header')
    status = int.from_bytes(buf[6:8], 'big')
    description, pos = zstring(buf, 8)
    require(pos+11 <= len(buf), 'LUS fixed fields')
    counter = int.from_bytes(buf[pos:pos+2], 'big')
    pos += 6  # counter, exception timer, estimated time
    ratio = buf[pos:pos+3].decode('ascii')
    require(ratio.isdigit() and 0 <= int(ratio) <= 100, 'LUS progress')
    pos += 3
    n = int.from_bytes(buf[pos:pos+2], 'big')
    pos += 2
    files = []
    for _ in range(n):
        name, pos = zstring(buf, pos)
        part, pos = zstring(buf, pos)
        file_ratio = buf[pos:pos+3].decode('ascii')
        pos += 3
        code = int.from_bytes(buf[pos:pos+2], 'big')
        pos += 2
        desc, pos = zstring(buf, pos)
        require(file_ratio.isdigit() and 0 <= int(file_ratio) <= 100, 'LUS file progress')
        files.append(dict(name=name, part=part, ratio=int(file_ratio), status=code, description=desc))
    require(pos == len(buf) and len(files) == 1, 'LUS file count/trailing bytes')
    return dict(status=status, counter=counter, ratio=int(ratio), files=files, description=description)


def validate_package(files):
    header = files['APP.LUH']
    require(len(header) == 126 and int.from_bytes(header[:4], 'big')*2 == len(header), 'LUH length')
    require(header[4:8] == b'\x80\x04\0\0', 'LUH format')
    require(binascii.crc_hqx(header[:-6], 65535) == int.from_bytes(header[-6:-4], 'big'), 'LUH CRC16')
    def word_string(pos):
        n = int.from_bytes(header[pos:pos+2], 'big')
        require(n > 0 and pos+2+n <= len(header)-6, 'LUH string bounds')
        return header[pos+2:pos+2+n].decode('ascii'), pos+2+((n+1)//2)*2
    part, _ = word_string(int.from_bytes(header[8:12], 'big')*2)
    hw = int.from_bytes(header[12:16], 'big')*2
    hardware, _ = word_string(hw+2)
    require(part == 'PN-1' and int.from_bytes(header[hw:hw+2], 'big') == 1 and hardware == 'SIM', 'LUH identity')
    pos = int.from_bytes(header[16:20], 'big')*2
    require(int.from_bytes(header[pos:pos+2], 'big') == 2, 'LUH data file count')
    pos += 2
    crc = load_crc32(header[:-4])
    rows = []
    for index, expected_name in enumerate(('A.LUP', 'B.LUP')):
        start = pos
        next_words = int.from_bytes(header[pos:pos+2], 'big')
        name, pos = word_string(pos+2)
        part, pos = word_string(pos)
        require(name == expected_name and part == 'PN-1', 'LUH data file identity')
        data = files[name]
        require(int.from_bytes(header[pos:pos+4], 'big')*2 == len(data), 'LUH word length')
        require(int.from_bytes(header[pos+10:pos+14], 'big') == len(data), 'LUH byte length')
        expected_crc = int.from_bytes(header[pos+4:pos+6], 'big')
        require(binascii.crc_hqx(data, 65535) == expected_crc, name+' CRC16')
        require(header[pos+6:pos+10] == bytes(4) and header[pos+14:pos+16] == bytes(2), 'LUH unsupported fields')
        pos += 16
        require((next_words == 0 and pos == len(header)-6) if index == 1 else start+next_words*2 == pos, 'LUH next entry')
        crc = load_crc32(data, crc)
        rows.append(dict(name=name, bytes=len(data), crc16=f'{expected_crc:04x}'))
    crc ^= 0xffffffff
    require(crc == int.from_bytes(header[-4:], 'big'), 'whole-package CRC32')
    require(files['A.LUP'] == bytes((3+7*i)&255 for i in range(700)), 'A.LUP payload')
    require(files['B.LUP'] == bytes((225-3*i)&255 for i in range(1024)), 'B.LUP payload')
    return rows, f'{crc:08x}'


def audit(path):
    path = Path(path)
    flows, lui, lus, requests, ntp_requests, ntp_replies = [], [], [], [], [], []
    downloads = {}
    records = bytearray(struct.pack('<IHHIIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1))
    final_lus_acked = False
    for line in path.read_text().splitlines():
        direction, timestamp, hexdata = line.split()
        require(direction in ('TARGET', 'PEER'), 'capture direction')
        raw = bytes.fromhex(hexdata)
        require(raw[:8] == b'\x55'*7+b'\xd5', 'preamble')
        frame = raw[8:-4]
        require(binascii.crc32(frame).to_bytes(4, 'little') == raw[-4:], 'FCS')
        require(60 <= len(frame) <= 1514 and frame[12:14] == b'\x08\x00', 'Ethernet length/type')
        ip = frame[14:34]
        require(ip[0] == 0x45 and ip[9] == 17 and checksum(ip) == 65535, 'IPv4 header/checksum')
        require(int.from_bytes(ip[6:8], 'big') & 0x3fff == 0, 'fragmented service packet')
        ip_len = int.from_bytes(ip[2:4], 'big')
        require(28 <= ip_len <= len(frame)-15, 'IPv4 length/AFDX sequence')
        udp = frame[34:14+ip_len]
        sp, dp, ul, ck = struct.unpack('!HHHH', udp[:8])
        require(ul == len(udp), 'UDP length')
        if ck:
            require(checksum(ip[12:20]+b'\0\x11'+udp[4:6]+udp) == 65535, 'UDP checksum')
        body = udp[8:]
        sec, usec = int(timestamp)//10**12, (int(timestamp)%10**12)//10**6
        records.extend(struct.pack('<IIII', sec, usec, len(frame), len(frame)))
        records.extend(frame)
        flows.append(dict(direction=direction, source_port=sp, destination_port=dp, length=len(body)))
        if sp == 123 or dp == 123:
            require(len(body) == 48, 'NTP length')
            if direction == 'TARGET':
                require(sp == 40001 and dp == 123 and body[0] == 0x23, 'NTP request endpoints/mode')
                require(body[40:48] != bytes(8), 'NTP request timestamp')
                ntp_requests.append((body[40:48], ip[12:16], ip[16:20]))
            else:
                require(sp == 123 and dp == 40001, 'NTP reply ports')
                require(body[0] & 0x3f == 0x24 and body[0] >> 6 != 3 and 1 <= body[1] <= 15, 'NTP reply flags/stratum')
                require((body[24:32], ip[16:20], ip[12:16]) in ntp_requests, 'NTP origin/endpoints mismatch')
                require(0 < int.from_bytes(body[32:40], 'big') <= int.from_bytes(body[40:48], 'big'), 'NTP server timestamps')
                ntp_replies.append(body)
            continue
        require(len(body) >= 4, 'TFTP header')
        opcode = int.from_bytes(body[:2], 'big')
        if opcode in (1, 2):
            filename, mode, empty = body[2:].split(b'\0')
            name = filename.decode('ascii')
            require(dp == 69 and mode == b'octet' and empty == b'' and name, 'TFTP request')
            requests.append((direction, opcode, name))
            if direction == 'TARGET' and opcode == 1:
                require(name in ('APP.LUH', 'A.LUP', 'B.LUP') and sp not in downloads, 'package RRQ/TID')
                downloads[sp] = dict(name=name, blocks={}, acks=set(), terminal=None, peer=None)
        elif opcode == 3:
            block, content = int.from_bytes(body[2:4], 'big'), body[4:]
            require(block >= 1 and len(content) <= 512, 'TFTP block/length')
            if direction == 'TARGET' and sp == 41000:
                require(block == 1 and content == bytes.fromhex('0000000a413400010100'), 'LUI content')
                lui.append(content.hex())
            if direction == 'TARGET' and sp == 40002:
                require(block == 1, 'LUS block')
                lus.append(status_file(content))
            if direction == 'PEER' and dp in downloads:
                transfer = downloads[dp]
                require(transfer['peer'] in (None, sp), 'TFTP server TID changed')
                transfer['peer'] = sp
                require(transfer['terminal'] is None or block <= transfer['terminal'], 'TFTP DATA after terminal')
                if block in transfer['blocks']:
                    require(transfer['blocks'][block] == content, 'TFTP changed retransmission')
                else:
                    require(block == len(transfer['blocks'])+1, 'TFTP block sequence')
                    transfer['blocks'][block] = content
                if len(content) < 512:
                    transfer['terminal'] = block
        elif opcode == 4:
            require(len(body) == 4, 'TFTP ACK length')
            block = int.from_bytes(body[2:4], 'big')
            if direction == 'TARGET' and sp in downloads:
                transfer = downloads[sp]
                require(dp == transfer['peer'] and block in transfer['blocks'], 'TFTP ACK block/TID')
                transfer['acks'].add(block)
            if direction == 'PEER' and sp == 30002 and dp == 40002 and block == 1 and lus and lus[-1]['status'] == 3:
                final_lus_acked = True
        else:
            raise ValueError(f'unexpected TFTP opcode {opcode}')
    require(len(ntp_requests) == len(ntp_replies) == 1, 'missing/duplicate NTP exchange')
    require(('PEER', 1, 'TARGET.LUI') in requests and ('PEER', 2, 'TARGET.LUR') in requests, 'LUI/LUR requests missing')
    files = {}
    for transfer in downloads.values():
        require(transfer['terminal'] is not None, 'TFTP missing terminal DATA')
        require(transfer['acks'] == set(transfer['blocks']), 'TFTP missing ACK')
        require(transfer['name'] not in files, 'duplicate package transfer')
        files[transfer['name']] = b''.join(transfer['blocks'].values())
    require(set(files) == {'APP.LUH', 'A.LUP', 'B.LUP'}, 'missing package files')
    file_rows, package_crc = validate_package(files)
    require(len(lui) == 1 and final_lus_acked and any(s['status'] == 3 and s['ratio'] == 100 for s in lus), 'LUI/final LUS not completed')
    require(all(s['files'][0]['name'] == 'APP.LUH' and s['files'][0]['part'] == 'PN-1' for s in lus), 'LUS package identity')
    result = dict(status='PASS', ethernet_frames=len(flows), ntp_packets=2, ntp_origin_matched=True,
                  lui=len(lui), lus=lus, final_lus_acked=final_lus_acked, header_bytes=len(files['APP.LUH']),
                  files=file_rows, loaded_bytes=1724, application_bytes=700, package_crc32=package_crc,
                  packet_capture=str(path.with_suffix('.pcap')))
    # Publish success artifacts only after every check has succeeded.
    path.with_suffix('.pcap').write_bytes(records)
    for name, data in files.items():
        path.with_name('loaded_'+name).write_bytes(data)
    path.with_name('wire_audit.json').write_text(json.dumps(result, indent=2)+'\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('capture', type=Path)
    args = parser.parse_args()
    print('WIRE_AUDIT_PASS', json.dumps(audit(args.capture)))