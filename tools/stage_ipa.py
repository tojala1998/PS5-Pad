"""Verify and copy an unsigned PS5 Pad IPA into LiveContainer Documents over USB.

No signing, installation, application launch, settings or icon changes.
An existing file with different bytes is preserved under its original name.
"""
import argparse
import asyncio
import hashlib
import json
from pathlib import Path
import sys
import zipfile
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService
from pymobiledevice3.services.installation_proxy import InstallationProxyService

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'app'))
from verify_ipa import verify

async def transfer(ipa, bundle_id):
    with zipfile.ZipFile(ipa) as archive:
        bundled=archive.read('Payload/PS5Pad.app/padd-controller.elf')
    known=next((p for p in sorted((ROOT/'service/prebuilt').glob('padd-controller-*.elf'))
                if p.read_bytes()==bundled),None)
    if known is None:
        raise RuntimeError('Bundled service does not match a verified prebuilt ELF.')
    report=verify(ipa,known)
    data=ipa.read_bytes(); digest=report['sha256']
    async with await create_using_usbmux(connection_type='USB',autopair=False) as phone:
        if not bundle_id:
            apps=await InstallationProxyService(phone).get_apps()
            candidates=[bid for bid in apps if bid.startswith('com.kdt.livecontainer')]
            if len(candidates)!=1:
                raise RuntimeError('Expected one LiveContainer installation; specify --bundle-id if needed.')
            bundle_id=candidates[0]
        async with await HouseArrestService.create(phone,bundle_id,documents_only=True) as files:
            remote='/Documents/'+ipa.name
            if await files.exists(remote) and await files.get_file_contents(remote)!=data:
                remote='/Documents/'+ipa.stem+'-'+digest[:8]+ipa.suffix
            if not await files.exists(remote):
                await files.set_file_contents(remote,data)
            copied=await files.get_file_contents(remote)
            if hashlib.sha256(copied).hexdigest()!=digest:
                raise RuntimeError('The copy did not match the verified build.')
    return {'file':ipa.name,'destination_app':'LiveContainer','device_path':remote,
            'bytes':len(data),'sha256':digest,'transfer_verified':True,'installed_by_this_transfer':False}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa',type=Path)
    parser.add_argument('--bundle-id',help='Override automatic LiveContainer selection.')
    args=parser.parse_args()
    try:
        receipt=asyncio.run(asyncio.wait_for(transfer(args.ipa.resolve(),args.bundle_id),40))
    except Exception as exc:
        print('Transfer failed: '+str(exc),file=sys.stderr)
        return 1
    print(json.dumps(receipt,indent=2)); return 0

if __name__=='__main__':
    raise SystemExit(main())
