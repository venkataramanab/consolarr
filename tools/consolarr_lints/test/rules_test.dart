// SPDX-License-Identifier: GPL-3.0-or-later

// ignore_for_file: non_constant_identifier_names -- test_reflective_loader convention
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:consolarr_lints/src/no_bad_certificate_callback.dart';
import 'package:consolarr_lints/src/no_print.dart';
import 'package:consolarr_lints/src/no_ui_string.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

const _widgets = r'''
class Text { const Text(String data, {String? semanticsLabel}); }
class SelectableText { const SelectableText(String data); }
class SnackBar { const SnackBar({required Object content}); }
class Tooltip { const Tooltip({String? message}); }
class InputDecoration {
  const InputDecoration({String? hintText, String? labelText});
  InputDecoration copyWith({String? hintText}) => this;
}
class IconButton { const IconButton({String? tooltip}); }
''';

@reflectiveTest
class NoUiStringTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = NoUiString();
    super.setUp();
  }

  Future<void> test_text_literal() async {
    final src = "$_widgets\nvoid f() { const Text('Hello'); }";
    await assertDiagnostics(src, [lint(src.indexOf("'Hello'"), 7)]);
  }

  Future<void> test_text_interpolation() async {
    final src = "$_widgets\nvoid f(int n) { Text('Count \$n'); }";
    await assertDiagnostics(src, [lint(src.indexOf("'Count"), 10)]);
  }

  Future<void> test_text_variable_ok() async {
    await assertNoDiagnostics('$_widgets\nvoid f(String s) { Text(s); }');
  }

  Future<void> test_separator_without_letters_ok() async {
    await assertNoDiagnostics("$_widgets\nvoid f() { const Text('·'); }");
  }

  Future<void> test_named_ui_arguments() async {
    final src =
        "$_widgets\nvoid f() { const IconButton(tooltip: 'Add'); "
        "const InputDecoration(hintText: 'Host', labelText: 'Name'); "
        "const Tooltip(message: 'Tip'); "
        "const SnackBar(content: 'Saved'); "
        "const InputDecoration().copyWith(hintText: 'x1'); }";
    await assertDiagnostics(src, [
      lint(src.indexOf("'Add'"), 5),
      lint(src.indexOf("'Host'"), 6),
      lint(src.indexOf("'Name'"), 6),
      lint(src.indexOf("'Tip'"), 5),
      lint(src.indexOf("'Saved'"), 7),
      lint(src.indexOf("'x1'"), 4),
    ]);
  }

  Future<void> test_ignore_comment() async {
    await assertNoDiagnostics(
      "$_widgets\nvoid f() {\n"
      "  // ignore: consolarr_no_ui_string -- debug-only sample\n"
      "  const Text('Hello');\n}",
    );
  }
}

@reflectiveTest
class NoBadCertificateCallbackTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = NoBadCertificateCallback();
    super.setUp();
  }

  Future<void> test_reported_elsewhere() async {
    const src = '''
class C { void Function()? badCertificateCallback; }
void f(C c) { c.badCertificateCallback = () {}; }
''';
    await assertDiagnostics(src, [
      lint(src.indexOf('badCertificateCallback = '), 22),
    ]);
  }

  Future<void> test_allowed_in_factory_file() async {
    const src = '''
class C { void Function()? badCertificateCallback; }
void f(C c) { c.badCertificateCallback = () {}; }
''';
    final path =
        '$testPackageRootPath/packages/security/lib/src/http/'
        'secure_http_client_factory.dart';
    newFile(path, src);
    await assertNoDiagnosticsInFile(path);
  }
}

@reflectiveTest
class NoPrintTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = NoPrint();
    super.setUp();
  }

  Future<void> test_print_reported() async {
    const src = "void f() { print('x'); }";
    await assertDiagnostics(src, [lint(src.indexOf('print'), 5)]);
  }

  Future<void> test_debugPrint_reported() async {
    const src = "void debugPrint(String? s) {}\nvoid f() { debugPrint('x'); }";
    await assertDiagnostics(src, [lint(src.lastIndexOf('debugPrint'), 10)]);
  }

  Future<void> test_other_method_ok() async {
    await assertNoDiagnostics('void f(List<int> l) { l.add(1); }');
  }
}

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NoUiStringTest);
    defineReflectiveTests(NoBadCertificateCallbackTest);
    defineReflectiveTests(NoPrintTest);
  });
}
