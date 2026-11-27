// SPDX-License-Identifier: GPL-3.0-or-later

/// The Consolarr app as a library, shared by the foss and Play entry points.
library;

export 'features/settings/application/settings_providers.dart'
    show settingsStoreProvider;
export 'features/settings/data/settings_store.dart' show InMemorySettingsStore;
export 'src/app.dart';
export 'src/first_frame.dart';
export 'src/providers.dart';
export 'src/router.dart';
