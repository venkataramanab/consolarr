// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A certificate (and key) generated at test time with the `openssl` CLI.
///
/// Files live in `test/.generated/` (git-ignored); nothing is committed.
class TestCert {
  TestCert({required this.certPath, required this.keyPath});

  final String certPath;
  final String keyPath;

  /// DER bytes of the (leaf) certificate.
  late final Uint8List der = _pemToDer(File(certPath).readAsStringSync());

  /// Lower-case SHA-256 hex of [der].
  late final String sha256Hex = sha256.convert(der).toString();

  List<int> get pemBytes => File(certPath).readAsBytesSync();

  SecurityContext serverContext() => SecurityContext(withTrustedRoots: false)
    ..useCertificateChain(certPath)
    ..usePrivateKey(keyPath);
}

Uint8List _pemToDer(String pem) {
  final body = pem
      .split('\n')
      .skipWhile((l) => !l.startsWith('-----BEGIN CERTIFICATE'))
      .skip(1)
      .takeWhile((l) => !l.startsWith('-----END'))
      .join();
  return base64.decode(body);
}

/// Generates certificates into a fresh directory under `test/.generated/`.
class CertFactory {
  CertFactory._(this.dir);

  final Directory dir;
  var _n = 0;

  static CertFactory create() {
    final root = Directory('test/.generated')..createSync(recursive: true);
    return CertFactory._(root.createTempSync('certs'));
  }

  void dispose() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  static void _run(List<String> args, {String? stdin}) {
    final ProcessResult r;
    try {
      r = Process.runSync('openssl', args);
    } on ProcessException catch (e) {
      throw StateError('openssl is required to run these tests: $e');
    }
    if (r.exitCode != 0) {
      throw StateError('openssl ${args.first} failed: ${r.stderr}');
    }
  }

  String _p(String name) => '${dir.path}/$name';

  /// A self-signed leaf valid for [days] days, with the given SAN list
  /// (`DNS:localhost,IP:127.0.0.1` by default).
  TestCert selfSigned({
    String cn = 'localhost',
    String org = 'Test',
    String san = 'DNS:localhost,IP:127.0.0.1',
    int days = 30,
  }) {
    final id = _n++;
    final cert = _p('ss$id.pem');
    final key = _p('ss$id.key');
    _run([
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', //
      '-keyout', key, '-out', cert, '-days', '$days',
      '-subj', '/CN=$cn/O=$org', '-addext', 'subjectAltName=$san',
    ]);
    return TestCert(certPath: cert, keyPath: key);
  }

  /// A self-signed leaf that expired in January 2020.
  TestCert expiredSelfSigned() {
    final id = _n++;
    final work = Directory(_p('ca$id'))..createSync();
    File('${work.path}/index.txt').writeAsStringSync('');
    File('${work.path}/serial').writeAsStringSync('01\n');
    Directory('${work.path}/new').createSync();
    final cnf = '${work.path}/ca.cnf';
    File(cnf).writeAsStringSync('''
[ca]
default_ca = c
[c]
dir = ${work.path}
database = ${work.path}/index.txt
new_certs_dir = ${work.path}/new
serial = ${work.path}/serial
default_md = sha256
policy = p
copy_extensions = copy
[p]
commonName = supplied
[req]
distinguished_name = dn
[dn]
''');
    final key = '${work.path}/e.key';
    final csr = '${work.path}/e.csr';
    final cert = '${work.path}/e.pem';
    _run([
      'req', '-newkey', 'rsa:2048', '-nodes', '-keyout', key, '-out', csr, //
      '-subj', '/CN=localhost', '-config', cnf,
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
    ]);
    _run([
      'ca', '-batch', '-config', cnf, '-selfsign', '-keyfile', key, //
      '-in', csr, '-out', cert, '-notext',
      '-startdate', '20200101000000Z', '-enddate', '20200102000000Z',
    ]);
    return TestCert(certPath: cert, keyPath: key);
  }

  /// A test CA. Pass [TestCa.pemBytes] as `additionalTrustedRootsPem`.
  TestCa ca() {
    final id = _n++;
    final cert = _p('root$id.pem');
    final key = _p('root$id.key');
    _run([
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', key, //
      '-out', cert, '-days', '30', '-subj', '/CN=Test Root CA',
      '-addext', 'basicConstraints=critical,CA:TRUE',
      '-addext', 'keyUsage=critical,keyCertSign,cRLSign',
    ]);
    return TestCa._(this, cert, key);
  }
}

class TestCa {
  TestCa._(this._factory, this.certPath, this._keyPath);

  final CertFactory _factory;
  final String certPath;
  final String _keyPath;

  List<int> get pemBytes => File(certPath).readAsBytesSync();

  /// A leaf signed by this CA.
  TestCert issue({
    String cn = 'localhost',
    String san = 'DNS:localhost,IP:127.0.0.1',
  }) {
    final id = _factory._n++;
    final key = _factory._p('leaf$id.key');
    final csr = _factory._p('leaf$id.csr');
    final cert = _factory._p('leaf$id.pem');
    final ext = _factory._p('leaf$id.ext');
    File(ext).writeAsStringSync('subjectAltName=$san\n');
    CertFactory._run([
      'req', '-newkey', 'rsa:2048', '-nodes', '-keyout', key, '-out', csr, //
      '-subj', '/CN=$cn',
    ]);
    CertFactory._run([
      'x509', '-req', '-in', csr, '-CA', certPath, '-CAkey', _keyPath, //
      '-CAcreateserial', '-out', cert, '-days', '30', '-extfile', ext,
    ]);
    return TestCert(certPath: cert, keyPath: key);
  }
}
