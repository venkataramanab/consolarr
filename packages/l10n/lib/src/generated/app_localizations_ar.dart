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
}
