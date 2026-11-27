// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';

import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

const _v = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = true,
  bool reduceTransparency = false,
}) async {
  applyVariantView(tester, _v);
  await tester.pumpWidget(
    harnessApp(
      _v,
      ConsolarrEffectsScope(
        reduceMotion: reduceMotion,
        reduceTransparency: reduceTransparency,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('ConsolarrEffects', () {
    testWidgets('defaults allow glass and motion', (tester) async {
      late ConsolarrEffects e;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (c) {
              e = ConsolarrEffects.of(c);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(e.useGlass, isTrue);
      expect(e.animate, isTrue);
    });

    testWidgets('system disableAnimations and highContrast turn effects off', (
      tester,
    ) async {
      late ConsolarrEffects e;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            highContrast: true,
          ),
          child: Builder(
            builder: (c) {
              e = ConsolarrEffects.of(c);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(e.useGlass, isFalse);
      expect(e.animate, isFalse);
    });

    testWidgets('scope flags override', (tester) async {
      late ConsolarrEffects e;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: ConsolarrEffectsScope(
            lowEnd: true,
            reduceMotion: true,
            child: Builder(
              builder: (c) {
                e = ConsolarrEffects.of(c);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(e.useGlass, isFalse);
      expect(e.animate, isFalse);
    });
  });

  group('GlassBar', () {
    testWidgets('blurs when glass is allowed', (tester) async {
      await _pump(tester, const GlassBar(child: SizedBox(height: 40)));
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('solid surface without blur under reduced transparency', (
      tester,
    ) async {
      await _pump(
        tester,
        const GlassBar(child: SizedBox(height: 40)),
        reduceTransparency: true,
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('MeasuredBarHeight reports the laid out height', (
      tester,
    ) async {
      final height = ValueNotifier<double>(0);
      await _pump(
        tester,
        MeasuredBarHeight(
          height: height,
          child: const GlassBar(child: SizedBox(height: 40, width: 100)),
        ),
      );
      await tester.pump();
      expect(height.value, 40);
    });
  });

  group('FloatingNavBar', () {
    Widget bar(ValueChanged<int> onSelected) => FloatingNavBar(
      selectedIndex: 0,
      onSelected: onSelected,
      destinations: const [
        FloatingNavDestination(
          icon: Icons.tv_outlined,
          selectedIcon: Icons.tv,
          label: 'Series',
        ),
        FloatingNavDestination(
          icon: Icons.download_outlined,
          selectedIcon: Icons.download,
          label: 'Torrents',
        ),
      ],
    );

    testWidgets('reports taps and exposes selected state', (tester) async {
      final handle = tester.ensureSemantics();
      var tapped = -1;
      await _pump(tester, bar((i) => tapped = i));
      await tester.tap(find.text('Torrents'));
      expect(tapped, 1);
      final selected = tester.getSemantics(find.text('Series'));
      expect(selected.flagsCollection.isSelected, Tristate.isTrue);
      expect(selected.flagsCollection.isButton, isTrue);
      final other = tester.getSemantics(find.text('Torrents'));
      expect(other.flagsCollection.isSelected, Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('targets are at least 48dp tall', (tester) async {
      await _pump(tester, bar((_) {}));
      final size = tester.getSize(find.byType(InkWell).first);
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('PosterCard', () {
    testWidgets('passes a display-size cacheWidth to the image builder', (
      tester,
    ) async {
      int? cacheWidth;
      await _pump(
        tester,
        SizedBox(
          width: 120,
          child: PosterCard(
            title: 'Example Show',
            imageBuilder: (context, w) {
              cacheWidth = w;
              return const SizedBox();
            },
          ),
        ),
      );
      // 120 logical px at device pixel ratio 1.0.
      expect(cacheWidth, 120);
    });

    testWidgets('shows a placeholder without artwork and announces title', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const SizedBox(
          width: 120,
          child: PosterCard(title: 'Example Show', subtitle: '2021'),
        ),
      );
      expect(find.byType(ArtworkPlaceholder), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Example Show')).label,
        'Example Show, 2021',
      );
      handle.dispose();
    });

    testWidgets('tap and long press', (tester) async {
      var taps = 0;
      var longs = 0;
      await _pump(
        tester,
        SizedBox(
          width: 120,
          child: PosterCard(
            title: 'Example Show',
            onTap: () => taps++,
            onLongPress: () => longs++,
          ),
        ),
      );
      await tester.tap(find.byType(PosterCard));
      await tester.longPress(find.byType(PosterCard));
      expect([taps, longs], [1, 1]);
    });
  });

  group('MediaListTile', () {
    testWidgets('joins metadata with a dot and announces it', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const MediaListTile(
          title: 'Example Show',
          metadata: ['2021', 'Example Network'],
        ),
      );
      expect(find.text('2021 · Example Network'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Example Show')).label,
        'Example Show, 2021 · Example Network',
      );
      handle.dispose();
    });
  });

  group('ProgressFillRow', () {
    ProgressFillRow row(ProgressRowState state, {double progress = 0.5}) =>
        ProgressFillRow(
          title: 'Example Item',
          progress: progress,
          state: state,
          stateIcon: Icons.arrow_downward,
          stateLabel: 'Downloading',
          progressLabel: '50%',
          semanticsLabel: 'Example Item, Downloading, 50 percent',
        );

    testWidgets('fill width is proportional to progress', (tester) async {
      await _pump(tester, row(ProgressRowState.idle));
      final box = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(box.widthFactor, 0.5);
    });

    testWidgets('progress is clamped', (tester) async {
      await _pump(tester, row(ProgressRowState.idle, progress: 7));
      expect(
        tester
            .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
            .widthFactor,
        1,
      );
    });

    testWidgets('fill starts at the leading edge in LTR and RTL', (
      tester,
    ) async {
      await _pump(tester, row(ProgressRowState.idle));
      final rowRect = tester.getRect(find.byType(ProgressFillRow));
      final fill = tester.getRect(find.byType(FractionallySizedBox));
      expect(fill.left, rowRect.left);

      const rtl = HarnessVariant(
        size: Size(360, 800),
        textScale: 1,
        locale: Locale('ar'),
        brightness: Brightness.dark,
      );
      applyVariantView(tester, rtl);
      await tester.pumpWidget(
        harnessApp(
          rtl,
          ConsolarrEffectsScope(
            reduceMotion: true,
            child: Scaffold(body: row(ProgressRowState.idle)),
          ),
        ),
      );
      await tester.pump();
      final rtlRow = tester.getRect(find.byType(ProgressFillRow));
      final rtlFill = tester.getRect(find.byType(FractionallySizedBox));
      expect(rtlFill.right, rtlRow.right);
    });

    testWidgets('announces the caller supplied state and percentage', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, row(ProgressRowState.active));
      expect(
        tester.getSemantics(find.byType(ProgressFillRow)).label,
        'Example Item, Downloading, 50 percent',
      );
      handle.dispose();
    });

    testWidgets('state is shown as icon plus text', (tester) async {
      await _pump(tester, row(ProgressRowState.paused));
      expect(find.text('Downloading'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('pulses only when motion is allowed', (tester) async {
      await _pump(tester, row(ProgressRowState.active), reduceMotion: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);

      await _pump(tester, row(ProgressRowState.active));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('paused rows never animate', (tester) async {
      await _pump(tester, row(ProgressRowState.paused), reduceMotion: false);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('StatusChip', () {
    testWidgets('always shows icon and text', (tester) async {
      await _pump(
        tester,
        const StatusChip(
          label: 'Healthy',
          icon: Icons.check_circle,
          tone: StatusTone.success,
        ),
      );
      expect(find.text('Healthy'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('expands details on tap and exposes expanded state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const StatusChip(
          label: 'Degraded',
          icon: Icons.warning,
          details: 'Slow responses',
        ),
      );
      expect(find.text('Slow responses'), findsNothing);
      await tester.tap(find.text('Degraded'));
      await tester.pump();
      expect(find.text('Slow responses'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Degraded')).flagsCollection.isExpanded,
        Tristate.isTrue,
      );
      handle.dispose();
    });
  });

  group('SkeletonBox', () {
    testWidgets('shimmers when motion is allowed', (tester) async {
      await _pump(
        tester,
        const SkeletonBox(width: 100, height: 20),
        reduceMotion: false,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('static under reduced motion', (tester) async {
      await _pump(tester, const SkeletonBox(width: 100, height: 20));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('is hidden from accessibility', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const SkeletonBox(width: 100, height: 20));
      expect(find.byType(ExcludeSemantics), findsWidgets);
      handle.dispose();
    });
  });

  group('state views', () {
    testWidgets('EmptyState action fires', (tester) async {
      var n = 0;
      await _pump(
        tester,
        SizedBox(
          height: 500,
          child: EmptyState(
            icon: Icons.tv,
            headline: 'Nothing yet',
            message: 'Add a server',
            actionLabel: 'Add',
            onAction: () => n++,
          ),
        ),
      );
      await tester.tap(find.text('Add'));
      expect(n, 1);
      expect(find.text('Nothing yet'), findsOneWidget);
    });

    testWidgets('ErrorState shows cause, hint and both actions', (
      tester,
    ) async {
      var retry = 0;
      var other = 0;
      await _pump(
        tester,
        SizedBox(
          height: 600,
          child: ErrorState(
            headline: 'Cannot connect',
            message: 'The server did not answer.',
            hint: 'Check the address.',
            retryLabel: 'Retry',
            onRetry: () => retry++,
            secondaryLabel: 'Edit',
            onSecondary: () => other++,
          ),
        ),
      );
      expect(find.text('The server did not answer.'), findsOneWidget);
      expect(find.text('Check the address.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.tap(find.text('Edit'));
      expect([retry, other], [1, 1]);
    });

    testWidgets('OfflineBanner shows age and retry', (tester) async {
      var n = 0;
      await _pump(
        tester,
        OfflineBanner(
          message: 'Offline',
          ageText: 'Updated 5 minutes ago',
          retryLabel: 'Reconnect',
          onRetry: () => n++,
        ),
      );
      expect(find.text('Updated 5 minutes ago'), findsOneWidget);
      await tester.tap(find.text('Reconnect'));
      expect(n, 1);
    });
  });

  group('CertificateTrustSheet', () {
    CertificateTrustSheet sheet(
      CertificateSheetVariant variant, {
      VoidCallback? onAccept,
      VoidCallback? onReject,
    }) => CertificateTrustSheet(
      variant: variant,
      title: 'Untrusted certificate',
      serverName: 'Example Server',
      explanation: 'Check the fingerprint.',
      warning: variant == CertificateSheetVariant.firstUse
          ? null
          : 'This is different from before.',
      fingerprintLabel: 'Fingerprint',
      fingerprint: 'AB:CD:EF:01:AB:CD:EF:01',
      previousFingerprintLabel: 'Previous',
      previousFingerprint: variant == CertificateSheetVariant.mismatch
          ? '11:22:33:44:11:22:33:44'
          : null,
      subjectLabel: 'Subject',
      subject: 'CN=example',
      issuerLabel: 'Issuer',
      issuer: 'CN=example',
      validityLabel: 'Valid',
      validity: '2026 to 2027',
      acceptLabel: 'Trust',
      rejectLabel: 'Cancel',
      onAccept: onAccept ?? () {},
      onReject: onReject ?? () {},
    );

    testWidgets('first use: accept and reject call back', (tester) async {
      var accept = 0;
      var reject = 0;
      await _pump(
        tester,
        sheet(
          CertificateSheetVariant.firstUse,
          onAccept: () => accept++,
          onReject: () => reject++,
        ),
      );
      expect(find.text('AB:CD:EF:01'), findsNWidgets(2));
      await tester.tap(find.text('Trust'));
      await tester.tap(find.text('Cancel'));
      expect([accept, reject], [1, 1]);
    });

    testWidgets('mismatch shows warning and previous fingerprint', (
      tester,
    ) async {
      await _pump(tester, sheet(CertificateSheetVariant.mismatch));
      expect(find.text('This is different from before.'), findsOneWidget);
      expect(find.text('Previous'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('expired disables accept', (tester) async {
      var accept = 0;
      await _pump(
        tester,
        sheet(CertificateSheetVariant.expired, onAccept: () => accept++),
      );
      await tester.tap(find.text('Trust'), warnIfMissed: false);
      expect(accept, 0);
    });

    testWidgets('show() resolves true on accept, false on dismiss', (
      tester,
    ) async {
      bool? result;
      applyVariantView(tester, _v);
      await tester.pumpWidget(
        harnessApp(
          _v,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await CertificateTrustSheet.show(
                      context,
                      builder: (c, accept, reject) => sheet(
                        CertificateSheetVariant.firstUse,
                        onAccept: accept,
                        onReject: reject,
                      ),
                    ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trust'));
      await tester.pumpAndSettle();
      expect(result, isTrue);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });

  group('SecretTextField', () {
    Widget field({
      TextEditingController? controller,
      ValueChanged<bool>? onReveal,
    }) => SecretTextField(
      controller: controller,
      label: 'API key',
      showTooltip: 'Show key',
      hideTooltip: 'Hide key',
      onRevealChanged: onReveal,
    );

    EditableText editable(WidgetTester tester) =>
        tester.widget<EditableText>(find.byType(EditableText));

    testWidgets('is masked by default with suggestions and autocorrect off', (
      tester,
    ) async {
      await _pump(tester, field());
      final e = editable(tester);
      expect(e.obscureText, isTrue);
      expect(e.enableSuggestions, isFalse);
      expect(e.autocorrect, isFalse);
      expect(e.enableIMEPersonalizedLearning, isFalse);
    });

    testWidgets('toggle reveals, reports and hides again', (tester) async {
      final reports = <bool>[];
      await _pump(tester, field(onReveal: reports.add));
      await tester.tap(find.byTooltip('Show key'));
      await tester.pump();
      expect(editable(tester).obscureText, isFalse);
      expect(find.byTooltip('Hide key'), findsOneWidget);
      await tester.tap(find.byTooltip('Hide key'));
      await tester.pump();
      expect(editable(tester).obscureText, isTrue);
      expect(reports, [true, false]);
    });

    testWidgets('disposing while revealed reports hidden', (tester) async {
      final reports = <bool>[];
      await _pump(tester, field(onReveal: reports.add));
      await tester.tap(find.byTooltip('Show key'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(reports, [true, false]);
    });

    testWidgets('obscured value is not exposed to accessibility', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final controller = TextEditingController(text: 'test-key-0000');
      addTearDown(controller.dispose);
      await _pump(tester, field(controller: controller));
      final node = tester.getSemantics(find.byType(EditableText));
      expect(node.value, isNot(contains('test-key-0000')));
      handle.dispose();
    });
  });
}
