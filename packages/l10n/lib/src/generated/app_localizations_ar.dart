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
  String get connErrorAuthFailedMessage => 'رفض الخادم بيانات الاعتماد.';

  @override
  String get connErrorAuthFailedHint =>
      'تحقّق من مفتاح API أو من اسم المستخدم وكلمة المرور ثم أعد الاختبار.';

  @override
  String get connErrorNeedsCredentialsMessage =>
      'بيانات اعتماد هذا الخادم المحفوظة مفقودة.';

  @override
  String get connErrorNeedsCredentialsHint =>
      'قد يحدث هذا بعد استعادة الجهاز أو تغيير قفل الشاشة. أدخل بيانات الاعتماد مرة أخرى.';

  @override
  String get connErrorTimeoutMessage => 'لم يستجب الخادم في الوقت المناسب.';

  @override
  String get connErrorTimeoutHint =>
      'تأكد من أنه يعمل ويمكن الوصول إليه من هذه الشبكة، أو حاول مرة أخرى.';

  @override
  String get connErrorTlsPinMismatchMessage =>
      'شهادة الخادم تختلف عن الشهادة التي وثقت بها.';

  @override
  String get connErrorTlsPinMismatchHint =>
      'الاتصالات محظورة. لا تثق بالشهادة الجديدة إلا إذا كنت تعلم أن شهادة الخادم قد استُبدلت.';

  @override
  String get connErrorTlsUntrustedMessage =>
      'شهادة الخادم غير موثوقة على هذا الجهاز.';

  @override
  String get connErrorTlsUntrustedHint =>
      'إذا كان هذا خادمك الخاص بشهادة موقّعة ذاتيًا، فراجع بصمتها واختر ما إذا كنت تثق بها.';

  @override
  String get connErrorTlsExpiredMessage =>
      'شهادة الخادم منتهية الصلاحية أو غير صالحة بعد.';

  @override
  String get connErrorTlsExpiredHint =>
      'جدّد الشهادة على الخادم، أو تحقّق من التاريخ على هذا الجهاز.';

  @override
  String get connErrorCleartextRefusedMessage =>
      'يستخدم هذا العنوان http غير مشفّر، وهو غير مسموح لهذا الخادم.';

  @override
  String get connErrorCleartextRefusedHint =>
      'استخدم عنوان https، أو اسمح بـ http غير المشفّر لهذا الخادم من إعدادات الأمان إذا كان على شبكة تثق بها.';

  @override
  String get connErrorUnsupportedVersionMessage =>
      'إصدار هذا الخادم غير مدعوم.';

  @override
  String get connErrorUnsupportedVersionHint =>
      'حدّث الخادم إلى إصدار رئيسي حديث.';

  @override
  String get connErrorNotFoundMessage => 'لم يُعثر على شيء في هذا العنوان.';

  @override
  String get connErrorNotFoundHint =>
      'تحقّق من العنوان والمنفذ وبادئة المسار. يحتاج الوكيل العكسي غالبًا إلى بادئة مثل /sonarr.';

  @override
  String get connErrorServerErrorMessage => 'أبلغ الخادم عن خطأ.';

  @override
  String get connErrorServerErrorHint =>
      'حاول مرة أخرى بعد قليل. إذا استمر ذلك، فراجع سجلات الخادم.';

  @override
  String get connErrorNetworkUnreachableMessage => 'تعذّر الوصول إلى الخادم.';

  @override
  String get connErrorNetworkUnreachableHint =>
      'تحقّق من العنوان والمنفذ ومن أن الخادم يعمل وأن هذا الجهاز على الشبكة الصحيحة.';

  @override
  String get connErrorParseErrorMessage => 'تعذّر فهم ردّ الخادم.';

  @override
  String get connErrorParseErrorHint =>
      'تحقّق من أن العنوان يشير إلى الخدمة الصحيحة وليس إلى صفحة تسجيل دخول أو وكيل.';

  @override
  String get connErrorRedirectRefusedMessage =>
      'أعاد الخادم توجيه الطلب إلى وجهة غير مسموح بها.';

  @override
  String get connErrorRedirectRefusedHint =>
      'استخدم العنوان النهائي للخادم مباشرة، واستخدم https إذا كان يعيد التوجيه من https إلى http.';

  @override
  String get connErrorResponseTooLargeMessage => 'كان ردّ الخادم كبيرًا جدًا.';

  @override
  String get connErrorResponseTooLargeHint =>
      'تحقّق من أن العنوان يشير إلى الخدمة الصحيحة.';

  @override
  String get connErrorInvalidInputMessage => 'العنوان أو المسار غير صالح.';

  @override
  String get connErrorInvalidInputHint =>
      'أدخل عنوانًا مثل https://host:port دون اسم مستخدم أو كلمة مرور أو مفتاح، ومسارًا يبدأ بشرطة مائلة.';

  @override
  String get appTitle => 'كونسولار';

  @override
  String get sonarrTitle => 'المسلسلات';

  @override
  String get sonarrSwitchToListTooltip => 'العرض كقائمة';

  @override
  String get sonarrSwitchToGridTooltip => 'العرض كشبكة';

  @override
  String get sonarrLoadingLabel => 'جارٍ تحميل المسلسلات';

  @override
  String get sonarrRetry => 'حاول مرة أخرى';

  @override
  String get sonarrEmptyHeadline => 'لا توجد مسلسلات بعد';

  @override
  String get sonarrEmptyMessage => 'ستظهر هنا المسلسلات التي تضيفها في Sonarr.';

  @override
  String get sonarrEmptyAction => 'تحديث';

  @override
  String get sonarrNoServerHeadline => 'لا يوجد خادم Sonarr';

  @override
  String get sonarrNoServerMessage => 'أضف خادم Sonarr لتصفح مسلسلاتك.';

  @override
  String get sonarrNoServerAction => 'إضافة خادم';

  @override
  String get sonarrOpenServers => 'فحص إعدادات الخادم';

  @override
  String get sonarrErrorTitle => 'تعذّر تحميل مسلسلاتك';

  @override
  String get sonarrErrorAuthTitle => 'رفض Sonarr تسجيل الدخول';

  @override
  String get sonarrErrorVersionTitle => 'إصدار Sonarr غير مدعوم';

  @override
  String get sonarrErrorAuthMessage => 'لم يتم قبول مفتاح API أو كلمة المرور.';

  @override
  String get sonarrErrorAuthHint =>
      'تحقق من بيانات الاعتماد في إعدادات الخادم.';

  @override
  String get sonarrErrorNeedsCredentialsMessage =>
      'بيانات الاعتماد المحفوظة لهذا الخادم مفقودة.';

  @override
  String get sonarrErrorNeedsCredentialsHint =>
      'أدخل مفتاح API أو كلمة المرور مرة أخرى في إعدادات الخادم.';

  @override
  String get sonarrErrorNetworkMessage => 'تعذّر الوصول إلى Sonarr.';

  @override
  String get sonarrErrorNetworkHint =>
      'تأكد من أنك على الشبكة الصحيحة وأن العنوان والمنفذ صحيحان.';

  @override
  String get sonarrErrorTimeoutMessage => 'استغرق Sonarr وقتًا طويلًا للرد.';

  @override
  String get sonarrErrorTimeoutHint =>
      'حاول مرة أخرى بعد قليل، أو تأكد من أن الخادم يعمل وغير مثقل.';

  @override
  String get sonarrErrorVersionMessage =>
      'إصدار Sonarr هذا قديم جدًا بالنسبة إلى Consolarr.';

  @override
  String get sonarrErrorVersionHint => 'حدّث Sonarr إلى الإصدار 3 أو أحدث.';

  @override
  String get sonarrErrorServerMessage => 'أبلغ Sonarr عن مشكلة داخلية.';

  @override
  String get sonarrErrorServerHint => 'افحص سجلات Sonarr ثم حاول مرة أخرى.';

  @override
  String get sonarrErrorParseMessage =>
      'أرسل Sonarr ردًا لم يتمكن التطبيق من قراءته.';

  @override
  String get sonarrErrorParseHint =>
      'تأكد من أن العنوان يشير إلى Sonarr وليس إلى خدمة أخرى.';

  @override
  String get sonarrErrorNotFoundMessage => 'لم يرد أي شيء على هذا العنوان.';

  @override
  String get sonarrErrorNotFoundHint =>
      'تحقق من العنوان وبادئة المسار، مثل /sonarr خلف وكيل عكسي.';

  @override
  String get sonarrErrorTlsMessage => 'شهادة الخادم غير موثوقة.';

  @override
  String get sonarrErrorTlsHint =>
      'راجع الشهادة في إعدادات الخادم قبل الوثوق بها.';

  @override
  String get sonarrErrorCleartextMessage =>
      'يستخدم هذا الخادم http غير المشفّر وهو غير مسموح.';

  @override
  String get sonarrErrorCleartextHint =>
      'استخدم https، أو اسمح بـ http غير المشفّر لهذا الخادم في إعداداته.';

  @override
  String get sonarrErrorGenericMessage => 'حدث خطأ أثناء التواصل مع Sonarr.';

  @override
  String get sonarrErrorGenericHint =>
      'حاول مرة أخرى، وافحص إعدادات الخادم إذا استمرت المشكلة.';

  @override
  String get sonarrOfflineMessage => 'غير متصل. يتم عرض المسلسلات المحفوظة.';

  @override
  String sonarrUpdatedAgo(String age) {
    return 'حُدّث $age';
  }

  @override
  String get sonarrAgeJustNow => 'الآن';

  @override
  String sonarrAgeMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'قبل $count دقيقة',
      few: 'قبل $count دقائق',
      two: 'قبل دقيقتين',
      one: 'قبل دقيقة',
    );
    return '$_temp0';
  }

  @override
  String sonarrAgeHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'قبل $count ساعة',
      few: 'قبل $count ساعات',
      two: 'قبل ساعتين',
      one: 'قبل ساعة',
    );
    return '$_temp0';
  }

  @override
  String sonarrAgeDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'قبل $count يومًا',
      few: 'قبل $count أيام',
      two: 'قبل يومين',
      one: 'قبل يوم',
    );
    return '$_temp0';
  }

  @override
  String get sonarrStatusContinuing => 'مستمر';

  @override
  String get sonarrStatusEnded => 'انتهى';

  @override
  String get sonarrStatusUpcoming => 'قريبًا';

  @override
  String get sonarrStatusDeleted => 'محذوف';

  @override
  String get sonarrMonitored => 'مراقَب';

  @override
  String get sonarrUnmonitored => 'غير مراقَب';

  @override
  String sonarrEpisodesShort(int have, int total) {
    return '$have/$total';
  }

  @override
  String sonarrEpisodesProgress(int have, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$have/$total حلقة',
      few: '$have/$total حلقات',
      two: '$have/2 حلقتان',
      one: '$have/1 حلقة',
    );
    return '$_temp0';
  }

  @override
  String sonarrSeasonCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count موسمًا',
      few: '$count مواسم',
      two: 'موسمان',
      one: 'موسم واحد',
    );
    return '$_temp0';
  }

  @override
  String sonarrSizeMb(String size) {
    return '$size ميغابايت';
  }

  @override
  String sonarrSizeGb(String size) {
    return '$size غيغابايت';
  }

  @override
  String sonarrSizeTb(String size) {
    return '$size تيرابايت';
  }

  @override
  String get sonarrNextAiringToday => 'يُعرض اليوم';

  @override
  String get sonarrNextAiringTomorrow => 'يُعرض غدًا';

  @override
  String sonarrNextAiringInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'يُعرض بعد $days يومًا',
      few: 'يُعرض بعد $days أيام',
      two: 'يُعرض بعد يومين',
      one: 'يُعرض بعد يوم',
    );
    return '$_temp0';
  }

  @override
  String sonarrSeriesSemantics(String title, String details) {
    return '$title، $details';
  }

  @override
  String get torrentsTitle => 'التورنتات';

  @override
  String torCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تورنت',
      many: '$count تورنتًا',
      few: '$count تورنتات',
      two: 'تورنتان',
      one: 'تورنت واحد',
      zero: 'لا توجد تورنتات',
    );
    return '$_temp0';
  }

  @override
  String get torSpeedDown => 'التنزيل';

  @override
  String get torSpeedUp => 'الرفع';

  @override
  String get torSpeedIdle => 'خامل';

  @override
  String get torSpeedPartial => 'معلومات السرعة غير متاحة حاليًا.';

  @override
  String get torSpeedOffline => 'غير متصل';

  @override
  String torSpeedHeaderSemantics(String down, String up, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تورنت',
      many: '$count تورنتًا',
      few: '$count تورنتات',
      two: 'تورنتان',
      one: 'تورنت واحد',
      zero: 'لا توجد تورنتات',
    );
    return 'التنزيل $down، الرفع $up، $_temp0';
  }

  @override
  String get torStateDownloading => 'جارٍ التنزيل';

  @override
  String get torStateStalled => 'متوقف مؤقتًا';

  @override
  String get torStateChecking => 'جارٍ الفحص';

  @override
  String get torStateQueued => 'في الانتظار';

  @override
  String get torStateSeeding => 'جارٍ البذر';

  @override
  String get torStatePaused => 'متوقف';

  @override
  String get torStateFinished => 'اكتمل';

  @override
  String get torStateError => 'خطأ';

  @override
  String get torStateUnknown => 'غير معروف';

  @override
  String torProgressPercent(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString';
  }

  @override
  String torRowSemantics(String name, String state, String percent) {
    return '$name، $state، اكتمل $percent';
  }

  @override
  String torDetailSize(String size) {
    return '$size';
  }

  @override
  String torDetailDown(String speed) {
    return 'تنزيل $speed';
  }

  @override
  String torDetailUp(String speed) {
    return 'رفع $speed';
  }

  @override
  String torDetailEta(String time) {
    return 'المتبقي $time';
  }

  @override
  String torDetailRatio(double ratio) {
    final intl.NumberFormat ratioNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String ratioString = ratioNumberFormat.format(ratio);

    return 'النسبة $ratioString';
  }

  @override
  String torSpeedPerSecond(String size) {
    return '$size/ث';
  }

  @override
  String torUnitB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString بايت';
  }

  @override
  String torUnitKB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString ك.ب';
  }

  @override
  String torUnitMB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString م.ب';
  }

  @override
  String torUnitGB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString ج.ب';
  }

  @override
  String torUnitTB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString ت.ب';
  }

  @override
  String torDurationSeconds(int count) {
    return '$count ث';
  }

  @override
  String torDurationMinutes(int count) {
    return '$count د';
  }

  @override
  String torDurationHoursMinutes(int hours, int minutes) {
    return '$hours س $minutes د';
  }

  @override
  String torDurationDaysHours(int days, int hours) {
    return '$days ي $hours س';
  }

  @override
  String get torEmptyHeadline => 'لا توجد تورنتات بعد';

  @override
  String get torEmptyMessage => 'ستظهر هنا التورنتات التي تضيفها في العميل.';

  @override
  String get torNoServerHeadline => 'لا يوجد عميل تورنت بعد';

  @override
  String get torNoServerMessage => 'أضف خادم qBittorrent لعرض التورنتات.';

  @override
  String get torNoServerAction => 'إضافة خادم';

  @override
  String get torErrorHeadline => 'تعذّر تحميل التورنتات';

  @override
  String get torRetry => 'حاول مرة أخرى';

  @override
  String get torOfflineMessage =>
      'تعذّر الوصول إلى الخادم. تُعرض آخر البيانات.';

  @override
  String torOfflineAge(String time) {
    return 'آخر تحديث قبل $time';
  }

  @override
  String get torOfflineJustNow => 'تم التحديث الآن';

  @override
  String get torReconnect => 'إعادة الاتصال';

  @override
  String get torSpeedLimitsHint => 'فتح حدود السرعة';
}
