#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Seeds the nightly integration services.

Sonarr: creates an empty root folder and adds one series (Sonarr resolves the
metadata for the TVDB id itself, so it needs outbound internet).
qBittorrent: adds one tiny, locally generated torrent (a single 16 KiB file;
the announce URL is a reserved documentation address, so nothing is contacted).

Usage: seed.py <env-file>
"""
import hashlib
import json
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import uuid
from http.cookiejar import CookieJar

SONARR = "http://127.0.0.1:8989"
QBIT = "http://127.0.0.1:8080"
# Any real TVDB id works; this one only supplies metadata to Sonarr.
TVDB_ID = 75978


def load_env(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        k, _, v = line.strip().partition("=")
        if k:
            out[k] = v
    return out


def sonarr(path, key, method="GET", body=None):
    req = urllib.request.Request(
        f"{SONARR}{path}",
        method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"X-Api-Key": key, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read() or b"null")


def seed_sonarr(key):
    subprocess.run(
        ["docker", "exec", "it-sonarr", "sh", "-c", "mkdir -p /tv-empty && chown 1000:1000 /tv-empty"],
        check=True,
    )
    sonarr("/api/v3/rootfolder", key, "POST", {"path": "/tv-empty"})
    profiles = sonarr("/api/v3/qualityprofile", key)
    lookup = sonarr(f"/api/v3/series/lookup?term=tvdb:{TVDB_ID}", key)
    series = lookup[0]
    series.update(
        {
            "qualityProfileId": profiles[0]["id"],
            "rootFolderPath": "/tv-empty",
            "monitored": False,
            "addOptions": {"searchForMissingEpisodes": False, "monitor": "none"},
        }
    )
    sonarr("/api/v3/series", key, "POST", series)


def bencode(v):
    if isinstance(v, int):
        return b"i%de" % v
    if isinstance(v, bytes):
        return b"%d:%s" % (len(v), v)
    if isinstance(v, str):
        return bencode(v.encode())
    if isinstance(v, list):
        return b"l" + b"".join(bencode(i) for i in v) + b"e"
    if isinstance(v, dict):
        return b"d" + b"".join(bencode(k) + bencode(v[k]) for k in sorted(v)) + b"e"
    raise TypeError(type(v))


def make_torrent():
    data = b"\0" * 16384
    info = {
        "name": "example-file.bin",
        "length": len(data),
        "piece length": 16384,
        "pieces": hashlib.sha1(data).digest(),
    }
    return bencode({"announce": "http://192.0.2.1/announce", "info": info})


def multipart(fields, files):
    boundary = uuid.uuid4().hex
    parts = []
    for k, v in fields.items():
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
        )
    for k, (fname, content) in files.items():
        parts.append(
            (
                f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"; '
                f'filename="{fname}"\r\nContent-Type: application/x-bittorrent\r\n\r\n'
            ).encode()
            + content
            + b"\r\n"
        )
    parts.append(f"--{boundary}--\r\n".encode())
    return boundary, b"".join(parts)


def seed_qbit(user, password):
    jar = CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    login = urllib.request.Request(
        f"{QBIT}/api/v2/auth/login",
        data=urllib.parse.urlencode({"username": user, "password": password}).encode(),
        headers={"Referer": QBIT},
    )
    assert opener.open(login, timeout=30).read().strip() == b"Ok."
    boundary, body = multipart(
        {"paused": "true", "stopped": "true", "savepath": "/downloads"},
        {"torrents": ("example.torrent", make_torrent())},
    )
    add = urllib.request.Request(
        f"{QBIT}/api/v2/torrents/add",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}", "Referer": QBIT},
    )
    opener.open(add, timeout=30).read()
    time.sleep(2)


if __name__ == "__main__":
    env = load_env(sys.argv[1])
    seed_sonarr(env["SONARR_API_KEY"])
    seed_qbit(env["QBIT_USERNAME"], env["QBIT_PASSWORD"])
    print("seeded")
