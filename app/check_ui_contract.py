"""Catch misspelled Objective-C UIKit overrides, which clang accepts as new methods."""
from pathlib import Path
import re
import sys

source=Path('main.m').read_text()
control=source.split('@implementation QPButton',1)[1].split('@end',1)[0]
header=(Path(sys.argv[1])/'System/Library/Frameworks/UIKit.framework/Headers/UIControl.h').read_text()
for selector in ('beginTrackingWithTouch','continueTrackingWithTouch','endTrackingWithTouch','cancelTrackingWithEvent'):
    assert re.search(r'-\s*\([^)]*\)\s*'+selector+r':',control), 'Missing UIKit override: '+selector
    assert selector+':' in header, 'Unknown UIKit override: '+selector
assert not re.search(r'\b(?:begin|continue|end)Tracking:',control), 'Misspelled tracking selector'
assert '?:@"192.168.' not in source and '?:@"10.' not in source, 'Preset console address'
assert 'kodiLabel' not in source, 'Obsolete footer'
print('PASS: UIKit touch override selectors match the SDK; fresh console setup has no preset host.')
