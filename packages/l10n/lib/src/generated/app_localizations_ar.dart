// SPDX-License-Identifier: GPL-3.0-or-later

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get aboutTitle => 'حول';

  @override
  String get aboutLicense =>
      'كونسولار برنامج حر، مرخّص بموجب GPL-3.0-or-later.';

  @override
  String get aboutIndependence =>
      'كونسولار مشروع مستقل وليس تابعًا لـ Sonarr أو Radarr أو مشروع Servarr أو أي تطبيق آخر.';

  @override
  String get homeTitle => 'الرئيسية';

  @override
  String get homeEmptyHeading => 'لا شيء هنا بعد';

  @override
  String get homeEmptyBody =>
      'أضف خادم وسائط أو عميل تنزيل للبدء. هذه الشاشة مؤقتة.';

  @override
  String homeServerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count خادم',
      many: '$count خادمًا',
      few: '$count خوادم',
      two: 'خادمان',
      one: 'خادم واحد',
      zero: 'لا توجد خوادم',
    );
    return '$_temp0';
  }

  @override
  String get homeAboutTooltip => 'حول كونسولار';

  @override
  String get appTitle => 'كونسولار';
}
