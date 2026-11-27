// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/release_row.dart';
import 'package:consolarr/features/sonarr/application/release_search.dart';
import 'package:consolarr/features/sonarr/presentation/formatters.dart';
import 'package:l10n/l10n.dart';

/// Localized labels for the release rows.
ReleaseRowLabels releaseRowLabels(AppLocalizations l10n) => ReleaseRowLabels(
  download: l10n.sonarrReleaseDownload,
  downloadAgain: l10n.sonarrReleaseDownloadAgain,
  grabbing: l10n.sonarrReleaseGrabbing,
  grabbed: l10n.sonarrReleaseGrabbed,
  failed: l10n.sonarrReleaseFailed,
  maybeSent: l10n.sonarrReleaseMaybeSent,
  rejectedBadge: l10n.sonarrReleaseRejected,
  expand: l10n.sonarrReleaseExpand,
  collapse: l10n.sonarrReleaseCollapse,
  rejectionsHeading: l10n.sonarrReleaseRejectionsHeading,
  customFormatsHeading: l10n.sonarrReleaseCustomFormatsHeading,
  languagesHeading: l10n.sonarrReleaseLanguagesHeading,
);

/// "5 minutes ago" style age of a release.
String releaseAgeText(AppLocalizations l10n, int minutes) {
  if (minutes < 60) return l10n.sonarrReleaseAgeMinutes(minutes);
  if (minutes < 60 * 24) return l10n.sonarrReleaseAgeHours(minutes ~/ 60);
  return l10n.sonarrReleaseAgeDays(minutes ~/ (60 * 24));
}

String? protocolText(AppLocalizations l10n, ArrProtocol protocol) =>
    switch (protocol) {
      ArrProtocol.torrent => l10n.sonarrReleaseProtocolTorrent,
      ArrProtocol.usenet => l10n.sonarrReleaseProtocolUsenet,
      ArrProtocol.unknown => null,
    };

ReleaseGrabState grabStateOf(GrabStatus? status) => switch (status) {
  null => ReleaseGrabState.idle,
  GrabStatus.grabbing => ReleaseGrabState.grabbing,
  GrabStatus.grabbed => ReleaseGrabState.grabbed,
  GrabStatus.failed => ReleaseGrabState.failed,
  GrabStatus.maybeSent => ReleaseGrabState.maybeSent,
};

/// The view-model of one release row.
ReleaseRowData releaseRowData(
  AppLocalizations l10n,
  ArrRelease r,
  GrabStatus? status,
) {
  final grab = grabStateOf(status);
  final facts = [
    ?r.qualityName,
    if (r.size > 0) sizeText(l10n, r.size),
    releaseAgeText(l10n, r.ageMinutes),
    if (r.protocol == ArrProtocol.torrent && r.seeders != null)
      l10n.sonarrReleaseSeeders(r.seeders!),
    ?r.indexer,
    ?protocolText(l10n, r.protocol),
  ];
  final stateText = switch (grab) {
    ReleaseGrabState.idle => null,
    ReleaseGrabState.grabbing => l10n.sonarrReleaseGrabbing,
    ReleaseGrabState.grabbed => l10n.sonarrReleaseGrabbed,
    ReleaseGrabState.failed => l10n.sonarrReleaseFailed,
    ReleaseGrabState.maybeSent => l10n.sonarrReleaseMaybeSent,
  };
  final details = [
    ...facts,
    if (r.isRejected) l10n.sonarrReleaseRejected,
    ?stateText,
  ].join(', ');
  return ReleaseRowData(
    title: r.title,
    facts: facts,
    semanticsLabel: l10n.sonarrReleaseSemantics(r.title, details),
    isRejected: r.isRejected,
    rejections: r.rejections,
    customFormats: r.customFormats,
    languages: r.languages,
    grab: grab,
  );
}
