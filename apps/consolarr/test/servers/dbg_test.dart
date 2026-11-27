import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security/security.dart';
void main() {
  test('x', () async {
    final db = AppDatabase.memory();
    final c = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db), secretStoreProvider.overrideWithValue(InMemorySecretStore())]);
    final repo = c.read(serverRepositoryProvider);
    print('repo ok');
    print(await repo.watchAll().first);
    print('stream ok');
    c.listen(serversProvider, (a, b) { print('got $b'); });
    await Future<void>.delayed(const Duration(seconds: 1));
    print(c.read(serversProvider));
  });
}
