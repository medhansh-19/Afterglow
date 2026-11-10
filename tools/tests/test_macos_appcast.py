import base64
import importlib.util
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

spec = importlib.util.spec_from_file_location('appcast', Path(__file__).parents[1] / 'macos-appcast.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
INFO = {'CFBundleIdentifier':'local.medhansh.afterglow','CFBundleVersion':'35','CFBundleShortVersionString':'3.0.8','LSMinimumSystemVersion':'14.0'}
SIGNATURE = base64.b64encode(bytes(64)).decode()

class AppcastTests(unittest.TestCase):
    def test_signed_update_metadata_and_immutable_url(self):
        xml = module.appcast(INFO, 'Afterglow.zip', 100, SIGNATURE, 'macos-v3.0.8')
        item = ET.fromstring(xml).find('channel/item/enclosure')
        self.assertEqual(item.attrib[f'{{{module.SPARKLE}}}version'], '35')
        self.assertEqual(item.attrib[f'{{{module.SPARKLE}}}edSignature'], SIGNATURE)
        self.assertEqual(item.attrib['url'], 'https://github.com/medhansh-19/Afterglow/releases/download/macos-v3.0.8/Afterglow.zip')

    def test_reject_malformed_release_identity_or_signature(self):
        for info, name, length, signature, tag in [
            ({**INFO,'CFBundleIdentifier':'other.app'},'Afterglow.zip',100,SIGNATURE,'macos-v3.0.8'),
            (INFO,'../Afterglow.zip',100,SIGNATURE,'macos-v3.0.8'),
            (INFO,'Afterglow.zip',100,SIGNATURE,'../../latest'),
            (INFO,'Afterglow.zip',100,'','macos-v3.0.8'),
            (INFO,'Afterglow.zip',0,SIGNATURE,'macos-v3.0.8'),
        ]:
            with self.assertRaises(ValueError):
                module.appcast(info,name,length,signature,tag)

if __name__ == '__main__': unittest.main()
