#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Asserts security properties of an APK's *merged* AndroidManifest.xml.

The source manifest is hardened, but plugins and AndroidX libraries merge
extra entries into the final manifest, so the merged result is what counts:

* the only permission requested is INTERNET (plus the app-private signature
  permission AndroidX adds for non-exported dynamic receivers);
* the only exported component is the launcher activity;
* no component with an intent filter relies on the implicit default for
  `android:exported`;
* backups are off and platform cleartext traffic is denied;
* release manifests are not debuggable.

Usage:
  check_merged_manifest.py [--release] <merged AndroidManifest.xml>...
  check_merged_manifest.py --self-test
"""
import sys
import xml.etree.ElementTree as ET

ANDROID = "{http://schemas.android.com/apk/res/android}"
COMPONENT_TAGS = ("activity", "activity-alias", "service", "receiver", "provider")
ALLOWED_PERMISSIONS = {"android.permission.INTERNET"}


def check(xml_text: str, release: bool = False) -> list[str]:
    root = ET.fromstring(xml_text)
    problems: list[str] = []
    package = root.get("package", "")

    allowed = set(ALLOWED_PERMISSIONS)
    # Added by androidx.core: a signature permission private to this app.
    allowed.add(f"{package}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION")

    for tag in ("uses-permission", "uses-permission-sdk-23"):
        for el in root.iter(tag):
            name = el.get(ANDROID + "name", "")
            if name not in allowed:
                problems.append(f"unexpected permission requested: {name}")

    app = root.find("application")
    if app is None:
        return problems + ["no <application> element"]

    if app.get(ANDROID + "allowBackup") != "false":
        problems.append('android:allowBackup is not "false"')
    if app.get(ANDROID + "usesCleartextTraffic") != "false":
        problems.append('android:usesCleartextTraffic is not "false"')
    if release and app.get(ANDROID + "debuggable") == "true":
        problems.append("release manifest is debuggable")

    exported_launchers = []
    for tag in COMPONENT_TAGS:
        for el in app.iter(tag):
            name = el.get(ANDROID + "name", "?")
            exported = el.get(ANDROID + "exported")
            has_filter = el.find("intent-filter") is not None
            if exported is None and has_filter:
                problems.append(
                    f"{tag} {name} has an intent filter but no explicit android:exported"
                )
            if exported == "true":
                is_launcher = tag == "activity" and any(
                    any(a.get(ANDROID + "name") == "android.intent.action.MAIN"
                        for a in f.iter("action"))
                    and any(c.get(ANDROID + "name") == "android.intent.category.LAUNCHER"
                            for c in f.iter("category"))
                    for f in el.iter("intent-filter")
                )
                if is_launcher:
                    exported_launchers.append(name)
                else:
                    problems.append(f"{tag} {name} is exported")
    if len(exported_launchers) != 1:
        problems.append(
            f"expected exactly one exported launcher activity, found {exported_launchers}"
        )
    return problems


_GOOD = """<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="x.y">
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="x.y.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"/>
  <application android:allowBackup="false" android:usesCleartextTraffic="false">
    <activity android:name="x.y.MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
    <provider android:name="p.P" android:exported="false"/>
  </application>
</manifest>"""


def self_test() -> None:
    assert check(_GOOD) == [], check(_GOOD)
    cases = {
        "extra permission": _GOOD.replace(
            "<application",
            '<uses-permission android:name="android.permission.CAMERA"/><application',
        ),
        "exported service": _GOOD.replace(
            "</application>", '<service android:name="s.S" android:exported="true"/></application>'
        ),
        "implicit export": _GOOD.replace(
            "</application>",
            '<receiver android:name="r.R"><intent-filter><action android:name="a"/></intent-filter></receiver></application>',
        ),
        "backup on": _GOOD.replace('allowBackup="false"', 'allowBackup="true"'),
        "cleartext": _GOOD.replace('usesCleartextTraffic="false"', 'usesCleartextTraffic="true"'),
        "second exported activity": _GOOD.replace(
            "</application>",
            '<activity android:name="o.O" android:exported="true"/></application>',
        ),
        "no launcher": _GOOD.replace("LAUNCHER", "DEFAULT"),
    }
    for label, xml in cases.items():
        assert check(xml), f"{label}: expected a problem"
    assert check(
        _GOOD.replace("<application", '<application android:debuggable="true"'), release=True
    ), "debuggable release"
    print("check_merged_manifest self-test passed")


def main(argv: list[str]) -> int:
    if argv == ["--self-test"]:
        self_test()
        return 0
    release = "--release" in argv
    paths = [a for a in argv if not a.startswith("--")]
    if not paths:
        print(__doc__)
        return 2
    status = 0
    for path in paths:
        with open(path, encoding="utf-8") as f:
            problems = check(f.read(), release=release)
        for p in problems:
            print(f"::error file={path}::{p}")
        if problems:
            status = 1
        else:
            print(f"ok: {path}")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
