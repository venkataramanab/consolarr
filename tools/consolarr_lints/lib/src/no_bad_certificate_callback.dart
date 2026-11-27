// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:consolarr_lints/src/paths.dart';

/// The package that owns TLS trust decisions.
const allowedTlsPackage = 'security';

/// The only file (relative to [allowedTlsPackage]) allowed to touch TLS trust.
const allowedTlsFile = 'lib/src/http/secure_http_client_factory.dart';

/// Repo-relative form of the allowed file, for messages.
const allowedBadCertificateFile = 'packages/security/$allowedTlsFile';

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
/// `SecurityContext(withTrustedRoots: false)`.
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
    if (isFileInPackage(
      filePath: context.definingUnit.file.path,
      packageRoot: context.package?.root.path,
      packageName: allowedTlsPackage,
      relativePath: allowedTlsFile,
    )) {
      return;
    }
    final visitor = _Visitor(this);
    registry
      ..addSimpleIdentifier(this, visitor)
      ..addNamedType(this, visitor)
      ..addNamedArgument(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (forbiddenTlsIdentifiers.contains(node.name)) {
      rule.reportAtNode(node);
    }
  }

  @override
  void visitNamedType(NamedType node) {
    if (forbiddenTlsIdentifiers.contains(node.name.lexeme)) {
      rule.reportAtNode(node);
    }
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    final name = node.name.lexeme;
    final value = node.argumentExpression;
    if (forbiddenTlsIdentifiers.contains(name)) {
      rule.reportAtNode(node);
    } else if (name == 'withTrustedRoots' &&
        value is BooleanLiteral &&
        !value.value) {
      rule.reportAtNode(node);
    }
  }
}
