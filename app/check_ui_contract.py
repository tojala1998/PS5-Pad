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

# Scene activity must not be rejected by UIApplication's lagging aggregate state.
assert 'UIApplication.sharedApplication.applicationState' not in source, 'Controller flow still gates on aggregate application state'
assert re.search(r'sceneDidBecomeActive:[^\n]*\[_controller activateScene\]',source), 'Scene activation must enter the production lifecycle adapter'
assert 'qp_lifecycle_view_ready(&_lifecycle); [self scheduleActivation];' in source, 'View hydration must retry a pending activation'
assert 'qp_lifecycle_take_start(&self->_lifecycle,generation)' in source, 'Deferred activation must reject stale generations'
assert '!_ensureSessionGeneration' not in source, 'Connection generation must not consume lifecycle startup'
print('PASS: UIKit lifecycle entry points use the scene adapter and deferred activation guard.')

resume=source.split('- (void)resumeAfterInterruption {',1)[1].split('- (void)suspend',1)[0]
assert '_autoInitializeAttempted=NO' not in resume, 'Deferred activation must not reset a pending explicit initialization'
