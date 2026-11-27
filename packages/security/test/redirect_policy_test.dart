// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:security/security.dart';
import 'package:test/test.dart';

RedirectDecision decide(
  String from,
  String to, {
  int status = 302,
  String method = 'GET',
  bool allowCleartext = false,
  String profileHost = 'nas.example',
}) => decideRedirect(
  from: Uri.parse(from),
  to: Uri.parse(to),
  status: status,
  method: method,
  profileHost: profileHost,
  allowCleartext: allowCleartext,
);

void main() {
  test('same origin keeps headers', () {
    final d = decide('https://nas.example/a', 'https://nas.example/b');
    expect(d, isA<RedirectFollow>());
    expect((d as RedirectFollow).keepHeaders, isTrue);
  });

  test('other host or port is followed with stripped headers', () {
    for (final to in ['https://other.example/', 'https://nas.example:8443/']) {
      final d = decide('https://nas.example/a', to) as RedirectFollow;
      expect(d.keepHeaders, isFalse, reason: to);
    }
  });

  test('https to http is refused, even on the same host', () {
    final d = decide('https://nas.example/', 'http://nas.example/');
    expect((d as RedirectRefuse).error.category, ErrorCategory.redirectRefused);
  });

  test('http target needs the opt-in and the profile host', () {
    expect(
      (decide('http://nas.example/', 'http://nas.example/x') as RedirectRefuse)
          .error
          .category,
      ErrorCategory.cleartextRefused,
    );
    expect(
      decide('http://nas.example/', 'http://nas.example/x', allowCleartext: true),
      isA<RedirectFollow>(),
    );
    expect(
      (decide(
        'http://nas.example/',
        'http://other.example/',
        allowCleartext: true,
      ) as RedirectRefuse).error.category,
      ErrorCategory.redirectRefused,
    );
  });

  test('non-http schemes are refused', () {
    expect(
      decide('https://nas.example/', 'file:///etc/passwd'),
      isA<RedirectRefuse>(),
    );
  });

  test('methods', () {
    expect(
      (decide('https://nas.example/', 'https://nas.example/x',
              status: 303, method: 'POST') as RedirectFollow)
          .toGet,
      isTrue,
    );
    expect(
      decide('https://nas.example/', 'https://nas.example/x',
          status: 307, method: 'POST'),
      isA<RedirectRefuse>(),
    );
    expect(
      (decide('https://nas.example/', 'https://nas.example/x',
              status: 307, method: 'GET') as RedirectFollow)
          .toGet,
      isFalse,
    );
  });

  test('stripUnsafeHeaders keeps only the allowlist', () {
    final out = stripUnsafeHeaders({
      'Authorization': 'x',
      'X-Api-Key': 'x',
      'Cookie': 'x',
      'X-Gateway': 'x',
      'Accept': 'application/json',
      'User-Agent': 'ua',
    });
    expect(out.keys.map((k) => k.toLowerCase()).toSet(), {'accept', 'user-agent'});
  });
}
