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
/// `SnackBar.content`, `Tooltip.message`, `Semantics.label`/`hint`,
/// `TextSpan.text` (so `Text.rich`), `Tab.text`, `Semantics.value`,
/// `prefixText`, `suffixText`, `onTapHint`, `onLongPressHint`,
/// `DropdownMenuEntry.label`, the message of `SemanticsService.announce` /
/// `sendAnnouncement` / `tooltip` and the `label` of
/// `NavigationDestination`, `NavigationRailDestination`, `NavigationRail`,
/// `NavigationDrawerDestination` and `BottomNavigationBarItem`.
///
/// Conditionals (`b ? 'a' : 'b'`), `??` fallbacks, `+` concatenations and
/// parentheses are looked through.
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
  'prefixText',
  'suffixText',
  'onTapHint',
  'onLongPressHint',
};

/// Extra (type name -> parameter names) positions.
const _typeSpecificArguments = <String, Set<String>>{
  'SnackBar': {'content'},
  'Tooltip': {'message'},
  'Semantics': {'label', 'hint', 'value'},
  'DropdownMenuEntry': {'label'},
  'TextSpan': {'text'},
  'Tab': {'text'},
  'NavigationDestination': {'label'},
  'NavigationRailDestination': {'label'},
  'NavigationRail': {'label'},
  'NavigationDrawerDestination': {'label'},
  'BottomNavigationBarItem': {'label'},
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
    // `SemanticsService.announce(message, ...)` and
    // `SemanticsService.sendAnnouncement(view, message, ...)` speak the
    // message to the user.
    final target = node.target;
    if (target is SimpleIdentifier && target.name == 'SemanticsService') {
      final index = switch (node.methodName.name) {
        'announce' || 'tooltip' => 0,
        'sendAnnouncement' => 1,
        _ => -1,
      };
      if (index >= 0) {
        final positional = [
          for (final arg in node.argumentList.arguments)
            if (arg is! NamedArgument) arg.argumentExpression,
        ];
        if (positional.length > index) _check(positional[index]);
      }
    }
    // Covers e.g. `decoration.copyWith(hintText: 'x')`.
    for (final arg in node.argumentList.arguments) {
      if (arg is NamedArgument && _uiNamedArguments.contains(arg.name.lexeme)) {
        _check(arg.argumentExpression);
      }
    }
  }

  void _check(Expression expression) {
    switch (expression) {
      case StringLiteral() when _hasLetters(expression):
        rule.reportAtNode(expression);
      case ParenthesizedExpression(:final expression):
        _check(expression);
      case ConditionalExpression(:final thenExpression, :final elseExpression):
        _check(thenExpression);
        _check(elseExpression);
      case BinaryExpression(
        :final leftOperand,
        :final rightOperand,
        :final operator,
      ):
        final op = operator.lexeme;
        if (op == '+') {
          _check(leftOperand);
          _check(rightOperand);
        } else if (op == '??') {
          _check(rightOperand);
        }
      default:
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
