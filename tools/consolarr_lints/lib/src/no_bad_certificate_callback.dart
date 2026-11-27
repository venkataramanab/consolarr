// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:consolarr_lints/src/paths.dart';

/// The only file allowed to touch `badCertificateCallback`.
const allowedBadCertificateFile =
    'packages/security/lib/src/http/secure_http_client_factory.dart';

/// Reports any use of `badCertificateCallback` outside the one file that
/// implements trust-on-first-use pinning.
class NoBadCertificateCallback extends AnalysisRule {
  NoBadCertificateCallback()
    : super(
        name: 'consolarr_bad_certificate_callback',
        description:
            'badCertificateCallback may only be used in '
            'secure_http_client_factory.dart.',
      );

  static const LintCode code = LintCode(
    'consolarr_bad_certificate_callback',
    'badCertificateCallback is only allowed in '
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
    if (pathEndsWith(
      context.definingUnit.file.path,
      allowedBadCertificateFile,
    )) {
      return;
    }
    registry.addSimpleIdentifier(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'badCertificateCallback') {
      rule.reportAtNode(node);
    }
  }
}
