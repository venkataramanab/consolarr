// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:observability/src/events/catalog.dart';

/// Rough count: `0 / 1 / 2 / 3-5 / 6+`. Exact counts of servers or items can
/// identify a setup, so events and the issue summary carry a bucket.
CountBucketParam countBucket(int count) => switch (count) {
  <= 0 => CountBucketParam.zero,
  1 => CountBucketParam.one,
  2 => CountBucketParam.two,
  <= 5 => CountBucketParam.threeToFive,
  _ => CountBucketParam.sixPlus,
};

/// The bucket as shown in text: `0`, `1`, `2`, `3-5` or `6+`.
String countBucketLabel(int count) => switch (countBucket(count)) {
  CountBucketParam.zero => '0',
  CountBucketParam.one => '1',
  CountBucketParam.two => '2',
  CountBucketParam.threeToFive => '3-5',
  CountBucketParam.sixPlus => '6+',
};

/// The closed major-version value for [version]; `null` when unknown or not
/// positive (the parameter is then omitted).
MajorVersionParam? majorVersionParam(int? version) {
  if (version == null || version < 1) return null;
  return switch (version) {
    1 => MajorVersionParam.v1,
    2 => MajorVersionParam.v2,
    3 => MajorVersionParam.v3,
    4 => MajorVersionParam.v4,
    5 => MajorVersionParam.v5,
    6 => MajorVersionParam.v6,
    _ => MajorVersionParam.v7OrLater,
  };
}
