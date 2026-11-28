// SPDX-License-Identifier: GPL-3.0-or-later

// One shared corpus of FAKE secrets (RFC 5737 / 3849 addresses, `.example`
// names, made-up keys). Every sink that can leave the device is asserted
// against it. Nothing here is real.

/// One dirty line and the substrings that must not survive any sink.
class Canary {
  const Canary(this.name, this.text, this.forbidden);

  final String name;
  final String text;
  final List<String> forbidden;

  @override
  String toString() => name;
}

const _hex32 = '0a1b2c3d4e5f60718293a4b5c6d7e8f9';
const _base32 = 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP';
// JWT-shaped, but assembled at runtime from fragments so that no literal in
// the repository (or its history) matches a secret scanner's JWT pattern.
const _jwtPrefix = 'ey' 'J';
const _jwtPayloadBody = 'zdWIiOiJjYW5hcnktYWxpY2UifQ';
final _jwt = [
  '${_jwtPrefix}hbGciOiJIUzI1NiJ9',
  '${_jwtPrefix}$_jwtPayloadBody',
  'c2lnbmF0dXJlY2FuYXJ5',
].join('.');

final canaryCorpus = <Canary>[
  // Addresses.
  const Canary('ipv4', 'connect to 198.51.100.23 refused', ['198.51.100.23']),
  const Canary('ipv4 port', 'dial 198.51.100.23:7878 timed out', [
    '198.51.100.23',
  ]),
  const Canary('ipv6', 'route to 2001:db8:85a3::8a2e:370:7334 lost', [
    '2001:db8:85a3::8a2e:370:7334',
  ]),
  const Canary('ipv6 bracketed', 'GET [2001:db8::1d]:8989 failed', [
    '2001:db8::1d',
  ]),
  const Canary('label host port', 'cannot reach nas:8989 right now', [
    'nas:8989',
  ]),
  const Canary('host port', 'cannot reach media.canary.example:8989', [
    'media.canary.example',
  ]),
  const Canary('mixed case host', 'host NaS.HoMe.Canary.Example refused', [
    'canary.example',
    'Canary.Example',
  ]),
  const Canary('punycode host', 'host xn--canary-nas-4ya.example refused', [
    'xn--canary-nas-4ya',
  ]),
  // URLs.
  const Canary(
    'userinfo url',
    'GET https://bobcanary:s3cr3tpwcanary@media.canary.example:8443/api failed',
    ['bobcanary', 's3cr3tpwcanary', 'media.canary.example'],
  ),
  Canary(
    'tracker passkey',
    'announce https://tracker.canary.example/$_hex32/announce failed',
    [_hex32, 'tracker.canary.example'],
  ),
  Canary('bare passkey', 'tracker answered for passkey $_hex32', [_hex32]),
  const Canary(
    'magnet',
    'added magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567'
        '&dn=Canary+Movie&tr=https%3A%2F%2Ftracker.canary.example%2Fannounce',
    ['0123456789abcdef0123456789abcdef01234567', 'Canary+Movie'],
  ),
  const Canary('file url', 'opening file:///home/alicecanary/Movies/x.mkv', [
    'alicecanary',
  ]),
  // Credentials.
  Canary('jwt', 'session $_jwt expired', [
    _jwt,
    '${_jwtPrefix}$_jwtPayloadBody',
  ]),
  const Canary('bearer', 'Authorization: Bearer canarybearer0123456789', [
    'canarybearer0123456789',
  ]),
  const Canary('basic', 'Authorization: Basic Y2FuYXJ5OnNlY3JldA==', [
    'Y2FuYXJ5OnNlY3JldA',
  ]),
  const Canary('cookie', 'Cookie: SID=canarysid0123456789; other=1', [
    'canarysid0123456789',
  ]),
  const Canary(
    'set-cookie',
    'Set-Cookie: QBT_SID_8080=canaryqbtsession01; Path=/; HttpOnly',
    ['canaryqbtsession01'],
  ),
  const Canary(
    'session id',
    'X-Transmission-Session-Id: canarytransmissionsid01',
    ['canarytransmissionsid01'],
  ),
  Canary('hex key', 'apikey=$_hex32 rejected', [_hex32]),
  Canary('hex key unlabeled', 'server said $_hex32 is invalid', [_hex32]),
  Canary('base32 key', 'otp secret $_base32 rejected', [_base32]),
  // Content.
  const Canary('quoted title', 'failed to import "The Canary Show (2020)"', [
    'The Canary Show',
  ]),
  const Canary('arabic title', 'failed to import "المسلسل الكناري الأول"', [
    'المسلسل الكناري',
  ]),
  const Canary('mixed rtl title', 'title: Canary مسلسل Show 2020, other', [
    'مسلسل',
    'Canary',
  ]),
  const Canary(
    'windows path spaces',
    r'missing C:\Program Files\Canary App\movie file.mkv today',
    ['Canary App', 'movie file'],
  ),
  const Canary(
    'unix path spaces',
    'missing /mnt/media/My Canary Shows/Canary Show/S01E01 - Pilot.mkv now',
    ['My Canary Shows', 'S01E01 - Pilot'],
  ),
  Canary(
    'large blob',
    '${'A' * 9000} tail apikey=canaryblobkey00000000000000001',
    ['canaryblobkey00000000000000001'],
  ),
  Canary(
    'secret early in large blob',
    'password=canaryearlypassword ${'B' * 9000}',
    ['canaryearlypassword'],
  ),
];

/// Every forbidden substring of every case.
List<String> get canaryForbidden => [
  for (final c in canaryCorpus) ...c.forbidden,
];
