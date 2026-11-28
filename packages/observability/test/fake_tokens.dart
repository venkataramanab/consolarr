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
