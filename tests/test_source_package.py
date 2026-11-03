import importlib.util
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'report_tools'))
from package_common import validate_output, inventory
from build_source_package import build
class PackageSafetyTests(unittest.TestCase):
    def test_source_and_ancestors_and_children_are_rejected_without_writes(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/'source';root.mkdir()
            sentinel=root/'sentinel';sentinel.write_text('KEEP')
            for output in (root,root/'child.zip',root.parent):
                with self.assertRaises(ValueError):validate_output(root,output)
            self.assertEqual(sentinel.read_text(),'KEEP')
    def test_existing_output_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/'source';root.mkdir()
            output=Path(temp)/'existing.zip';output.write_bytes(b'KEEP')
            with self.assertRaises(FileExistsError):validate_output(root,output)
            self.assertEqual(output.read_bytes(),b'KEEP')
    def test_package_uses_current_layout_preserves_pyc_and_source(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/'source'
            for name in ('rtl/AFDX_defense_top.v','report_tools/helper.py','poster/poster.html',
                         'README_PACKAGE.md','evidence/log.txt','__pycache__/cache.pyc'):
                f=root/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text('KEEP')
            original={p.relative_to(root).as_posix():p.read_bytes() for p in root.rglob('*') if p.is_file()}
            output=Path(temp)/'new.zip'
            rows=build(root,output)
            with zipfile.ZipFile(output) as z:
                self.assertIn('report_tools/helper.py',z.namelist())
                self.assertIn('poster/poster.html',z.namelist())
                self.assertIn('__pycache__/cache.pyc',z.namelist())
                self.assertEqual(len(rows),len(z.read('MANIFEST.sha256').decode().splitlines()))
            self.assertEqual(original,{p.relative_to(root).as_posix():p.read_bytes() for p in root.rglob('*') if p.is_file()})
            with self.assertRaises(FileExistsError):build(root,output)
    def test_submission_archive_keeps_top_folder(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/'source';(root/'rtl').mkdir(parents=True)
            (root/'rtl/AFDX_defense_top.v').write_text('module AFDX_defense_top; endmodule')
            out=Path(temp)/'submission.zip'
            build(root,out,'AFDX_SOURCE_20261026')
            with zipfile.ZipFile(out) as z:
                self.assertEqual(set(z.namelist()),{'AFDX_SOURCE_20261026/rtl/AFDX_defense_top.v','AFDX_SOURCE_20261026/MANIFEST.sha256'})
    def test_selected_waveforms_kept_build_files_excluded(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            for name in ('evidence/selected/signals.wlf','results/run/signals.wlf','work/_info','mimic_plugin/build/worker.exe'):
                p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'evidence fixture')
            self.assertEqual(set(inventory(root)),{'evidence/selected/signals.wlf'})
if __name__=='__main__':unittest.main()
