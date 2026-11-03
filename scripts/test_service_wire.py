"""Mutation tests for the fail-closed independent service-wire audit."""
import binascii
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from verify_service_wire import audit, checksum

CAPTURE = Path(sys.argv.pop(1))


class WireGate(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)/'wire.txt'
        self.lines = CAPTURE.read_text().splitlines()

    def run_audit(self):
        self.path.write_text('\n'.join(self.lines)+'\n')
        return audit(self.path)

    def packet(self, index):
        return bytearray.fromhex(self.lines[index].split()[2])

    def find(self, sp, dp, block=None):
        for index in range(len(self.lines)):
            raw = self.packet(index)
            if struct.unpack('!HH', raw[42:46]) == (sp, dp):
                if block is None or int.from_bytes(raw[52:54], 'big') == block:
                    return index
        self.fail('missing mutation target')

    def replace(self, index, raw):
        # Keep L2/L3/L4 checks valid so mutations exercise the protocol checks.
        length = int.from_bytes(raw[46:48], 'big')
        if raw[48:50] != bytes(2):
            raw[48:50] = bytes(2)
            pseudo = raw[34:42]+b'\0\x11'+raw[46:48]
            value = (~checksum(bytes(pseudo+raw[42:42+length]))) & 65535
            raw[48:50] = (value or 65535).to_bytes(2, 'big')
        raw[-4:] = binascii.crc32(raw[8:-4]).to_bytes(4, 'little')
        direction, timestamp, _ = self.lines[index].split()
        self.lines[index] = f'{direction} {timestamp} {raw.hex()}'

    def rejected(self, message):
        with self.assertRaisesRegex(ValueError, message):
            self.run_audit()
        self.assertFalse(self.path.with_name('wire_audit.json').exists())

    def test_valid_capture(self):
        result = self.run_audit()
        self.assertEqual(result['loaded_bytes'], 1724)
        self.assertEqual(result['package_crc32'], 'ce05f473')

    def test_missing_ntp_reply(self):
        del self.lines[self.find(123, 40001)]
        self.rejected('missing/duplicate NTP')

    def test_wrong_ntp_origin(self):
        index = self.find(123, 40001)
        raw = self.packet(index); raw[74] ^= 1
        self.replace(index, raw); self.rejected('NTP origin')

    def test_wrong_ntp_port(self):
        index = self.find(123, 40001)
        raw = self.packet(index); raw[44:46] = (40003).to_bytes(2, 'big')
        self.replace(index, raw); self.rejected('NTP reply ports')

    def test_unsynchronized_ntp(self):
        index = self.find(123, 40001)
        raw = self.packet(index); raw[50] |= 0xc0
        self.replace(index, raw); self.rejected('NTP reply flags')

    def test_zero_stratum(self):
        index = self.find(123, 40001)
        raw = self.packet(index); raw[51] = 0
        self.replace(index, raw); self.rejected('NTP reply flags')

    def test_zero_server_timestamp(self):
        index = self.find(123, 40001)
        raw = self.packet(index); raw[82:90] = bytes(8)
        self.replace(index, raw); self.rejected('NTP server timestamps')

    def test_corrupt_data(self):
        index = self.find(30000, 42003, 1)
        raw = self.packet(index); raw[54] ^= 1
        self.replace(index, raw); self.rejected('B.LUP CRC16')

    def test_bad_load_crc(self):
        index = self.find(30000, 42001, 1)
        raw = self.packet(index); raw[54+125] ^= 1
        self.replace(index, raw); self.rejected('whole-package CRC32')

    def test_missing_zero_terminal_block(self):
        del self.lines[self.find(30000, 42003, 3)]
        del self.lines[self.find(42003, 30000, 3)]
        self.rejected('TFTP missing terminal DATA')

    def test_missing_data_ack(self):
        del self.lines[self.find(42003, 30000, 2)]
        self.rejected('TFTP missing ACK')

    def test_missing_final_lus_ack(self):
        del self.lines[-1]
        self.rejected('LUI/final LUS not completed')

    def test_bad_fcs(self):
        index = self.find(123, 40001)
        raw = self.packet(index); raw[-1] ^= 1
        direction, timestamp, _ = self.lines[index].split()
        self.lines[index] = f'{direction} {timestamp} {raw.hex()}'
        self.rejected('FCS')


if __name__ == '__main__':
    unittest.main()