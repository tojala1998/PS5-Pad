"""Validate an unsigned ARM64 PS5 Pad archive without contacting a device."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import zipfile

def verify(path, expected_elf):
    with zipfile.ZipFile(path) as archive:
        names=archive.namelist()
        assert len(names)==len(set(names)), 'Duplicate ZIP entries'
        assert archive.testzip() is None, 'ZIP integrity failure'
        prefix='Payload/PS5Pad.app/'
        assert all(n.startswith(prefix) and '..' not in n.split('/') for n in names), 'Unexpected archive path'
        assert not any('_CodeSignature' in n or n.endswith('embedded.mobileprovision') for n in names), 'Signing material found'
        info=plistlib.loads(archive.read(prefix+'Info.plist'))
        assert info['CFBundleIdentifier']=='com.uhnmeyker.ps5pad', 'App identifier changed'
        assert info['CFBundleDisplayName']=='PS5 Pad', 'Display name mismatch'
        assert info['UIApplicationSceneManifest'], 'Missing scene lifecycle'
        assert info['NSLocalNetworkUsageDescription'], 'Missing network permission description'
        binary=archive.read(prefix+info['CFBundleExecutable'])
        magic,cpu,subtype,kind,count,size,flags,reserved=struct.unpack_from('<IiiIIIII',binary)
        assert magic==0xfeedfacf and cpu==0x100000c and kind==2, 'Not an ARM64 executable'
        at=32; end=32+size
        assert end<=len(binary), 'Invalid load commands'
        for _ in range(count):
            cmd,length=struct.unpack_from('<II',binary,at)
            assert length>=8 and at+length<=end, 'Invalid Mach-O command'
            assert cmd!=0x1d, 'Executable has a code signature'
            at+=length
        assert at==end, 'Load command size mismatch'
        assert archive.getinfo(prefix+info['CFBundleExecutable']).external_attr>>16 & 0o111, 'Executable permissions missing'
        assert info['CFBundleExecutable']=='PS5Pad'
        assert not any('/Library/' in n or '/Documents/' in n for n in names), 'Preseeded app data found'
        logo=archive.read(prefix+'KodiLogo.png')
        assert logo[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack_from('>II',logo,16)==(256,256), 'Kodi logo missing'
        elf=archive.read(prefix+'padd-controller.elf')
        assert elf==expected_elf.read_bytes(), 'Bundled service differs from tested ELF'
        for name,pixels in [('AppIcon60x60@2x.png',120),('AppIcon60x60@3x.png',180)]:
            png=archive.read(prefix+name)
            assert png[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack_from('>II',png,16)==(pixels,pixels), 'Invalid app icon'
    return {'app':'PS5 Pad','version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],
            'bundle_id':info['CFBundleIdentifier'],'unsigned':True,'architecture':'ARM64',
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,
            'service_sha256':hashlib.sha256(elf).hexdigest(),
            'validation':'Local archive and protocol checks only; no device installation or live input test.'}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('ipa',type=Path); p.add_argument('--elf',required=True,type=Path)
    p.add_argument('--report',type=Path)
    a=p.parse_args(); report=verify(a.ipa,a.elf)
    text=json.dumps(report,indent=2)+'\n'
    if a.report: a.report.write_text(text,encoding='utf-8')
    print(text,end='')
