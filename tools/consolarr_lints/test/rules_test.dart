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
class TextSpan { const TextSpan({String? text, List<Object>? children}); }
class Tab { const Tab({String? text}); }
class NavigationDestination { const NavigationDestination({required String label}); }
class NavigationRailDestination { const NavigationRailDestination({required Object label}); }
class NavigationRail { const NavigationRail({String? label}); }
class BottomNavigationBarItem { const BottomNavigationBarItem({required String label}); }
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

  Future<void> test_conditional_and_concatenation() async {
    final src =
        "$_widgets\nvoid f(bool b, String n, String? m) { Text(b ? 'Yes' : 'No'); "
        "Text('Hello ' + n); Text(n + ' items'); Text(('Paren')); "
        "Text(m ?? 'Fallback'); Text(b ? n : n); Text(n + n); }";
    await assertDiagnostics(src, [
      lint(src.indexOf("'Yes'"), 5),
      lint(src.indexOf("'No'"), 4),
      lint(src.indexOf("'Hello '"), 8),
      lint(src.indexOf("' items'"), 8),
      lint(src.indexOf("'Paren'"), 7),
      lint(src.indexOf("'Fallback'"), 10),
    ]);
  }

  Future<void> test_text_span_and_tab() async {
    final src =
        "$_widgets\nvoid f() { const TextSpan(text: 'Rich'); "
        "const Tab(text: 'Tab one'); }";
    await assertDiagnostics(src, [
      lint(src.indexOf("'Rich'"), 6),
      lint(src.indexOf("'Tab one'"), 9),
    ]);
  }

  Future<void> test_navigation_labels() async {
    final src =
        "$_widgets\nvoid f() { const NavigationDestination(label: 'Home'); "
        "const NavigationRailDestination(label: 'Queue'); "
        "const NavigationRail(label: 'Rail'); "
        "const BottomNavigationBarItem(label: 'Calendar'); }";
    await assertDiagnostics(src, [
      lint(src.indexOf("'Home'"), 6),
      lint(src.indexOf("'Queue'"), 7),
      lint(src.indexOf("'Rail'"), 6),
      lint(src.indexOf("'Calendar'"), 10),
    ]);
  }

  Future<void> test_navigation_label_from_variable_ok() async {
    await assertNoDiagnostics(
      "$_widgets\nvoid f(String s) { NavigationDestination(label: s); "
      "Tab(text: s); TextSpan(text: s); }",
    );
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

  static const _src = '''
class C { void Function()? badCertificateCallback; }
void f(C c) { c.badCertificateCallback = () {}; }
''';

  Future<void> test_reported_elsewhere() async {
    await assertDiagnostics(_src, [
      lint(_src.indexOf('badCertificateCallback = '), 22),
    ]);
  }

  Future<void> test_allowed_in_factory_file() async {
    const root = '/home/test/packages/security';
    newPubspecYamlFile(root, 'name: security');
    final path = '$root/lib/src/http/secure_http_client_factory.dart';
    newFile(path, _src);
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_lookalike_path_is_not_allowed() async {
    // Same trailing path, different package location: must still be reported.
    const root = '/home/test/apps/x/packages/other';
    newPubspecYamlFile(root, 'name: other');
    final path = '$root/lib/src/http/secure_http_client_factory.dart';
    newFile(path, _src);
    await assertDiagnosticsInFile(path, [
      lint(_src.indexOf('badCertificateCallback = '), 22),
    ]);
  }

  Future<void> test_other_file_in_security_package_is_not_allowed() async {
    const root = '/home/test/packages/security';
    newPubspecYamlFile(root, 'name: security');
    final path = '$root/lib/src/http/other.dart';
    newFile(path, _src);
    await assertDiagnosticsInFile(path, [
      lint(_src.indexOf('badCertificateCallback = '), 22),
    ]);
  }

  Future<void> test_http_overrides_allowed_only_in_access_guard() async {
    const src =
        'class HttpOverrides { static HttpOverrides? global; }\n'
        'class G extends HttpOverrides {}\n'
        'void f() { HttpOverrides.global = null; }';
    const root = '/home/test/packages/test_harness';
    newPubspecYamlFile(root, 'name: test_harness');
    final path = '$root/lib/src/access_guard.dart';
    newFile(path, src);
    await assertNoDiagnosticsInFile(path);

    final other = '$root/lib/src/other.dart';
    newFile(other, src);
    await assertDiagnosticsInFile(other, [
      lint(src.indexOf('HttpOverrides? global'), 14),
      lint(src.indexOf('extends HttpOverrides') + 8, 13),
      lint(src.indexOf('HttpOverrides.global'), 13),
    ]);
  }

  Future<void> test_access_guard_may_not_use_other_trust_apis() async {
    const src =
        'class C { void Function()? badCertificateCallback; }\n'
        'void f(C c) { c.badCertificateCallback = () {}; }';
    const root = '/home/test/packages/test_harness';
    newPubspecYamlFile(root, 'name: test_harness');
    final path = '$root/lib/src/access_guard.dart';
    newFile(path, src);
    await assertDiagnosticsInFile(path, [
      lint(src.indexOf('badCertificateCallback = '), 22),
    ]);
  }

  Future<void> test_other_trust_apis_reported() async {
    const src = '''
class HttpOverrides {}
class MyOverrides extends HttpOverrides {}
class SecurityContext {
  SecurityContext({bool withTrustedRoots = false});
  void setTrustedCertificates(String f) {}
  void setTrustedCertificatesBytes(List<int> b) {}
}
void g({Object? onBadCertificate}) {}
void f() {
  final c = SecurityContext(withTrustedRoots: false);
  c.setTrustedCertificates('x');
  c.setTrustedCertificatesBytes([]);
  g(onBadCertificate: 1);
}
''';
    await assertDiagnostics(src, [
      lint(src.indexOf('extends HttpOverrides') + 8, 13),
      lint(src.indexOf('withTrustedRoots: false)'), 23),
      lint(src.indexOf('c.setTrustedCertificates') + 2, 22),
      lint(src.indexOf('c.setTrustedCertificatesBytes') + 2, 27),
      lint(src.indexOf('onBadCertificate: 1'), 19),
    ]);
  }

  Future<void> test_trusted_roots_true_ok() async {
    await assertNoDiagnostics('''
class SecurityContext {
  SecurityContext({bool withTrustedRoots = false});
}
void f() { SecurityContext(withTrustedRoots: true); }
''');
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
