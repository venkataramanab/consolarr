# consolarr_lints

Analyzer plugin (first-party `analysis_server_plugin`) with Consolarr's project
rules. It is enabled for the whole workspace from the root
`analysis_options.yaml` and loaded by `dart analyze` / the IDE (Dart 3.10+).

| Rule | Reports |
| --- | --- |
| `consolarr_no_ui_string` | String literals in user-facing positions: `Text`/`SelectableText` data, `tooltip`, `semanticsLabel`/`semanticLabel`, `hintText`, `labelText`, `helperText`, `errorText`, `counterText`, `SnackBar.content`, `Tooltip.message`, `Semantics.label`/`hint`, `TextSpan.text` (`Text.rich`), `Tab.text`, `Semantics.value`, `prefixText`, `suffixText`, `onTapHint`, `onLongPressHint`, `DropdownMenuEntry.label`, the message of `SemanticsService.announce`/`sendAnnouncement`/`tooltip`, and the `label` of `NavigationDestination`, `NavigationRailDestination`, `NavigationRail`, `NavigationDrawerDestination` and `BottomNavigationBarItem`. Conditionals, `??` and `+` concatenations are looked through. Literals with no letters (e.g. a `·` separator) are ignored; `test/` and `integration_test/` are exempt. |
| `consolarr_bad_certificate_callback` | Any use of `badCertificateCallback`, `onBadCertificate`, `HttpOverrides`, `setTrustedCertificates(Bytes)` or `withTrustedRoots: false` outside `packages/security/lib/src/http/secure_http_client_factory.dart` (matched by package and package-relative path; the test harness's access guard may name `HttpOverrides` only). Generated `*.g.dart` files are analysed too. |
| `consolarr_no_print` | `print` / `debugPrint` calls outside `packages/observability/lib/src/logger.dart`. |

Suppress a non-UI string with a reason:

```dart
// ignore: consolarr_no_ui_string -- debug-only label, never shown to users
```

The plugin API reports these at `info` severity, so CI runs
`dart analyze --fatal-infos`. This package is intentionally **not** a workspace
member (its analyzer/test dependencies must not constrain the Flutter
workspace); it has its own `pubspec.lock`. Run its tests with
`dart run melos run test:lints`.
