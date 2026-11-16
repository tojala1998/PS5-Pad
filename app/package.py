"""Create the app's original geometric icon and an unsigned IPA, using the standard library."""
from pathlib import Path
import math
import struct
import sys
import zlib
import zipfile
import shutil


def icon(size):
    # Rounded swipe surface and four directional marks, drawn at 3x for antialiasing.
    scale = 3
    n = size * scale
    pixels = []
    for y in range(n):
        row=[]
        for x in range(n):
            u,v=(x+.5)/n,(y+.5)/n
            c=(14,23,29)
            dx=max(abs(u-.5)-.235,0); dy=max(abs(v-.5)-.235,0)
            if math.hypot(dx,dy)<.09: c=(30,49,56)
            # Four slim chevrons and the selection point.
            for a in range(4):
                ax,ay=u-.5,v-.5
                for _ in range(a): ax,ay=-ay,ax
                if abs(ax)<.052 and abs(ay-(-.245+abs(ax)))<.012: c=(158,232,212)
            if math.hypot(u-.5,v-.5)<.027: c=(158,232,212)
            row.append(c)
        pixels.append(row)
    raw=bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            for channel in range(3):
                raw.append(sum(pixels[y*scale+j][x*scale+i][channel] for i in range(scale) for j in range(scale))//(scale*scale))
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')


app=Path(sys.argv[1]); output=Path(sys.argv[2])
for name,size in [('AppIcon60x60@2x.png',120),('AppIcon60x60@3x.png',180)]:
    asset=Path(__file__).parent/'assets'/name
    if not asset.is_file():
        raise SystemExit('Missing app icon. Run make-icon.ps1 first.')
    shutil.copyfile(asset,app/name)
shutil.copyfile(Path(__file__).parent/'assets/KodiLogo.png',app/'KodiLogo.png')
with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.iterdir()):
        info=zipfile.ZipInfo('Payload/PS5Pad.app/'+path.name)
        info.create_system=3
        info.external_attr=(0o100755 if path.name=='PS5Pad' else 0o100644)<<16
        info.compress_type=zipfile.ZIP_DEFLATED
        archive.writestr(info,path.read_bytes())
print(f'Packaged {output}: {output.stat().st_size:,} bytes')
