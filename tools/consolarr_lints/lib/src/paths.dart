// SPDX-License-Identifier: GPL-3.0-or-later

String _normalize(String path) => path.replaceAll(r'\', '/');

/// Whether [path] is inside an `integration_test/` directory.
bool isIntegrationTestPath(String path) =>
    _normalize(path).contains('/integration_test/');

/// Whether [filePath] is exactly [relativePath] inside the workspace package
/// whose root folder is [packageRoot] and which lives in
/// `packages/[packageName]`.
///
/// The comparison is on the package-relative path, never `endsWith` on the
/// absolute path, so a look-alike directory such as
/// `apps/x/packages/security/lib/...` cannot claim the exemption.
bool isFileInPackage({
  required String filePath,
  required String? packageRoot,
  required String packageName,
  required String relativePath,
}) {
  if (packageRoot == null) return false;
  var root = _normalize(packageRoot);
  while (root.endsWith('/')) {
    root = root.substring(0, root.length - 1);
  }
  final segments = root.split('/');
  if (segments.length < 2 ||
      segments.last != packageName ||
      segments[segments.length - 2] != 'packages') {
    return false;
  }
  return _normalize(filePath) == '$root/$relativePath';
}
