#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Asserts security properties of an APK's *merged* AndroidManifest.xml.

The source manifest is hardened, but plugins and AndroidX libraries merge
extra entries into the final manifest, so the merged result is what counts:

* the only permissions requested are INTERNET and the two biometric ones the
  opt-in app lock needs (USE_BIOMETRIC, and USE_FINGERPRINT which
  androidx.biometric merges for the API 26-27 fallback), plus the exact
  app-private signature permission
  `<package>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` that AndroidX adds for
  non-exported dynamic receivers;
* the only exported component is the launcher activity;
* no component with an intent filter relies on the implicit default for
  `android:exported`;
* backups are off, the extraction/backup rules and the network security
  config are present and point at the expected resources, and platform
  cleartext traffic is denied;
* no advertising or analytics identifiers: no `AD_ID` permission and no
  ads/analytics `<meta-data>` (for example an ads `APPLICATION_ID`);
* deep links stay off (`flutter_deeplinking_enabled` is "false");
* release manifests are not debuggable.

Usage:
  check_merged_manifest.py [--release] <merged AndroidManifest.xml>...
  check_merged_manifest.py --self-test
"""
import re
import sys
import xml.etree.ElementTree as ET

ANDROID = "{http://schemas.android.com/apk/res/android}"
COMPONENT_TAGS = ("activity", "activity-alias", "service", "receiver", "provider")
ALLOWED_PERMISSIONS = {
    "android.permission.INTERNET",
    # Opt-in app lock (SET-02): BiometricPrompt; USE_FINGERPRINT is merged by
    # androidx.biometric for the API 26-27 FingerprintManager fallback.
    "android.permission.USE_BIOMETRIC",
    "android.permission.USE_FINGERPRINT",
}

# Attribute -> the resource the source manifest points it at.
REQUIRED_RESOURCES = {
    "dataExtractionRules": "@xml/data_extraction_rules",
    "fullBackupContent": "@xml/backup_rules",
    "networkSecurityConfig": "@xml/network_security_config",
}
AD_ID_PERMISSION = "com.google.android.gms.permission.AD_ID"
# Words (split on non-alphanumerics) that mark an ads or analytics SDK entry.
BANNED_META_WORDS = {
    "ads", "ad", "admob", "analytics", "adid", "firebase", "appmetrica",
    "crashlytics", "sentry", "bugsnag", "flurry", "mixpanel", "amplitude",
}


def meta_data_problems(root: ET.Element) -> list[str]:
    problems = []
    deeplinks = []
    for el in root.iter("meta-data"):
        name = el.get(ANDROID + "name", "")
        words = set(re.split(r"[^a-z0-9]+", name.lower()))
        if words & BANNED_META_WORDS or "APPLICATION_ID" in name.upper():
            problems.append(f"advertising/analytics <meta-data>: {name}")
        if name == "flutter_deeplinking_enabled":
            deeplinks.append(el.get(ANDROID + "value"))
    if deeplinks != ["false"]:
        problems.append('flutter_deeplinking_enabled must be set to "false"')
    return problems


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
            if name == AD_ID_PERMISSION:
                problems.append(f"advertising id permission requested: {name}")
            elif name not in allowed:
                problems.append(f"unexpected permission requested: {name}")

    app = root.find("application")
    if app is None:
        return problems + ["no <application> element"]

    if app.get(ANDROID + "allowBackup") != "false":
        problems.append('android:allowBackup is not "false"')
    if app.get(ANDROID + "usesCleartextTraffic") != "false":
        problems.append('android:usesCleartextTraffic is not "false"')
    for attr, resource in REQUIRED_RESOURCES.items():
        value = app.get(ANDROID + attr)
        if value is None:
            problems.append(f"android:{attr} is missing")
        elif value != resource:
            problems.append(f'android:{attr} is "{value}", expected "{resource}"')
    problems += meta_data_problems(root)
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
  <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
  <uses-permission android:name="android.permission.USE_FINGERPRINT"/>
  <uses-permission android:name="x.y.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"/>
  <application android:allowBackup="false" android:usesCleartextTraffic="false"
      android:dataExtractionRules="@xml/data_extraction_rules"
      android:fullBackupContent="@xml/backup_rules"
      android:networkSecurityConfig="@xml/network_security_config">
    <meta-data android:name="flutterEmbedding" android:value="2"/>
    <meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>
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
        "another app's dynamic-receiver permission": _GOOD.replace(
            "<application",
            '<uses-permission android:name="other.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"/><application',
        ),
        "unrelated credentials permission": _GOOD.replace(
            "<application",
            '<uses-permission android:name="android.permission.USE_CREDENTIALS"/><application',
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
        "no data extraction rules": _GOOD.replace(
            ' android:dataExtractionRules="@xml/data_extraction_rules"', ""
        ),
        "no full backup content": _GOOD.replace(
            ' android:fullBackupContent="@xml/backup_rules"', ""
        ),
        "no network security config": _GOOD.replace(
            ' android:networkSecurityConfig="@xml/network_security_config"', ""
        ),
        "extraction rules point elsewhere": _GOOD.replace(
            "@xml/data_extraction_rules", "@xml/other"
        ),
        "backup content points elsewhere": _GOOD.replace(
            "@xml/backup_rules", "@xml/other"
        ),
        "network config points elsewhere": _GOOD.replace(
            "@xml/network_security_config", "@xml/other"
        ),
        "ad id permission": _GOOD.replace(
            "<application",
            '<uses-permission android:name="com.google.android.gms.permission.AD_ID"/><application',
        ),
        "ads application id": _GOOD.replace(
            "</application>",
            '<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="x"/></application>',
        ),
        "analytics meta-data": _GOOD.replace(
            "</application>",
            '<meta-data android:name="google_analytics_adid_collection_enabled" android:value="true"/></application>',
        ),
        "deep links not disabled": _GOOD.replace(
            '<meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>', ""
        ),
        "deep links enabled": _GOOD.replace(
            'flutter_deeplinking_enabled" android:value="false"', 'flutter_deeplinking_enabled" android:value="true"'
        ),
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
