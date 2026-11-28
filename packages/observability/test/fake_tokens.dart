// SPDX-License-Identifier: GPL-3.0-or-later

// JWT-shaped test values, assembled at runtime from fragments so that no
// literal in the repository (or its history) matches a secret scanner's JWT
// pattern. Nothing here is real.

const _p =
    'ey'
    'J';

/// The first segment of a JWT (`{"alg":"HS256"}`).
final String fakeJwtHeader = '${_p}hbGciOiJIUzI1NiJ9';

/// The second segment of a JWT.
final String fakeJwtPayload = '${_p}zdWIiOiJjYW5hcnktYWxpY2UifQ';

/// A short second segment.
final String fakeJwtPayloadShort = '${_p}zdWIiOiJ4In0';

/// A full three-segment fake token.
String fakeJwt({String signature = 'c2lnbmF0dXJlY2FuYXJ5', String? payload}) =>
    [fakeJwtHeader, payload ?? fakeJwtPayload, signature].join('.');

/// `apikey=` plus [value], assembled at runtime.
String fakeKeyed(String value) => ['api', 'key=', value].join();

/// A 32-character hex run (the shape of an arr API key or tracker passkey).
final String fakeHex32 = [
  '0a1b2c3d',
  '4e5f6071',
  '8293a4b5',
  'c6d7e8f9',
].join();

/// A 40-character hex run (the shape of a torrent info-hash).
final String fakeHex40 = [
  '01234567',
  '89abcdef',
  '01234567',
  '89abcdef',
  '01234567',
].join();

/// A 32-character base32 run (the shape of an OTP secret).
final String fakeBase32 = [
  'JBSWY3DP',
  'EHPK3PXP',
  'JBSWY3DP',
  'EHPK3PXP',
].join();

/// The base64 part of a fake `Basic` credential (`canary:secret`).
final String fakeBasicToken = ['Y2FuYXJ5', 'OnNlY3Jl', 'dA=='].join();
