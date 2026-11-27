// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:consolarr_lints/src/paths.dart';

/// The package and package-relative file allowed to call `print`/`debugPrint`.
const allowedPrintPackage = 'observability';
const allowedPrintFile = 'lib/src/logger.dart';

/// Reports calls to `print` and `debugPrint` outside the redacting logger.
class NoPrint extends AnalysisRule {
  NoPrint()
    : super(
        name: 'consolarr_no_print',
        description: 'print/debugPrint are only allowed inside the logger.',
      );

  static const LintCode code = LintCode(
    'consolarr_no_print',
    'print/debugPrint are only allowed in the redacting logger.',
    correctionMessage: 'Use AppLogger from package:observability.',
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
      packageName: allowedPrintPackage,
      relativePath: allowedPrintFile,
    )) {
      return;
    }
    registry.addMethodInvocation(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target != null) return;
    final name = node.methodName.name;
    if (name == 'print' || name == 'debugPrint') {
      rule.reportAtNode(node.methodName);
    }
  }
}
