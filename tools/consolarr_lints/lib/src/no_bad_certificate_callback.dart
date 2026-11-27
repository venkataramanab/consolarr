// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:consolarr_lints/src/paths.dart';

/// A file (identified by package name and package-relative path) allowed to
/// use some TLS-trust identifiers. [identifiers] `null` means all of them.
class AllowedTlsFile {
  const AllowedTlsFile(this.package, this.relativePath, [this.identifiers]);

  final String package;
  final String relativePath;
  final Set<String>? identifiers;
}

/// The only exemptions. The factory owns TLS trust; the test harness's access
/// guard only *observes* `HttpClient` creation through `HttpOverrides` and
/// never changes certificate validation.
const allowedTlsFiles = [
  AllowedTlsFile('security', 'lib/src/http/secure_http_client_factory.dart'),
  AllowedTlsFile('test_harness', 'lib/src/access_guard.dart', {
    'HttpOverrides',
  }),
  AllowedTlsFile('test_harness', 'test/access_guard_test.dart', {
    'HttpOverrides',
  }),
];

/// Repo-relative form of the main allowed file, for messages.
const allowedBadCertificateFile =
    'packages/security/lib/src/http/secure_http_client_factory.dart';

/// Identifiers that can weaken or replace certificate validation.
const forbiddenTlsIdentifiers = {
  'badCertificateCallback',
  'onBadCertificate',
  'HttpOverrides',
  'setTrustedCertificates',
  'setTrustedCertificatesBytes',
};

/// Reports any use of TLS-trust-altering APIs outside the one file that
/// implements trust-on-first-use pinning: `badCertificateCallback`,
/// `onBadCertificate`, `HttpOverrides`, `setTrustedCertificates(Bytes)` and
/// `SecurityContext(withTrustedRoots: <anything but literal true>)`.
class NoBadCertificateCallback extends AnalysisRule {
  NoBadCertificateCallback()
    : super(
        name: 'consolarr_bad_certificate_callback',
        description:
            'TLS trust may only be customised in '
            'secure_http_client_factory.dart.',
      );

  static const LintCode code = LintCode(
    'consolarr_bad_certificate_callback',
    'Certificate validation may only be customised in '
        'packages/security/lib/src/http/secure_http_client_factory.dart.',
    correctionMessage:
        'Obtain HTTP clients from SecureHttpClientFactory instead.',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    var allowed = <String>{};
    for (final file in allowedTlsFiles) {
      if (isFileInPackage(
        filePath: context.definingUnit.file.path,
        packageRoot: context.package?.root.path,
        packageName: file.package,
        relativePath: file.relativePath,
      )) {
        final ids = file.identifiers;
        if (ids == null) return;
        allowed = ids;
      }
    }
    final visitor = _Visitor(this, allowed);
    registry
      ..addSimpleIdentifier(this, visitor)
      ..addNamedType(this, visitor)
      ..addNamedArgument(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.allowed);

  final AnalysisRule rule;
  final Set<String> allowed;

  bool _forbidden(String name) =>
      forbiddenTlsIdentifiers.contains(name) && !allowed.contains(name);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_forbidden(node.name)) {
      rule.reportAtNode(node);
    }
  }

  @override
  void visitNamedType(NamedType node) {
    if (_forbidden(node.name.lexeme)) {
      rule.reportAtNode(node);
    }
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    final name = node.name.lexeme;
    final value = node.argumentExpression;
    if (_forbidden(name)) {
      rule.reportAtNode(node);
    } else if (name == 'withTrustedRoots' &&
        !(value is BooleanLiteral && value.value)) {
      // Anything but the literal `true` (false, a variable, `!true`, ...)
      // can disable the platform trust store.
      rule.reportAtNode(node);
    }
  }
}
