// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/arr_common/presentation/add_options_form.dart';
import 'package:consolarr/features/arr_common/presentation/release_controls.dart';
import 'package:consolarr/features/arr_common/presentation/release_row.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

const _labels = ReleaseRowLabels(
  download: 'Download',
  downloadAgain: 'Again',
  grabbing: 'Sending',
  grabbed: 'Sent',
  failed: 'Failed',
  maybeSent: 'Maybe sent',
  rejectedBadge: 'Rejected',
  expand: 'Expand',
  collapse: 'Collapse',
  rejectionsHeading: 'Reasons',
  customFormatsHeading: 'Formats',
  languagesHeading: 'Languages',
);

ReleaseRowData _data({
  ReleaseGrabState grab = ReleaseGrabState.idle,
  bool rejected = false,
  String title = 'Example.Show.S01E01.1080p',
}) => ReleaseRowData(
  title: title,
  facts: const ['WEBDL-1080p', '1.0 GB'],
  semanticsLabel: '$title, WEBDL-1080p',
  isRejected: rejected,
  rejections: rejected ? const ['Not an upgrade'] : const [],
  customFormats: const ['Example Format'],
  languages: const ['English'],
  grab: grab,
);

Widget _host(HarnessVariant v, Widget child) =>
    harnessApp(v, Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  for (final grab in ReleaseGrabState.values) {
    testWidgets('row in state ${grab.name} across the matrix', (tester) async {
      await pumpMatrix(
        tester,
        (v) => _host(
          v,
          ReleaseRow(
            data: _data(
              grab: grab,
              rejected: true,
              title: 'Example.Show.With.A.Very.Long.Release.Name.${'x' * 120}',
            ),
            labels: _labels,
            onDownload: () {},
          ),
        ),
        variants: harnessMatrix(brightnesses: const [Brightness.dark]),
      );
      await expectLabeledTapTargets(tester);
    });
  }

  testWidgets('markup in the title is shown as plain text', (tester) async {
    const title = '<b>bold</b> [link](https://evil.example)';
    await tester.pumpWidget(
      _host(
        harnessMatrix().first,
        ReleaseRow(
          data: _data(title: title),
          labels: _labels,
          onDownload: () {},
        ),
      ),
    );
    expect(find.text(title), findsOneWidget);
  });

  testWidgets('download callback fires; grabbing disables the control', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        harnessMatrix().first,
        ReleaseRow(data: _data(), labels: _labels, onDownload: () => taps++),
      ),
    );
    await tester.tap(find.text('Download'));
    expect(taps, 1);
    await tester.pumpWidget(
      _host(
        harnessMatrix().first,
        ReleaseRow(
          data: _data(grab: ReleaseGrabState.grabbing),
          labels: _labels,
          onDownload: () => taps++,
        ),
      ),
    );
    expect(find.text('Download'), findsNothing);
    expect(find.text('Sending'), findsOneWidget);
  });

  testWidgets('controls: sort menu, reverse and filter chips', (tester) async {
    String? sorted;
    var reversed = 0;
    String? toggled;
    await tester.pumpWidget(
      _host(
        harnessMatrix().first,
        ReleaseControls<String>(
          labels: const ReleaseControlsLabels(
            sortButton: 'Sort: A',
            reverseSort: 'Reverse',
            filterButton: 'Filters (1)',
            clearFilters: 'Clear',
          ),
          sortOptions: const [
            ReleaseSortOption('a', 'A'),
            ReleaseSortOption('b', 'B'),
          ],
          selectedSort: 'a',
          onSort: (k) => sorted = k,
          onReverse: () => reversed++,
          groups: const [
            ReleaseFilterGroup(
              id: 'g',
              label: 'Group',
              options: [
                ReleaseFilterOption(id: 'x', label: 'X', selected: true),
              ],
            ),
          ],
          activeFilters: 1,
          onToggleFilter: (g, o) => toggled = '$g/$o',
          onClearFilters: () {},
        ),
      ),
    );
    await tester.tap(find.text('Sort: A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(sorted, 'b');
    await tester.tap(find.byTooltip('Reverse'));
    expect(reversed, 1);
    await tester.tap(find.text('Filters (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'X'));
    expect(toggled, 'g/x');
    expect(find.text('Clear'), findsOneWidget);
  });

  testWidgets('tag picker creates a tag and shows the error it is given', (
    tester,
  ) async {
    final created = <String>[];
    await tester.pumpWidget(
      _host(
        harnessMatrix().first,
        ArrTagPicker(
          tags: const [ArrTagOption(1, 'kids')],
          selected: const {1},
          labels: const ArrTagPickerLabels(
            heading: 'Tags',
            none: 'None',
            newTag: 'New',
            addTag: 'Create',
          ),
          onToggle: (_) {},
          onCreate: (l) async {
            created.add(l);
            return 'bad name';
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'x');
    await tester.tap(find.byTooltip('Create'));
    await tester.pumpAndSettle();
    expect(created, ['x']);
    expect(find.text('bad name'), findsOneWidget);
  });
}
