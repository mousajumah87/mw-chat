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
  String get createNewAccount => 'إنشاء حساب جديد';

  @override
  String get alreadyHaveAccount => 'لديك حساب بالفعل؟';

  @override
  String get email => 'البريد الإلكتروني';

  @override
  String get password => 'كلمة المرور';

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
  String get preferNotToSay => 'أفضل عدم الإفصاح';

  @override
  String get choosePicture => 'اختر صورة';

  @override
  String get choosePictureTooltip => 'اضغط لاختيار صورة';

  @override
  String get login => 'تسجيل الدخول';

  @override
  String get register => 'إنشاء حساب';

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
  String get notLoggedIn => 'غير مسجل الدخول';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get logoutTooltip => 'تسجيل الخروج';

  @override
  String get goBack => 'الرجوع';

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
  String get usersTitle => 'الأصدقاء';

  @override
  String get mwUsersTabTitle => 'أصدقاء MW';

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
  String get typeMessageHint => 'اكتب رسالة...';

  @override
  String isTyping(Object name) {
    return '$name يكتب...';
  }

  @override
  String get noMessagesYet => 'لا توجد رسائل بعد';

  @override
  String get sendFailed => 'فشل إرسال الرسالة. يرجى المحاولة مرة أخرى.';

  @override
  String get attachFile => 'إرفاق ملف';

  @override
  String get attachment => 'مرفق';

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
  String get failedToUploadFile => 'فشل رفع الملف';

  @override
  String get uploadFailedStorage => 'فشل الرفع (التخزين).';

  @override
  String get uploadFailedMessageSave => 'فشل الرفع (حفظ الرسالة).';

  @override
  String get deleteMessageTitle => 'حذف الرسالة';

  @override
  String get deleteMessageConfirm => 'هل أنت متأكد أنك تريد حذف هذه الرسالة؟';

  @override
  String get deleteFailed => 'فشل حذف الرسالة. يرجى المحاولة مرة أخرى.';

  @override
  String get deleteChatTitle => 'حذف المحادثة';

  @override
  String get deleteChatWarning => 'هل أنت متأكد أنك تريد حذف هذه المحادثة؟ لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get delete => 'حذف';

  @override
  String get cancel => 'إلغاء';

  @override
  String get chatDeleted => 'تم حذف المحادثة بنجاح';

  @override
  String get chatHistoryDeleteFailed => 'فشل حذف سجل المحادثة';

  @override
  String get deleteChatDescription => 'هل أنت متأكد أنك تريد حذف سجل هذه المحادثة؟ لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get chatHistoryDeleted => 'تم حذف سجل المحادثة بنجاح';

  @override
  String get invite => 'دعوة';

  @override
  String get inviteFriendsTitle => 'دعوة الأصدقاء';

  @override
  String get inviteContactsTabTitle => 'دعوة جهات الاتصال';

  @override
  String get inviteFromContactsFuture => 'دعوة الأصدقاء مباشرةً من جهات الاتصال ستكون متاحة في تحديث قادم من تطبيق MW Chat.';

  @override
  String get inviteShareManual => 'حالياً، يمكنك مشاركة تطبيق MW Chat مع أصدقائك من خلال إرسال رابط التطبيق لهم يدوياً.';

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
  String inviteSent(Object name) {
    return 'تم إرسال الدعوة إلى $name';
  }

  @override
  String get inviteWebNotSupported => 'دعوة جهات الاتصال من دفتر العناوين غير مدعومة على نسخة الويب. يرجى استخدام تطبيق الهاتف بدلاً من ذلك.';

  @override
  String get search => 'بحث';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get unknownEmail => 'غير معروف';

  @override
  String get addFriendTooltip => 'إضافة صديق';

  @override
  String get friendRequestedChip => 'بانتظار الموافقة';

  @override
  String get friendAcceptTooltip => 'قبول';

  @override
  String get friendDeclineTooltip => 'رفض';

  @override
  String get friendSectionRequests => 'طلبات الصداقة';

  @override
  String get friendSectionYourFriends => 'أصدقاؤك';

  @override
  String get friendSectionAllUsers => 'جميع مستخدمي MW';

  @override
  String get friendSectionInactiveUsers => 'المستخدمون غير النشطين';

  @override
  String get friendRequestSent => 'تم إرسال طلب الصداقة';

  @override
  String get friendRequestSendFailed => 'فشل في إرسال طلب الصداقة';

  @override
  String get friendRequestAccepted => 'تم قبول طلب الصداقة';

  @override
  String get friendRequestAcceptFailed => 'فشل في قبول طلب الصداقة';

  @override
  String get friendRequestDeclined => 'تم رفض طلب الصداقة';

  @override
  String get friendRequestDeclineFailed => 'فشل في رفض طلب الصداقة';

  @override
  String get friendshipInfoOutgoing => 'تم إرسال طلب الصداقة. يرجى الانتظار لحين الموافقة.';

  @override
  String get friendshipInfoIncoming => 'لديك طلب صداقة معلق. قم بقبوله لبدء الدردشة.';

  @override
  String get friendshipInfoNotFriends => 'يجب أن تكون صديقًا لهذا المستخدم لتتمكن من إرسال الرسائل.';

  @override
  String get friendshipFileInfoOutgoing => 'تم إرسال طلب الصداقة. يمكنك إرسال الملفات بعد قبول الطلب.';

  @override
  String get friendshipFileInfoIncoming => 'لديك طلب صداقة معلق. قم بقبوله لمشاركة الملفات.';

  @override
  String get friendshipFileInfoNotFriends => 'أرسل طلب صداقة لبدء مشاركة الملفات.';

  @override
  String friendshipBannerNotFriends(Object name) {
    return 'أنت لست صديقًا لـ $name بعد. أرسل طلب صداقة لبدء الدردشة.';
  }

  @override
  String get friendshipBannerSendRequestButton => 'إرسال طلب';

  @override
  String friendshipBannerIncoming(Object name) {
    return '$name أرسل لك طلب صداقة.';
  }

  @override
  String friendshipBannerOutgoing(Object name) {
    return 'تم إرسال طلب الصداقة. بانتظار موافقة $name.';
  }

  @override
  String get friendshipCannotSendOutgoing => 'تم إرسال طلب الصداقة. ستتمكن من الدردشة بعد قبول الطلب.';

  @override
  String get friendshipCannotSendIncoming => 'قم بقبول طلب الصداقة أعلاه لبدء الدردشة.';

  @override
  String get friendshipCannotSendNotFriends => 'أرسل طلب صداقة أعلاه لبدء الدردشة.';

  @override
  String get blockUserTitle => 'حظر المستخدم';

  @override
  String get blockUserDescription => 'سيؤدي حظر هذا المستخدم إلى منعه من التواصل معك، ولن تتلقى رسائل جديدة منه.';

  @override
  String get userBlocked => 'تم حظر المستخدم.';

  @override
  String get userBlockedInfo => 'لقد قمت بحظر هذا المستخدم. لا يمكنك إرسال أو استقبال رسائل جديدة معه.';

  @override
  String get blockedUserBanner => 'لقد قمت بحظر هذا المستخدم. لن تصلك رسائل منه بعد الآن.';

  @override
  String get blockedByUserBanner => 'قام هذا المستخدم بحظرك. لا يمكنك إرسال رسائل في هذه المحادثة.';

  @override
  String get unblockUserTitle => 'إلغاء حظر المستخدم';

  @override
  String get unblockUserDescription => 'هل تريد إلغاء حظر هذا المستخدم؟ ستبدأ برؤية الرسائل الجديدة منه مرة أخرى.';

  @override
  String get unblockUserConfirm => 'إلغاء الحظر';

  @override
  String get userUnblocked => 'تم إلغاء حظر المستخدم';

  @override
  String get removeFriendTitle => 'إزالة الصديق';

  @override
  String get removeFriendDescription => 'سيتم إزالة هذا الشخص من قائمة أصدقائك. ما زال بإمكانك الدردشة معه إذا سمحت إعدادات الخصوصية بذلك.';

  @override
  String get removeFriendConfirm => 'إزالة';

  @override
  String get friendRemoved => 'تمت إزالة الصديق';

  @override
  String get reportMessageTitle => 'الإبلاغ عن رسالة';

  @override
  String get reportMessageHint => 'صف سبب الإبلاغ عن هذه الرسالة (تحرش، إزعاج، محتوى غير لائق، إلخ...)';

  @override
  String get reportUserTitle => 'الإبلاغ عن مستخدم';

  @override
  String get reportUserHint => 'صف المشكلة (تحرش، إزعاج، محتوى غير لائق، إلخ...)';

  @override
  String get reportUserReasonLabel => 'السبب';

  @override
  String get reportSubmitted => 'شكراً لك. تم إرسال بلاغك لمراجعته.';

  @override
  String get messageContainsRestrictedContent => 'رسالتك تحتوي على كلمات غير مسموح بها في MW Chat.';

  @override
  String get contentBlockedTitle => 'لم يتم إرسال الرسالة';

  @override
  String get contentBlockedBody => 'تحتوي رسالتك على كلمات غير مسموح بها في تطبيق MW Chat. يرجى تعديلها والمحاولة مرة أخرى.';

  @override
  String get dangerZone => 'إجراءات حساسة';

  @override
  String get optional => 'اختياري';

  @override
  String get reasonHarassment => 'التحرش أو التنمر';

  @override
  String get reasonSpam => 'الرسائل المزعجة أو الاحتيال';

  @override
  String get reasonHate => 'الكراهية أو المحتوى المسيء';

  @override
  String get reasonSexual => 'محتوى جنسي أو غير لائق';

  @override
  String get reasonOther => 'أخرى';

  @override
  String get deletingAccount => 'جاري حذف الحساب...';

  @override
  String get deleteMyAccount => 'حذف حسابي';

  @override
  String get deleteAccountWarning => 'سيؤدي هذا إلى حذف حسابك ورسائلك وبياناتك بشكل دائم. لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get deleteAccountDescription => 'سيؤدي حذف حسابك إلى إزالة ملفك الشخصي ورسائلك وبياناتك المرتبطة بشكل دائم.';

  @override
  String get loginAgainToDelete => 'يرجى تسجيل الدخول مرة أخرى ثم إعادة محاولة حذف الحساب';

  @override
  String get deleteAccountFailed => 'فشل حذف الحساب.';

  @override
  String get deleteAccountFailedRetry => 'فشل حذف الحساب. يرجى المحاولة مرة أخرى.';

  @override
  String get accountDeletedSuccessfully => 'تم حذف الحساب بنجاح';

  @override
  String get termsTitle => 'شروط الاستخدام';

  @override
  String get termsAcceptButton => 'أوافق';

  @override
  String get termsBody => 'مرحباً بك في MW Chat!\n\nباستخدامك لهذا التطبيق، فإنك توافق على شروط الاستخدام التالية:\n\n1. عدم التسامح مع المحتوى غير اللائق\n• يُمنع إرسال أو مشاركة أي محتوى يتسم بالكراهية أو التحرش أو التهديد أو الإيحاءات الجنسية أو العنف أو التمييز أو أي محتوى ضار.\n• يُمنع التنمر أو الإساءة أو الترهيب لأي مستخدم آخر.\n• يُمنع انتحال شخصية الآخرين أو استخدام MW Chat للاحتيال أو أي نشاط غير قانوني.\n\n2. المحتوى الذي ينشئه المستخدمون\n• أنت تتحمل المسؤولية الكاملة عن الرسائل والمحتوى الذي ترسله.\n• يحق لتطبيق MW Chat إزالة أي محتوى يخالف هذه الشروط.\n• يحق لتطبيق MW Chat تعليق أو حظر أي مستخدم ينتهك هذه القواعد بشكل مؤقت أو دائم.\n\n3. الإبلاغ والحظر\n• يوفر MW Chat أدوات للإبلاغ عن المستخدمين وحظرهم في حال إساءة الاستخدام.\n• تتم مراجعة البلاغات بسرعة، ونعمل على اتخاذ الإجراءات المناسبة خلال 24 ساعة، بما في ذلك إزالة المحتوى المسيء و/أو تعطيل حساب المستخدم المخالف عند الحاجة.\n\n4. الخصوصية والسلامة\n• يُنصح بعدم مشاركة معلومات شخصية حساسة (مثل كلمات المرور أو المعلومات المالية أو الوثائق الرسمية) داخل المحادثات.\n• لمزيد من التفاصيل حول كيفية تعاملنا مع بياناتك، يُرجى مراجعة سياسة الخصوصية.\n\n5. إنهاء الاستخدام\n• في حال مخالفة شروط الاستخدام، قد يقوم MW Chat بتقييد أو إنهاء وصولك إلى الخدمة دون إشعار مسبق.\n\nإذا واجهت سلوكاً مسيئاً أو محتوى غير لائق، أو كانت لديك أسئلة حول هذه الشروط، يمكنك التواصل معنا عبر البريد الإلكتروني: support@mwchats.com.\n\nبالنقر على \"أوافق\"، فإنك تؤكد أنك قرأت هذه الشروط وفهمتها وتوافق عليها.';

  @override
  String get byRegisteringYouAgree => 'من خلال إنشاء حساب، فإنك توافق على شروط الاستخدام الخاصة بتطبيق MW Chat.';

  @override
  String get viewTermsLink => 'عرض شروط الاستخدام';

  @override
  String get iAgreeTo => 'أوافق على شروط استخدام MW Chat';

  @override
  String get viewTermsOfUse => 'عرض شروط الاستخدام';

  @override
  String get termsOfUse => 'شروط الاستخدام';

  @override
  String get iAgree => 'أوافق';

  @override
  String get mustAcceptTerms => 'يجب عليك الموافقة على شروط الاستخدام قبل إنشاء الحساب.';

  @override
  String get contactSupport => 'الاتصال بالدعم';

  @override
  String get contactSupportSubtitle => 'support@mwchats.com';

  @override
  String get about => 'حول';

  @override
  String get website => 'الموقع الإلكتروني';

  @override
  String get aboutTitle => 'حول MW Chat';

  @override
  String get aboutDescription => '‏MW Chat هو تطبيق مراسلة حديث للرسائل الخاصة، مُصمَّم لتواصل آمن وسلس.\n\nيمكنك الدردشة مع الأصدقاء، وإرسال الصور والفيديوهات والرسائل الصوتية من خلال واجهة بسيطة وسهلة الاستخدام. يركّز MW Chat على الخصوصية والسرعة والبساطة.\n\nالمميزات:\n• رسائل فورية في الوقت الحقيقي\n• مشاركة الوسائط (صور وفيديوهات)\n• تسجيل دخول آمن\n• تصميم بسيط وأنيق\n• تطبيق سريع وخفيف\n\nسواء للمحادثات الشخصية أو العائلية، يبقيك MW Chat على تواصل آمن وممتع.';

  @override
  String get legalTitle => 'الجانب القانوني';

  @override
  String get copyrightText => 'MW Chat – تطبيق مراسلة حديث للرسائل الخاصة.\nحقوق النشر © 2025 موسى أبو هلال. جميع الحقوق محفوظة.';

  @override
  String get allRightsReserved => 'جميع الحقوق محفوظة.';

  @override
  String get cancelFriendRequestTitle => 'إلغاء طلب الصداقة';

  @override
  String get cancelFriendRequestDescription => 'هل تريد إلغاء طلب الصداقة هذا؟';

  @override
  String get cancelFriendRequestConfirm => 'إلغاء الطلب';

  @override
  String get friendRequestCancelled => 'تم إلغاء طلب الصداقة';

  @override
  String get friendRequestIncomingBanner => 'قام هذا المستخدم بإرسال طلب صداقة إليك.';

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
  String get appBrandingBeta => 'MW شات • نسخة تجريبية';
}
