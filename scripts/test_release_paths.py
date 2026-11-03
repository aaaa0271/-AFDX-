import tempfile,unittest
import hashlib,json,sys
from pathlib import Path
from run_all import external_output_root,ROOT
sys.path.insert(0,str(ROOT/'mimic_plugin/scripts'))
from release_paths import upstream_manifest,verify_upstream,verify_local
class ReleasePaths(unittest.TestCase):
 def test_source_directories_rejected(self):
  for p in (ROOT,ROOT/'rtl',ROOT/'tb',ROOT/'docs'/'bad',ROOT/'results'/'..'/'rtl'):
   with self.assertRaises(ValueError):external_output_root(p)
 def test_delivery_results_accepted(self):
  for p in (ROOT/'results',ROOT/'results'/'run'):
   self.assertEqual(external_output_root(p),p.resolve())
 def test_external_path_accepted(self):
  with tempfile.TemporaryDirectory() as d:self.assertEqual(external_output_root(d),Path(d).resolve())
 def test_mimic_merged_manifest(self):
  self.assertEqual(upstream_manifest(ROOT/'mimic_plugin'),ROOT/'docs/mimic_plugin/UPSTREAM_HASHES.json')
  result=verify_upstream(ROOT/'mimic_plugin')
  self.assertEqual(result['status'],'NOT_AVAILABLE');self.assertEqual(result['files_checked'],0)
 def test_mimic_missing_upstream_is_not_pass(self):
  with tempfile.TemporaryDirectory() as d:
   with self.assertRaises(RuntimeError):verify_upstream(ROOT/'mimic_plugin',Path(d))
 def test_mimic_local_integrity_rejects_tampering(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);file=root/'source.py';file.write_bytes(b'original')
   (root/'RELEASE_MANIFEST.json').write_text(json.dumps({'files':{'source.py':hashlib.sha256(b'original').hexdigest()}}))
   self.assertEqual(verify_local(root)['status'],'PASS');file.write_bytes(b'changed')
   with self.assertRaises(RuntimeError):verify_local(root)
 def test_mimic_standalone_manifest(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);(root/'docs').mkdir();path=root/'docs/UPSTREAM_HASHES.json';path.write_text('{}')
   self.assertEqual(upstream_manifest(root),path)
if __name__=='__main__':unittest.main()
