import struct
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from download615a import DownloadReceiver,selection_file,parse_directory,parse_status,envelope


class DownloadPeerTests(unittest.TestCase):
    def test_operator_and_media_selection(self):
        self.assertEqual(selection_file(['A.LUP']).hex(),'0000000f4134000106412e4c555000')
        self.assertEqual(selection_file(['A.LUP'],True).hex(),'000000104134000106412e4c55500000')

    def test_duplicate_change_and_out_of_order(self):
        r=DownloadReceiver();r.receive(b'\0\2A.LUP\0octet\0')
        first=b'\0\3\0\1'+bytes(range(256))*2
        r.receive(first);self.assertIsNone(r.receive(first)[1])
        with self.assertRaises(ValueError):r.receive(first[:-1]+b'x')
        with self.assertRaises(ValueError):r.receive(b'\0\3\0\3')
        ack,event=r.receive(b'\0\3\0\2')
        self.assertEqual(len(event['data']),512);self.assertEqual(ack,b'\0\4\0\2')

    def test_bound_and_unsafe_name(self):
        r=DownloadReceiver(max_file_bytes=2)
        with self.assertRaises(ValueError):r.receive(b'\0\2../x\0octet\0')
        r.receive(b'\0\2X\0octet\0')
        with self.assertRaises(ValueError):r.receive(b'\0\3\0\1abc')

    def test_bad_status_never_acknowledged(self):
        r=DownloadReceiver();r.receive(b'\0\2TARGET.LNS\0octet\0')
        with self.assertRaises(ValueError):r.receive(b'\0\3\0\1'+b'broken')
        self.assertFalse(r.finished);self.assertNotIn('TARGET.LNS',r.files)

    def test_selection_duplicate_rejected(self):
        with self.assertRaises(ValueError):selection_file(['A.LUP','A.LUP'])

    def test_directory_trailing_or_truncated(self):
        raw=envelope(b'\0\1\6A.LUP\0\0')
        self.assertEqual(parse_directory(raw)[0]['name'],'A.LUP')
        with self.assertRaises(ValueError):parse_directory(raw+b'\0')
        with self.assertRaises(ValueError):parse_directory(raw[:-1])


if __name__=='__main__':unittest.main()
