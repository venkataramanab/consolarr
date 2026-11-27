// SPDX-License-Identifier: GPL-3.0-or-later

// Self-test for the licence detector: dart run tools/ci/check_licenses_selftest.dart

import 'dart:io';

import 'check_licenses.dart';

const _cases = <String, String>{
  'GNU AFFERO GENERAL PUBLIC LICENSE Version 3, 19 November 2007 ... '
          'the GNU General Public License is a free, copyleft license ...':
      'AGPL-3.0',
  'GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007 ...': 'GPL-3.0',
  'GNU GENERAL PUBLIC LICENSE Version 2, June 1991 ...': 'GPL-2.0',
  'GNU LESSER GENERAL PUBLIC LICENSE Version 3, 29 June 2007 This version of '
          'the GNU Lesser General Public License incorporates the terms of the '
          'GNU General Public License version 3':
      'LGPL-3.0',
  'GNU LESSER GENERAL PUBLIC LICENSE Version 2.1, February 1999': 'LGPL-2.1',
  'Apache License Version 2.0, January 2004': 'Apache-2.0',
  'Permission is hereby granted, free of charge, to any person ...': 'MIT',
  'Mozilla Public License Version 2.0 ...': 'MPL-2.0',
  'Redistribution and use in source and binary forms, with or without '
          'modification, are permitted. Neither the name of the copyright holder '
          'nor the names of its contributors may be used to endorse':
      'BSD-3-Clause',
};

void main() {
  var failed = false;
  _cases.forEach((text, expected) {
    final got = detect(text);
    if (got != expected) {
      stderr.writeln('detect(...) = $got, expected $expected for: $text');
      failed = true;
    }
  });
  const agpl = 'GNU AFFERO GENERAL PUBLIC LICENSE Version 3 ...';
  if (detect(agpl) == 'GPL-3.0') {
    stderr.writeln('AGPL must not be classified as GPL');
    failed = true;
  }
  if (failed) exit(1);
  stdout.writeln('licence detector self-test passed');
}
