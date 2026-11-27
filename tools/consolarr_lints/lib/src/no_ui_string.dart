// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:consolarr_lints/src/paths.dart';

/// Reports string literals in user-facing positions.
///
/// User-facing text must come from generated localizations. Flagged
/// positions: the first positional argument of `Text`/`SelectableText`, and
/// the `tooltip`, `semanticsLabel`, `semanticLabel`, `hintText`, `labelText`,
/// `helperText`, `errorText` and `counterText` named arguments, plus
/// `SnackBar.content`, `Tooltip.message` and `Semantics.label`/`hint`.
///
/// Literals without any letter (for example a `'·'` separator) are ignored.
/// For non-UI strings that happen to sit in such a position, suppress with a
/// reason: `// ignore: consolarr_no_ui_string -- <why this is not UI text>`.
class NoUiString extends AnalysisRule {
  NoUiString()
    : super(
        name: 'consolarr_no_ui_string',
        description:
            'User-facing text must come from localizations, not string '
            'literals.',
      );

  static const LintCode code = LintCode(
    'consolarr_no_ui_string',
    'Hardcoded user-facing string.',
    correctionMessage:
        'Use a generated localization. For non-UI text add '
        '"// ignore: consolarr_no_ui_string -- <reason>".',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (context.isInTestDirectory ||
        isIntegrationTestPath(context.definingUnit.file.path)) {
      return;
    }
    final visitor = _Visitor(this);
    registry
      ..addInstanceCreationExpression(this, visitor)
      ..addMethodInvocation(this, visitor);
  }
}

const _textWidgets = {'Text', 'SelectableText'};

const _uiNamedArguments = {
  'tooltip',
  'semanticsLabel',
  'semanticLabel',
  'hintText',
  'labelText',
  'helperText',
  'errorText',
  'counterText',
};

/// Extra (type name -> parameter names) positions.
const _typeSpecificArguments = <String, Set<String>>{
  'SnackBar': {'content'},
  'Tooltip': {'message'},
  'Semantics': {'label', 'hint'},
};

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type.name.lexeme;
    final args = node.argumentList.arguments;
    if (_textWidgets.contains(typeName)) {
      for (final arg in args) {
        if (arg is! NamedArgument) {
          _check(arg.argumentExpression);
          break;
        }
      }
    }
    final extra = _typeSpecificArguments[typeName] ?? const <String>{};
    for (final arg in args) {
      if (arg is NamedArgument) {
        final name = arg.name.lexeme;
        if (_uiNamedArguments.contains(name) || extra.contains(name)) {
          _check(arg.argumentExpression);
        }
      }
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Covers e.g. `decoration.copyWith(hintText: 'x')`.
    for (final arg in node.argumentList.arguments) {
      if (arg is NamedArgument && _uiNamedArguments.contains(arg.name.lexeme)) {
        _check(arg.argumentExpression);
      }
    }
  }

  void _check(Expression expression) {
    if (expression is StringLiteral && _hasLetters(expression)) {
      rule.reportAtNode(expression);
    }
  }
}

final _letter = RegExp(r'\p{L}', unicode: true);

bool _hasLetters(StringLiteral literal) {
  return switch (literal) {
    SimpleStringLiteral(:final value) => _letter.hasMatch(value),
    AdjacentStrings(:final strings) => strings.any(_hasLetters),
    StringInterpolation(:final elements) => elements.any(
      (e) => e is InterpolationString && _letter.hasMatch(e.value),
    ),
  };
}
