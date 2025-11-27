// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get loginTitle => 'مرحباً بعودتك';

  @override
  String get createAccount => 'إنشاء حساب MW';

  @override
  String get choosePicture => 'اختر صورة';

  @override
  String get choosePictureTooltip => 'اضغط لاختيار صورة';

  @override
  String get firstName => 'الاسم الأول';

  @override
  String get lastName => 'اسم العائلة';

  @override
  String get birthday => 'تاريخ الميلاد';

  @override
  String get selectBirthday => 'اختر تاريخ الميلاد';

  @override
  String get gender => 'الجنس';

  @override
  String get male => 'ذكر';

  @override
  String get female => 'أنثى';

  @override
  String get email => 'البريد الإلكتروني';

  @override
  String get password => 'كلمة المرور';

  @override
  String get login => 'تسجيل الدخول';

  @override
  String get register => 'إنشاء حساب';

  @override
  String get createNewAccount => 'إنشاء حساب جديد';

  @override
  String get alreadyHaveAccount => 'لديك حساب بالفعل؟';

  @override
  String get requiredField => 'حقل مطلوب';

  @override
  String get invalidEmail => 'بريد إلكتروني غير صالح';

  @override
  String get minPassword => 'كلمة المرور لا تقل عن 6 أحرف';

  @override
  String get authError => 'خطأ في المصادقة';

  @override
  String get failedToCreateUser => 'فشل إنشاء المستخدم';

  @override
  String get settingUpProfile => 'جارٍ إعداد ملفك الشخصي...';

  @override
  String get accountNotActive => 'حسابك غير مفعّل بعد.';

  @override
  String get waitForActivation => 'يرجى الانتظار حتى يتم تفعيل حسابك من قبل المسؤول.';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get goBack => 'الرجوع';

  @override
  String get usersTitle => 'الأصدقاء';

  @override
  String get notActivated => 'غير مفعّل';

  @override
  String get online => 'متصل';

  @override
  String get offline => 'غير متصل';

  @override
  String get lastSeenJustNow => 'آخر ظهور الآن';

  @override
  String lastSeenMinutes(Object minutes) {
    return 'آخر ظهور منذ $minutes دقيقة';
  }

  @override
  String lastSeenHours(Object hours) {
    return 'آخر ظهور منذ $hours ساعة';
  }

  @override
  String lastSeenDays(Object days) {
    return 'آخر ظهور منذ $days يوم';
  }

  @override
  String get noOtherUsers => 'لا يوجد أصدقاء آخرون';

  @override
  String get notLoggedIn => 'غير مسجل الدخول';

  @override
  String get userProfileTitle => 'الملف الشخصي للمستخدم';

  @override
  String get userNotFound => 'المستخدم غير موجود';

  @override
  String get ageLabel => 'العمر';

  @override
  String get birthdayLabel => 'تاريخ الميلاد';

  @override
  String get genderLabel => 'الجنس';

  @override
  String get notSpecified => 'غير محدد';

  @override
  String get unknown => 'غير معروف';

  @override
  String get profileTitle => 'الملف الشخصي';

  @override
  String get profileUpdated => 'تم تحديث الملف الشخصي';

  @override
  String get saving => 'جارٍ الحفظ...';

  @override
  String get save => 'حفظ';

  @override
  String saveFailed(Object error) {
    return 'فشل الحفظ: $error';
  }

  @override
  String get failedToUploadFile => 'فشل رفع الملف';

  @override
  String get uploadFailedStorage => 'فشل الرفع (التخزين).';

  @override
  String get uploadFailedMessageSave => 'فشل الرفع (حفظ الرسالة).';

  @override
  String isTyping(Object name) {
    return '$name يكتب...';
  }

  @override
  String get attachFile => 'إرفاق ملف';

  @override
  String get typeMessageHint => 'اكتب رسالة...';

  @override
  String get noMessagesYet => 'لا توجد رسائل بعد';

  @override
  String get photo => '📷 صورة';

  @override
  String photoWithName(Object fileName) {
    return '📷 صورة: $fileName';
  }

  @override
  String get video => '🎬 فيديو';

  @override
  String videoWithName(Object fileName) {
    return '🎬 فيديو: $fileName';
  }

  @override
  String get audio => '🎵 صوت';

  @override
  String audioWithName(Object fileName) {
    return '🎵 صوت: $fileName';
  }

  @override
  String get file => '📎 ملف';

  @override
  String fileWithName(Object fileName) {
    return '📎 ملف: $fileName';
  }

  @override
  String get attachment => 'مرفق';

  @override
  String get invite => 'دعوة';

  @override
  String get inviteFriendsTitle => 'دعوة الأصدقاء';

  @override
  String get contactsPermissionDenied => 'لا يمكننا الوصول إلى جهات الاتصال لديك. يرجى تفعيل إذن جهات الاتصال من الإعدادات لدعوة أصدقائك.';

  @override
  String get noContactsFound => 'لا توجد جهات اتصال تحتوي على أرقام هاتف.';

  @override
  String get inviteSubject => 'انضم إليّ في MW Chat';

  @override
  String inviteMessageTemplate(Object androidLink, Object iosLink, Object name) {
    return 'مرحباً $name، أستخدم تطبيق MW Chat للتواصل. يمكنك تحميله من هنا:\nأندرويد: $androidLink\nآيفون: $iosLink\nأراك هناك!';
  }

  @override
  String get inviteContactsTabTitle => 'دعوة جهات الاتصال';

  @override
  String get inviteWebNotSupported => 'دعوة جهات الاتصال من دفتر العناوين غير مدعومة على نسخة الويب. يرجى استخدام تطبيق الهاتف بدلاً من ذلك.';

  @override
  String get sidePanelAppName => 'MW شات';

  @override
  String get sidePanelTagline => 'ابق قريباً من أحبّ الناس إليك.';

  @override
  String get sidePanelMissingMascotsHint => 'أضِف صورة شخصيات MW إلى المسار assets/images/mw_bear_and_smurf.png';

  @override
  String get sidePanelFeatureTitle => 'لماذا يحبّ الناس MW';

  @override
  String get sidePanelFeaturePrivate => 'محادثات خاصة فردية مع الأشخاص المقرّبين منك.';

  @override
  String get sidePanelFeatureStatus => 'حالة الاتصال وآخر ظهور لتعرف متى يكون الأصدقاء متاحين.';

  @override
  String get sidePanelFeatureInvite => 'ادعُ أصدقاءك من جهات الاتصال بضغطة واحدة.';

  @override
  String get sidePanelTip => 'نصيحة: الأصدقاء المتصلون يظهرون في الأعلى. اضغط على أي صديق لبدء المحادثة فوراً.';

  @override
  String get sidePanelFollowTitle => 'تابِع MW';

  @override
  String get socialFacebook => 'فيسبوك';

  @override
  String get socialInstagram => 'إنستغرام';

  @override
  String get socialX => 'إكس / تويتر';

  @override
  String get mwUsersTabTitle => 'أصدقاء MW';

  @override
  String get search => 'بحث';

  @override
  String get aboutTitle => 'حول MW Chat';

  @override
  String get aboutDescription => '‏MW Chat هو تطبيق مراسلة حديث للرسائل الخاصة، مُصمَّم لتواصل آمن وسلس.\n\nيمكنك الدردشة مع الأصدقاء، وإرسال الصور والفيديوهات والرسائل الصوتية من خلال واجهة بسيطة وسهلة الاستخدام. يركّز MW Chat على الخصوصية والسرعة والبساطة.\n\nالمميزات:\n• رسائل فورية في الوقت الحقيقي\n• مشاركة الوسائط (صور وفيديوهات)\n• تسجيل دخول آمن\n• تصميم بسيط وأنيق\n• تطبيق سريع وخفيف\n\nسواء للمحادثات الشخصية أو العائلية، يبقيك MW Chat على تواصل آمن وممتع.';

  @override
  String get legalTitle => 'الجانب القانوني';

  @override
  String get copyrightText => 'MW Chat – تطبيق مراسلة حديث للرسائل الخاصة.\nحقوق النشر © 2025 موسى أبو هلال. جميع الحقوق محفوظة.';

  @override
  String get appBrandingBeta => 'MW شات • نسخة تجريبية';
}
