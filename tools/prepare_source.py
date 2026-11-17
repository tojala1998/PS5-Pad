"""Stage a verified release and refresh the SideStore source. No network or signing."""
import argparse
from datetime import date
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import zipfile

ROOT = Path(__file__).resolve().parent.parent
RAW = "https://raw.githubusercontent.com/tojala1998/PS5-Pad/main/"
BUNDLE = "com.uhnmeyker.ps5pad"
SOURCE_ID = BUNDLE + ".source"

def read_release(ipa, report_path):
    data = ipa.read_bytes()
    report = json.loads(report_path.read_text(encoding="utf-8"))
    digest = hashlib.sha256(data).hexdigest()
    if report.get("sha256") != digest or report.get("bytes") != len(data) or report.get("unsigned") is not True:
        raise ValueError("IPA does not match its unsigned build verification report")
    with zipfile.ZipFile(ipa) as archive:
        info = plistlib.loads(archive.read("Payload/PS5Pad.app/Info.plist"))
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", version):
        raise ValueError("Expected a numeric dotted release version")
    if info["CFBundleIdentifier"] != BUNDLE or report.get("bundle_id") != BUNDLE:
        raise ValueError("App identity changed")
    if report.get("version") != version or report.get("build") != info["CFBundleVersion"]:
        raise ValueError("IPA version/build does not match verification report")
    return info, report

def stage(root, ipa, report_path, release_date=None, check=False):
    info, report = read_release(ipa, report_path)
    version = report["version"]
    source_path = root / "source.json"
    source = json.loads(source_path.read_text(encoding="utf-8")) if source_path.exists() else None
    if source and (source.get("identifier") != SOURCE_ID or len(source.get("apps", [])) != 1 or source["apps"][0].get("bundleIdentifier") != BUNDLE):
        raise ValueError("Source identity changed; refusing to overwrite")
    versions = source["apps"][0]["versions"] if source else []
    previous = next((v for v in versions if v["version"] == version), None)
    release = root / "releases" / version
    name = "PS5-Pad-" + version + "-unsigned.ipa"
    destination = release / name
    if destination.exists() and destination.read_bytes() != ipa.read_bytes():
        raise ValueError("Published version already has different bytes. Bump the app version before releasing.")
    if versions and tuple(map(int,version.split("."))) < max(tuple(map(int,v["version"].split("."))) for v in versions):
        raise ValueError("Refusing to promote an older version")
    notes = (root / "docs" / ("PS5-Pad-" + version + "-notes.txt")).read_text(encoding="utf-8")
    entry = {
        "version": version,
        "date": previous["date"] if previous else (release_date or date.today().isoformat()),
        "localizedDescription": notes.strip(),
        "downloadURL": RAW + "releases/" + version + "/" + name,
        "size": report["bytes"],
        "minOSVersion": info["MinimumOSVersion"],
    }
    date.fromisoformat(entry["date"])
    versions = [entry] + [v for v in versions if v["version"] != version]
    app = {
        "name": "PS5 Pad", "bundleIdentifier": BUNDLE, "developerName": "uhnmeyker",
        "subtitle": "A direct Wi-Fi media remote for PS5",
        "localizedDescription": "Control a jailbroken PS5 directly over Wi-Fi. Swipe navigation, controller buttons, Kodi playback controls and a manual live keyboard. Requires the PS5 Pad helper on the console. No Remote Play, audio/video streaming or Windows relay. Experimental software; see version notes for verified behavior and limitations.",
        "iconURL": RAW + "docs/PS5-Pad-icon.png", "tintColor": "53D889",
        "permissions": [{"type": "network", "usageDescription": info["NSLocalNetworkUsageDescription"]}],
        "versions": versions,
        # Compatibility fields for older source readers.
        "version": version, "versionDate": entry["date"], "versionDescription": entry["localizedDescription"],
        "downloadURL": entry["downloadURL"], "size": entry["size"],
    }
    expected = {"name": "uhnmeyker - PS5 Pad", "identifier": SOURCE_ID,
                "sourceURL": RAW + "source.json", "apps": [app], "news": []}
    if check:
        if source != expected or not destination.exists():
            raise ValueError("Source or staged IPA is stale; run prepare_source.py first")
    else:
        release.mkdir(parents=True, exist_ok=True)
        if not destination.exists(): shutil.copy2(ipa, destination)
        report_destination = release / ("PS5-Pad-" + version + "-verification.json")
        if report_path.resolve() != report_destination.resolve(): shutil.copy2(report_path, report_destination)
        temporary = source_path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(expected, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        temporary.replace(source_path)
    return {"source": expected["sourceURL"], "version": version, "bytes": report["bytes"],
            "sha256": report["sha256"], "check_only": check, "published": False}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--date", help="Release date YYYY-MM-DD; existing dates are preserved")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    print(json.dumps(stage(ROOT,args.ipa,args.report,args.date,args.check),indent=2))
