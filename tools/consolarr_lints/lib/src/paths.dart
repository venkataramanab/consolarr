// SPDX-License-Identifier: GPL-3.0-or-later

String _normalize(String path) => path.replaceAll(r'\', '/');

/// Whether [path] is inside an `integration_test/` directory.
bool isIntegrationTestPath(String path) =>
    _normalize(path).contains('/integration_test/');

/// Whether [path] ends with the repo-relative [suffix].
bool pathEndsWith(String path, String suffix) =>
    _normalize(path).endsWith('/$suffix') || _normalize(path) == suffix;
