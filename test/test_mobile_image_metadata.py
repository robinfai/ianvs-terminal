import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('metadata', Path(__file__).resolve().parents[1] / 'tools/check_mobile_image_metadata.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ImageMetadataTests(unittest.TestCase):
    def test_png(self):
        image = b'\x89PNG\r\n\x1a\n' + struct.pack('>I',13) + b'IHDR' + struct.pack('>II',390,844) + b'\0'*9
        self.assertEqual(module.image_info(image), ('PNG',390,844))

    def test_jpeg_with_png_extension_and_frozen_original(self):
        image = b'\xff\xd8\xff\xe0\x00\x04ab\xff\xc0' + struct.pack('>HBHH',8,8,1694,768) + b'\0'
        self.assertEqual(module.image_info(image),('JPEG',768,1694))
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'capture.png').write_bytes(image)
            original={'status':'failed','artifacts':[{'path':'capture.png','sha256':hashlib.sha256(image).hexdigest(),'pixel_size':[4718592,4292935744]}]}
            frozen=json.dumps(original)
            fixed=module.corrected_record(original,root)
            self.assertEqual(fixed['artifacts'][0]['pixel_size'],[768,1694])
            self.assertFalse(fixed['artifacts'][0]['extension_matches_format'])
            self.assertEqual(fixed['status'],'failed')
            self.assertEqual(json.dumps(original),frozen)
            self.assertEqual((root/'capture.png').read_bytes(),image)

    def test_truncation_and_nonsense_rejected(self):
        for image in [b'',b'\xff\xd8\xff\xc0\x00\x09',b'\x89PNG\r\n\x1a\n']:
            with self.assertRaises(ValueError):module.image_info(image)

    def test_path_escape_and_hash_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'test.png').write_bytes(b'bad')
            for name in ['test.png','../test.png']:
                with self.assertRaises(ValueError):
                    module.corrected_record({'artifacts':[{'path':name,'sha256':'wrong'}]},root)

if __name__=='__main__': unittest.main()
