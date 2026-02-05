// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get mainTitle => 'MW';

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
  String get forgotPassword => 'نسيت كلمة المرور؟';

  @override
  String get resetPasswordTitle => 'إعادة تعيين كلمة المرور';

  @override
  String get resetEmailSent =>
      'تم إرسال رابط إعادة تعيين كلمة المرور. تحقق من بريدك الإلكتروني.';

  @override
  String get resetEmailIfExists =>
      'إذا كان هذا البريد الإلكتروني موجودًا، فستتلقى رابط إعادة التعيين.';

  @override
  String get tooManyRequests => 'محاولات كثيرة. يرجى المحاولة لاحقًا.';

  @override
  String get settingUpProfile => 'جارٍ إعداد ملفك الشخصي...';

  @override
  String get accountNotActive => 'حسابك غير مفعّل بعد.';

  @override
  String get waitForActivation =>
      'يرجى الانتظار حتى يتم تفعيل حسابك من قبل المسؤول.';

  @override
  String get notLoggedIn => 'غير مسجل الدخول';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get logoutTooltip => 'تسجيل الخروج';

  @override
  String get goBack => 'الرجوع';

  @override
  String get autoUpdateNotice => 'سيتم تحديث هذه الشاشة تلقائيًا عند التفعيل.';

  @override
  String get checkAgain => 'تحقق مرة أخرى';

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
  String get languageLabel => 'اللغة';

  @override
  String get menuTitle => 'القائمة';

  @override
  String get profile => 'الملف الشخصي';

  @override
  String get viewProfile => 'عرض الملف الشخصي';

  @override
  String get viewFriendProfile => 'عرض ملف الصديق';

  @override
  String get viewMyProfile => 'عرض ملفي الشخصي';

  @override
  String get removePhoto => 'إزالة الصورة';

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
  String get attachPhotoFromGallery => 'صورة من المعرض';

  @override
  String get attachVideoFromGallery => 'فيديو من المعرض';

  @override
  String get attachTakePhoto => 'التقاط صورة';

  @override
  String get attachRecordVideo => 'تسجيل فيديو';

  @override
  String get attachFileFromDevice => 'ملف من الجهاز';

  @override
  String get voiceNotSupportedWeb =>
      'الرسائل الصوتية غير مدعومة على الويب بعد.';

  @override
  String get microphonePermissionRequired =>
      'يتطلب تسجيل الصوت منح إذن الوصول إلى الميكروفون.';

  @override
  String get holdMicToRecord =>
      'اضغط باستمرار على الميكروفون لتسجيل رسالة صوتية';

  @override
  String get previewVoiceMessage => 'معاينة الرسالة الصوتية';

  @override
  String get voiceMessageLabel => 'رسالة صوتية';

  @override
  String get genericFileLabel => 'ملف';

  @override
  String get websiteDomain => 'mwchats.com';

  @override
  String get deleteChatForMe => 'حذف المحادثة من عندي فقط';

  @override
  String get deleteChatForBoth => 'حذف المحادثة للطرفين';

  @override
  String get deletingChatInProgressTitle => 'جارٍ حذف المحادثة...';

  @override
  String deletingChatProgress(int current, int total) {
    return '$current / $total رسالة';
  }

  @override
  String get deleteMessageTitle => 'حذف الرسالة';

  @override
  String get deleteMessageConfirm => 'هل أنت متأكد أنك تريد حذف هذه الرسالة؟';

  @override
  String get deleteFailed => 'فشل حذف الرسالة. يرجى المحاولة مرة أخرى.';

  @override
  String get deleteChatTitle => 'حذف المحادثة';

  @override
  String get deleteChatWarning =>
      'هل أنت متأكد أنك تريد حذف هذه المحادثة؟ لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get deleteChatDescription =>
      'هل أنت متأكد أنك تريد حذف سجل هذه المحادثة؟ لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get delete => 'حذف';

  @override
  String get cancel => 'إلغاء';

  @override
  String get chatDeleted => 'تم حذف المحادثة بنجاح';

  @override
  String get chatHistoryDeleteFailed => 'فشل حذف سجل المحادثة';

  @override
  String get chatHistoryDeleted => 'تم حذف سجل المحادثة بنجاح';

  @override
  String get remove => 'حذف';

  @override
  String get invite => 'دعوة';

  @override
  String get inviteFriendsTitle => 'دعوة الأصدقاء';

  @override
  String get inviteContactsTabTitle => 'دعوة جهات الاتصال';

  @override
  String get inviteFromContactsFuture =>
      'ادعُ أصدقاءك إلى MW Chat وابقَ على تواصل معهم.';

  @override
  String get inviteShareManual =>
      'يمكنك تنزيل تطبيق MW Chat من خلال الروابط التالية:';

  @override
  String get contactsPermissionDenied =>
      'لا يمكننا الوصول إلى جهات الاتصال لديك. يرجى تفعيل إذن جهات الاتصال من الإعدادات لدعوة أصدقائك.';

  @override
  String get noContactsFound => 'لا توجد جهات اتصال تحتوي على أرقام هاتف.';

  @override
  String get inviteSubject => 'انضم إليّ في MW Chat';

  @override
  String inviteMessageTemplate(
    Object androidLink,
    Object iosLink,
    Object name,
  ) {
    return 'مرحباً $name، أستخدم تطبيق MW Chat للتواصل. يمكنك تحميله من هنا:\nأندرويد: $androidLink\nآيفون: $iosLink\nأراك هناك!';
  }

  @override
  String inviteSent(Object name) {
    return 'تم إرسال الدعوة إلى $name';
  }

  @override
  String get inviteWebNotSupported =>
      'دعوة جهات الاتصال من دفتر العناوين غير مدعومة على نسخة الويب. يرجى استخدام تطبيق الهاتف بدلاً من ذلك.';

  @override
  String get invitePlatformAndroid => 'أندرويد';

  @override
  String get invitePlatformIos => 'آيفون';

  @override
  String get invitePlatformWeb => 'الموقع الإلكتروني';

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
  String get friendRequestAlreadyIncoming =>
      'هذا المستخدم أرسل لك طلب صداقة بالفعل. تحقّق من طلبات الصداقة.';

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
  String get friendRequestCancelled => 'تم إلغاء طلب الصداقة';

  @override
  String get friendRequestIncomingBanner =>
      'قام هذا المستخدم بإرسال طلب صداقة إليك.';

  @override
  String get friendshipInfoOutgoing =>
      'تم إرسال طلب الصداقة. يرجى الانتظار لحين الموافقة.';

  @override
  String get friendshipInfoIncoming =>
      'لديك طلب صداقة معلق. قم بقبوله لبدء الدردشة.';

  @override
  String get friendshipInfoNotFriends =>
      'يجب أن تكون صديقًا لهذا المستخدم لتتمكن من إرسال الرسائل.';

  @override
  String get friendshipFileInfoOutgoing =>
      'تم إرسال طلب الصداقة. يمكنك إرسال الملفات بعد قبول الطلب.';

  @override
  String get friendshipFileInfoIncoming =>
      'لديك طلب صداقة معلق. قم بقبوله لمشاركة الملفات.';

  @override
  String get friendshipFileInfoNotFriends =>
      'أرسل طلب صداقة لبدء مشاركة الملفات.';

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
  String get friendshipCannotSendOutgoing =>
      'تم إرسال طلب الصداقة. ستتمكن من الدردشة بعد قبول الطلب.';

  @override
  String get friendshipCannotSendIncoming =>
      'قم بقبول طلب الصداقة أعلاه لبدء الدردشة.';

  @override
  String get friendshipCannotSendNotFriends =>
      'أرسل طلب صداقة أعلاه لبدء الدردشة.';

  @override
  String get blockUserTitle => 'حظر المستخدم';

  @override
  String get blockUserDescription =>
      'سيؤدي حظر هذا المستخدم إلى منعه من التواصل معك، ولن تتلقى رسائل جديدة منه.';

  @override
  String get userBlocked => 'تم حظر المستخدم.';

  @override
  String get userBlockedInfo =>
      'لقد قمت بحظر هذا المستخدم. لا يمكنك إرسال أو استقبال رسائل جديدة معه.';

  @override
  String get blockedUserBanner =>
      'لقد قمت بحظر هذا المستخدم. لن تصلك رسائل منه بعد الآن.';

  @override
  String get blockedByUserBanner =>
      'قام هذا المستخدم بحظرك. لا يمكنك إرسال رسائل في هذه المحادثة.';

  @override
  String get unblockUserTitle => 'إلغاء حظر المستخدم';

  @override
  String get unblockUserDescription =>
      'هل تريد إلغاء حظر هذا المستخدم؟ ستبدأ برؤية الرسائل الجديدة منه مرة أخرى.';

  @override
  String get unblockUserConfirm => 'إلغاء الحظر';

  @override
  String get userUnblocked => 'تم إلغاء حظر المستخدم';

  @override
  String get removeFriendTitle => 'إزالة الصديق';

  @override
  String get removeFriendDescription =>
      'سيتم إزالة هذا الشخص من قائمة أصدقائك. ما زال بإمكانك الدردشة معه إذا سمحت إعدادات الخصوصية بذلك.';

  @override
  String get removeFriendConfirm => 'إزالة';

  @override
  String get friendRemoved => 'تمت إزالة الصديق';

  @override
  String get reportMessageTitle => 'الإبلاغ عن رسالة';

  @override
  String get reportMessageHint =>
      'صف سبب الإبلاغ عن هذه الرسالة (تحرش، إزعاج، محتوى غير لائق، إلخ...)';

  @override
  String get reportUserTitle => 'الإبلاغ عن مستخدم';

  @override
  String get reportUserHint =>
      'صف المشكلة (تحرش، إزعاج، محتوى غير لائق، إلخ...)';

  @override
  String get reportUserReasonLabel => 'السبب';

  @override
  String get reportSubmitted => 'شكراً لك. تم إرسال بلاغك لمراجعته.';

  @override
  String get messageContainsRestrictedContent =>
      'رسالتك تحتوي على كلمات غير مسموح بها في MW Chat.';

  @override
  String get contentBlockedTitle => 'لم يتم إرسال الرسالة';

  @override
  String get contentBlockedBody =>
      'تحتوي رسالتك على كلمات غير مسموح بها في تطبيق MW Chat. يرجى تعديلها والمحاولة مرة أخرى.';

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
  String get deleteMessageSuccess => 'تم حذف الرسالة';

  @override
  String get deleteMessageFailed => 'فشل حذف الرسالة';

  @override
  String get deletedForMe => 'تم الحذف لدي';

  @override
  String get deletedAccount => 'حساب محذوف';

  @override
  String get messageDeletedSuccess => 'تم حذف الرسالة بنجاح';

  @override
  String get thisMessageWasDeleted => 'تم حذف هذه الرسالة';

  @override
  String get deletingAccount => 'جاري حذف الحساب...';

  @override
  String get deleteMyAccount => 'حذف حسابي';

  @override
  String get deleteAccountWarning =>
      'سيؤدي هذا إلى حذف حسابك ورسائلك وبياناتك بشكل دائم. لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get deleteAccountDescription =>
      'سيؤدي حذف حسابك إلى إزالة ملفك الشخصي ورسائلك وبياناتك المرتبطة بشكل دائم.';

  @override
  String get loginAgainToDelete =>
      'يرجى تسجيل الدخول مرة أخرى ثم إعادة محاولة حذف الحساب';

  @override
  String get deleteAccountFailed => 'فشل حذف الحساب.';

  @override
  String get deleteAccountFailedRetry =>
      'فشل حذف الحساب. يرجى المحاولة مرة أخرى.';

  @override
  String get accountDeletedSuccessfully => 'تم حذف الحساب بنجاح';

  @override
  String get termsTitle => 'شروط الاستخدام';

  @override
  String get termsAcceptButton => 'أوافق';

  @override
  String get termsBody =>
      'مرحباً بك في MW Chat!\n\nباستخدامك لهذا التطبيق، فإنك توافق على شروط الاستخدام التالية:\n\n1. عدم التسامح مع المحتوى غير اللائق\n• يُمنع إرسال أو مشاركة أي محتوى يتسم بالكراهية أو التحرش أو التهديد أو الإيحاءات الجنسية أو العنف أو التمييز أو أي محتوى ضار.\n• يُمنع التنمر أو الإساءة أو الترهيب لأي مستخدم آخر.\n• يُمنع انتحال شخصية الآخرين أو استخدام MW Chat للاحتيال أو أي نشاط غير قانوني.\n\n2. المحتوى الذي ينشئه المستخدمون\n• أنت تتحمل المسؤولية الكاملة عن الرسائل والمحتوى الذي ترسله.\n• يحق لتطبيق MW Chat إزالة أي محتوى يخالف هذه الشروط.\n• يحق لتطبيق MW Chat تعليق أو حظر أي مستخدم ينتهك هذه القواعد بشكل مؤقت أو دائم.\n\n3. الإبلاغ والحظر\n• يوفر MW Chat أدوات للإبلاغ عن المستخدمين وحظرهم في حال إساءة الاستخدام.\n• تتم مراجعة البلاغات بسرعة، ونعمل على اتخاذ الإجراءات المناسبة خلال 24 ساعة، بما في ذلك إزالة المحتوى المسيء و/أو تعطيل حساب المستخدم المخالف عند الحاجة.\n\n4. الخصوصية والسلامة\n• يُنصح بعدم مشاركة معلومات شخصية حساسة (مثل كلمات المرور أو المعلومات المالية أو الوثائق الرسمية) داخل المحادثات.\n• لمزيد من التفاصيل حول كيفية تعاملنا مع بياناتك، يُرجى مراجعة سياسة الخصوصية.\n\n5. إنهاء الاستخدام\n• في حال مخالفة شروط الاستخدام، قد يقوم MW Chat بتقييد أو إنهاء وصولك إلى الخدمة دون إشعار مسبق.\n\nإذا واجهت سلوكاً مسيئاً أو محتوى غير لائق، أو كانت لديك أسئلة حول هذه الشروط، يمكنك التواصل معنا عبر البريد الإلكتروني: support@mwchats.com.\n\nبالنقر على \"أوافق\"، فإنك تؤكد أنك قرأت هذه الشروط وفهمتها وتوافق عليها.';

  @override
  String get byRegisteringYouAgree =>
      'من خلال إنشاء حساب، فإنك توافق على شروط الاستخدام الخاصة بتطبيق MW Chat.';

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
  String get mustAcceptTerms =>
      'يجب عليك الموافقة على شروط الاستخدام قبل إنشاء الحساب.';

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
  String get aboutDescription =>
      '‏MW Chat هو تطبيق مراسلة حديث للرسائل الخاصة، مُصمَّم لتواصل آمن وسلس.\n\nيمكنك الدردشة مع الأصدقاء، وإرسال الصور والفيديوهات والرسائل الصوتية من خلال واجهة بسيطة وسهلة الاستخدام. يركّز MW Chat على الخصوصية والسرعة والبساطة.\n\nالمميزات:\n• رسائل فورية في الوقت الحقيقي\n• مشاركة الوسائط (صور وفيديوهات)\n• تسجيل دخول آمن\n• تصميم بسيط وأنيق\n• تطبيق سريع وخفيف\n\nسواء للمحادثات الشخصية أو العائلية، يبقيك MW Chat على تواصل آمن وممتع.';

  @override
  String get legalTitle => 'الجانب القانوني';

  @override
  String get copyrightText =>
      'MW Chat – تطبيق مراسلة حديث للرسائل الخاصة.\nحقوق النشر © 2025 موسى أبو هلال. جميع الحقوق محفوظة.';

  @override
  String get allRightsReserved => 'جميع الحقوق محفوظة.';

  @override
  String get sidePanelAppName => 'MW Chat';

  @override
  String get sidePanelTagline => 'ابقَ قريبًا من الأشخاص المفضلين لديك.';

  @override
  String get sidePanelMissingMascotsHint =>
      'أضِف صورة شخصيات MW إلى المسار assets/images/mw_bear_and_smurf.png';

  @override
  String get sidePanelFeatureTitle => 'لماذا يحبّ الناس MW';

  @override
  String get sidePanelFeaturePrivate =>
      'محادثات خاصة فردية مع الأشخاص المقرّبين منك.';

  @override
  String get sidePanelFeatureStatus =>
      'حالة الاتصال وآخر ظهور لتعرف متى يكون الأصدقاء متاحين.';

  @override
  String get sidePanelFeatureInvite =>
      'ادعُ أصدقاءك من جهات الاتصال بضغطة واحدة.';

  @override
  String get sidePanelTip =>
      'نصيحة: الأصدقاء المتصلون يظهرون في الأعلى. اضغط على أي صديق لبدء المحادثة فوراً.';

  @override
  String get sidePanelFollowTitle => 'تابِع MW';

  @override
  String get socialFacebook => 'فيسبوك';

  @override
  String get socialInstagram => 'إنستغرام';

  @override
  String get socialX => 'إكس / تويتر';

  @override
  String get loadMore => 'عرض المزيد';

  @override
  String get tapToPlay => 'اضغط للتشغيل';

  @override
  String get videoLabel => 'فيديو';

  @override
  String get recordingLabel => 'جارٍ التسجيل';

  @override
  String get cancelLabel => 'إلغاء';

  @override
  String get stopLabel => 'إيقاف';

  @override
  String get sendLabel => 'إرسال';

  @override
  String get cancelFriendRequestTitle => 'إلغاء طلب الصداقة';

  @override
  String get send => 'إرسال';

  @override
  String get privacyTitle => 'إعدادات الخصوصية';

  @override
  String get ok => 'موافق';

  @override
  String get cancelFriendRequestConfirm => 'إلغاء الطلب';

  @override
  String get cancelFriendRequestDescription => 'هل تريد إلغاء طلب الصداقة هذا؟';

  @override
  String get appBrandingBeta => 'MW شات 2025';

  @override
  String get profileSafetyToolsSectionTitle => 'أدوات السلامة';

  @override
  String get profileBlockedUserHintLimitedVisibility =>
      'قام هذا المستخدم بتقييد ما يمكنك رؤيته.';

  @override
  String get profileBlockDialogTitleBlock => 'حظر المستخدم';

  @override
  String get profileBlockDialogTitleUnblock => 'إلغاء حظر المستخدم';

  @override
  String get profileBlockDialogBodyBlock =>
      'هل تريد حظر هذا المستخدم؟ لن تتلقى رسائل منه في تطبيق MW Chat بعد الآن.';

  @override
  String get profileBlockDialogBodyUnblock =>
      'هل تريد إلغاء حظر هذا المستخدم؟ ستتمكن من استقبال الرسائل منه مرة أخرى.';

  @override
  String get profileBlockDialogConfirmBlock => 'حظر';

  @override
  String get profileBlockDialogConfirmUnblock => 'إلغاء الحظر';

  @override
  String get profileBlockButtonBlock => 'حظر المستخدم';

  @override
  String get profileBlockButtonUnblock => 'إلغاء حظر المستخدم';

  @override
  String get profileBlockSnackbarBlocked => 'تم حظر المستخدم بنجاح.';

  @override
  String get profileBlockSnackbarUnblocked => 'تم إلغاء حظر المستخدم.';

  @override
  String get profileBlockSnackbarError =>
      'فشل تحديث حالة الحظر. يرجى المحاولة مرة أخرى.';

  @override
  String get profileReportDialogTitle => 'الإبلاغ عن مستخدم';

  @override
  String get profileReportDialogBody =>
      'يرجى وصف سبب الإبلاغ عن هذا المستخدم، مثل: الرسائل المزعجة، التنمر، خطاب الكراهية، أو أي محتوى مسيء آخر.';

  @override
  String get profileReportDialogHint => 'صف المشكلة…';

  @override
  String get profileReportDialogSubmit => 'إرسال البلاغ';

  @override
  String get profileReportButtonLabel => 'الإبلاغ عن المستخدم';

  @override
  String get profileReportSnackbarSuccess => 'تم إرسال البلاغ. سنقوم بمراجعته.';

  @override
  String get profileReportSnackbarError =>
      'فشل إرسال البلاغ. يرجى المحاولة مرة أخرى.';

  @override
  String get generalErrorMessage => 'حدث خطأ ما. يرجى المحاولة مرة أخرى.';

  @override
  String get downloadOnAppStore => 'حمّل من متجر آبل';

  @override
  String get getItOnGooglePlay => 'احصل عليه من متجر Google Play';

  @override
  String get shareAppLink => 'مشاركة رابط التطبيق';

  @override
  String get presencePrivacyTitle => 'إعدادات الخصوصية';

  @override
  String get presencePrivacyNotSignedIn => 'لم يتم تسجيل الدخول';

  @override
  String get presencePrivacySectionSubtitle =>
      'تحكّم في من يمكنه رؤية ملفك الشخصي ونشاطك.';

  @override
  String get presencePrivacySectionOnlineTitle => 'حالة الاتصال';

  @override
  String get presencePrivacyShowWhenOnlineTitle =>
      'إظهار حالتي عندما أكون متصلاً';

  @override
  String get presencePrivacyShowWhenOnlineSubtitleOn =>
      'يمكن للآخرين رؤية أنك متصل.';

  @override
  String get presencePrivacyShowWhenOnlineSubtitleOff =>
      'ستظهر غير متصل للجميع.';

  @override
  String get presencePrivacyStatusHiddenOffline => 'ستظهر غير متصل للجميع.';

  @override
  String get presencePrivacyStatusVisibleOnline => 'يمكن للآخرين رؤيتك كمُتصل.';

  @override
  String get presencePrivacyStatusVisibleOfflineWhenInactive =>
      'سيراك الآخرون غير متصل عندما لا تكون نشطًا.';

  @override
  String get presencePrivacyAutoOfflineTitle => 'إيقاف تلقائي (موصى به)';

  @override
  String presencePrivacyAutoOfflineBody(Object staleWindow) {
    return 'إذا تم إغلاق التطبيق أو حذفه أو انقطع الاتصال، فقد تبقى حالتك \"متصل\" لفترة قصيرة. يقوم MW Chat باعتبار الحساب غير متصل تلقائيًا إذا لم يتم تسجيل نشاط حديث لمدة $staleWindow.';
  }

  @override
  String presencePrivacyStaleMinutes(num minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes دقيقة',
      many: '$minutes دقيقة',
      few: '$minutes دقائق',
      two: 'دقيقتان',
      one: 'دقيقة واحدة',
      zero: 'أقل من دقيقة',
    );
    return '$_temp0';
  }

  @override
  String get presencePrivacyLastSeenUnavailable => 'آخر ظهور: غير متاح';

  @override
  String presencePrivacyLastSeenLine(Object value) {
    return 'آخر ظهور: $value';
  }

  @override
  String get presencePrivacyTip =>
      'نصيحة: إيقاف هذا الخيار يُخفي حالة اتصالك في جميع أنحاء التطبيق.';

  @override
  String get privacySectionTitle => 'الخصوصية';

  @override
  String get onlineStatusTitle => 'الخصوصية والظهور';

  @override
  String get onlineStatusSubtitle =>
      'إدارة من يمكنه رؤية حالتك ونشاطك وملفك الشخصي';

  @override
  String get presencePrivacySectionProfileTitle => 'الملف الشخصي والطلبات';

  @override
  String get presencePrivacySectionProfileSubtitle =>
      'تحكّم بمن يمكنه رؤية ملفك الشخصي ومن يمكنه إضافتك كصديق.';

  @override
  String get presencePrivacyProfileVisTitle => 'من يمكنه رؤية ملفي الشخصي';

  @override
  String get presencePrivacyProfileVisSubtitle =>
      'اختر من يمكنه مشاهدة تفاصيل ملفك الشخصي.';

  @override
  String get presencePrivacyProfileVisSheetHint =>
      'هذا الإعداد يتحكم في ظهور ملفك الشخصي للمستخدمين الآخرين.';

  @override
  String get presencePrivacyProfileVisEveryoneTitle => 'الجميع';

  @override
  String get presencePrivacyProfileVisEveryoneSubtitle =>
      'يمكن لأي شخص رؤية ملفك الشخصي.';

  @override
  String get presencePrivacyProfileVisFriendsTitle => 'الأصدقاء فقط';

  @override
  String get presencePrivacyProfileVisFriendsSubtitle =>
      'يمكن لأصدقائك فقط رؤية ملفك الشخصي.';

  @override
  String get presencePrivacyProfileVisNobodyTitle => 'لا أحد';

  @override
  String get presencePrivacyProfileVisNobodySubtitle =>
      'إخفاء ملفك الشخصي عن المستخدمين الآخرين.';

  @override
  String get presencePrivacyProfileVisValueEveryone => 'الجميع';

  @override
  String get presencePrivacyProfileVisValueFriends => 'الأصدقاء';

  @override
  String get presencePrivacyProfileVisValueNobody => 'لا أحد';

  @override
  String get presencePrivacyFriendReqTitle => 'من يمكنه إضافتي كصديق';

  @override
  String get presencePrivacyFriendReqSubtitle =>
      'تحكّم بمن يُسمح له بإرسال طلبات صداقة إليك.';

  @override
  String get presencePrivacyFriendReqSheetHint =>
      'هذا الإعداد يتحكم في إمكانية إرسال طلبات الصداقة إليك.';

  @override
  String get presencePrivacyFriendReqEveryoneTitle => 'الجميع';

  @override
  String get presencePrivacyFriendReqEveryoneSubtitle =>
      'يمكن لأي شخص إرسال طلب صداقة.';

  @override
  String get presencePrivacyFriendReqNobodyTitle => 'لا أحد';

  @override
  String get presencePrivacyFriendReqNobodySubtitle =>
      'تعطيل طلبات الصداقة من المستخدمين الآخرين.';

  @override
  String get presencePrivacyFriendReqValueEveryone => 'الجميع';

  @override
  String get presencePrivacyFriendReqValueNobody => 'لا أحد';

  @override
  String get friendRequestNotAllowed => 'طلبات الصداقة غير مسموح بها';

  @override
  String get profilePrivateChatRestricted =>
      'هذا الملف الشخصي خاص ولا يمكن بدء الدردشة';

  @override
  String get profilePrivate => 'هذا الملف الشخصي خاص';

  @override
  String get deleteMessageDescription => 'اختر كيفية حذف هذه الرسالة';

  @override
  String get deleteForMe => 'حذف لدي';

  @override
  String get deleteForEveryone => 'حذف لدى الجميع';

  @override
  String get deletingMessageInProgressTitle => 'جارٍ حذف الرسالة';

  @override
  String get pleaseWait => 'يرجى الانتظار';

  @override
  String get messageAlreadyDeleted => 'تم حذف هذه الرسالة مسبقًا';

  @override
  String get deletedForMeSuccess => 'تم حذف الرسالة لديك';

  @override
  String get deletedForEveryoneSuccess => 'تم حذف الرسالة لدى الجميع';

  @override
  String get searchFriendsHint => 'ابحث في الأصدقاء…';

  @override
  String get searchUsersHint => 'ابحث في مستخدمي MW…';

  @override
  String get noFriendsFound => 'لم يتم العثور على أصدقاء.';

  @override
  String get noUsersFound => 'لم يتم العثور على مستخدمين.';

  @override
  String get loading => 'جارٍ التحميل…';

  @override
  String get peopleOnMw => 'أشخاص على MW';

  @override
  String get myFriends => 'أصدقائي';

  @override
  String get searchPeopleHint => 'ابحث عن أشخاص';

  @override
  String get noSearchResults => 'لا توجد نتائج';

  @override
  String get friendRequestsTitle => 'طلبات الصداقة';

  @override
  String get friendRequestsSearchHint => 'ابحث في طلبات الصداقة';

  @override
  String get friendRequestsEmpty => 'لا توجد طلبات صداقة';

  @override
  String friendRequestsSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'لديك $count طلبات صداقة جديدة',
      one: 'لديك طلب صداقة جديد',
      zero: 'لا توجد طلبات صداقة جديدة',
    );
    return '$_temp0';
  }

  @override
  String get unknownUser => 'مستخدم غير معروف';

  @override
  String get accountUnavailableSubtitle => 'هذا الحساب لم يعد متاحًا.';

  @override
  String get invitePlatformTitle => 'الدعوة عبر المنصات';

  @override
  String get tapIconToOpen => 'اضغط على أيقونة للفتح';

  @override
  String get reply => 'رد';

  @override
  String get more => 'المزيد';

  @override
  String get replyingToMessage => 'جارٍ الرد على الرسالة';

  @override
  String get replying => 'الرد على';

  @override
  String get originalMessageNotFound => 'لم يتم العثور على الرسالة الأصلية';

  @override
  String get fontAndDisplay => 'الخط وإعدادات العرض';

  @override
  String get noEmailOnAccount => 'لا يوجد بريد إلكتروني مرتبط بهذا الحساب';

  @override
  String get copied => 'تم النسخ';

  @override
  String get copy => 'نسخ';

  @override
  String get fontAndDisplaySubtitle => 'تخصيص حجم النص ومظهره';

  @override
  String get fontSizeLabel => 'حجم الخط';

  @override
  String get fontSizeDesc =>
      'غيّر حجم النص في تطبيق MW Chat بالكامل (بما في ذلك الرسائل).';

  @override
  String get fontStyleLabel => 'نمط الخط';

  @override
  String get fontStyleDesc => 'اختر نمط خط يناسب ذوقك.';

  @override
  String get previewLabel => 'معاينة';

  @override
  String get previewHeadline => 'MW Chat — هكذا ستبدو الرسائل.';

  @override
  String get previewBody =>
      'يمكنك إبقاء الخط صغيرًا أو تكبيره ليصبح مريحًا للعين.';

  @override
  String get resetToDefault => 'إعادة الإعدادات الافتراضية';

  @override
  String get backToDefault => 'تمت العودة إلى الإعدادات الافتراضية.';

  @override
  String get previewMiniLine =>
      'هكذا سيبدو نص الدردشة أثناء الاستخدام الحقيقي.';

  @override
  String get fontHintNote =>
      'معلومة: تغييرات الخط تُطبّق فورًا في جميع أنحاء التطبيق.';

  @override
  String get account => 'الحساب';

  @override
  String get preferences => 'التفضيلات';

  @override
  String get sensitiveActions => 'إجراءات حساسة';

  @override
  String get legal => 'القوانين والسياسات';

  @override
  String get webFontNote => 'تنطبق إعدادات الخط على إصدار الويب فقط';

  @override
  String get arabicLabel => 'العربية';

  @override
  String get messageDeletedForMeSuccess => 'تم حذف الرسالة لديك';

  @override
  String get messageDeletedForEveryoneSuccess => 'تم حذف الرسالة لدى الجميع';

  @override
  String get messageSelectedTitle => 'تم تحديد الرسالة';

  @override
  String get copyNotAvailable => 'النسخ غير متاح';

  @override
  String get deleteMessageDescriptionEveryone => 'اختر كيفية حذف هذه الرسالة.';

  @override
  String get deleteMessageDescriptionMe => 'سيتم حذف هذه الرسالة لديك فقط.';

  @override
  String get report => 'الإبلاغ';

  @override
  String get selectedOne => 'محددة';

  @override
  String get selectedMany => 'تم تحديد عدة عناصر';

  @override
  String get chooseArabicFont => 'يرجى اختيار خط عربي.';

  @override
  String get chooseEnglishFont => 'يرجى اختيار خط إنجليزي.';

  @override
  String get typographyTip =>
      'نصيحة: الخطوط العصرية تناسب الشباب، والخطوط النظيفة أفضل للدردشة الطويلة، وخطوط الحب جميلة للعناوين والبروفايل.';

  @override
  String get typographyWebTip =>
      'نصيحة للويب: إذا لم يتغير الخط، جرّب إعادة التشغيل السريع (R) لإعادة تحميل الخط.';

  @override
  String get englishSample =>
      'مثال إنجليزي: The quick brown fox jumps over the lazy dog.';

  @override
  String get arabicSample =>
      'مثال عربي: اللغة العربية جميلة وتبدو رائعة مع الخط المناسب.';

  @override
  String get newLabel => 'جديد';

  @override
  String get callLogs_title => 'سجل المكالمات';

  @override
  String get callLogs_notSignedIn => 'لم يتم تسجيل الدخول';

  @override
  String get callLogs_filter_all => 'الكل';

  @override
  String get callLogs_filter_missed => 'فائتة';

  @override
  String get callLogs_filter_incoming => 'واردة';

  @override
  String get callLogs_filter_outgoing => 'صادرة';

  @override
  String get callLogs_tooltip_retry => 'إعادة المحاولة';

  @override
  String get callLogs_tooltip_markMissedRead => 'وضع المكالمات الفائتة كمقروءة';

  @override
  String get callLogs_tooltip_clearLogs => 'مسح السجل';

  @override
  String get callLogs_snack_markedMissedRead =>
      'تم وضع المكالمات الفائتة كمقروءة';

  @override
  String get callLogs_snack_markedAsRead => 'تم وضعها كمقروءة';

  @override
  String callLogs_snack_failedWithError(Object error) {
    return 'فشل: $error';
  }

  @override
  String callLogs_snack_clearedWithCount(Object count, Object filter) {
    return 'تم مسح $count من سجل مكالمات $filter';
  }

  @override
  String callLogs_snack_clearFailedWithError(Object error) {
    return 'فشل المسح: $error';
  }

  @override
  String callLogs_confirm_clearTitle(Object filter) {
    return 'مسح سجل مكالمات $filter؟';
  }

  @override
  String get callLogs_confirm_clearAllBody =>
      'سيؤدي هذا إلى حذف جميع سجلات المكالمات من تاريخك.';

  @override
  String callLogs_confirm_clearFilterBody(Object filter) {
    return 'سيؤدي هذا إلى حذف سجلات مكالمات $filter فقط من تاريخك.';
  }

  @override
  String callLogs_chip_errorPermission(String title) {
    return '$title (لا توجد صلاحية)';
  }

  @override
  String get common_cancel => 'إلغاء';

  @override
  String get common_clear => 'مسح';

  @override
  String get common_retry => 'إعادة المحاولة';

  @override
  String get callLogs_error_indexRequired => 'مطلوب فهرس في Firestore';

  @override
  String get callLogs_error_failedToLoad => 'تعذر تحميل سجل المكالمات';

  @override
  String get callLogs_error_createIndexHint =>
      'أنشئ الفهرس المركّب الموضح في رابط خطأ Firestore.';

  @override
  String get callLogs_loading => 'جارٍ التحميل...';

  @override
  String get callLogs_empty_all => 'لا يوجد سجل مكالمات بعد';

  @override
  String get callLogs_empty_missed => 'لا توجد مكالمات فائتة';

  @override
  String get callLogs_empty_incoming => 'لا توجد مكالمات واردة';

  @override
  String get callLogs_empty_outgoing => 'لا توجد مكالمات صادرة';

  @override
  String get callLogs_unknownUser => 'غير معروف';

  @override
  String get callLogs_result_ended => 'انتهت';

  @override
  String get callLogs_result_declined => 'مرفوضة';

  @override
  String get callLogs_result_canceled => 'أُلغيت';

  @override
  String get callLogs_result_missed => 'فائتة';

  @override
  String get callLogs_result_busy => 'مشغول';

  @override
  String get callLogs_direction_incoming => 'واردة';

  @override
  String get callLogs_direction_outgoing => 'صادرة';

  @override
  String callLogs_chip_indexNeeded(String title) {
    return '$title (مطلوب فهرس)';
  }

  @override
  String callLogs_chip_error(String title) {
    return '$title (خطأ)';
  }

  @override
  String callLogs_chip_missedCount(
    String title,
    String missedLabel,
    int count,
  ) {
    return '$title • $missedLabel ($count)';
  }

  @override
  String get debug_insertedCallLog => 'تصحيح: تم إدراج سجل مكالمة';

  @override
  String get callLogs_tooltip_voiceCall => 'مكالمة صوتية';

  @override
  String get callLogs_tooltip_videoCall => 'مكالمة فيديو';

  @override
  String get outgoingCall_failedToStart => 'فشل بدء المكالمة';

  @override
  String get outgoingCall_calling => 'جارٍ الاتصال…';

  @override
  String get outgoingCall_connecting => 'جارٍ الاتصال…';

  @override
  String get outgoingCall_pleaseWait => 'يرجى الانتظار…';

  @override
  String get outgoingCall_notSignedIn => 'لم يتم تسجيل الدخول';

  @override
  String get outgoingCall_invalidPeer => 'جهة الاتصال غير صالحة';

  @override
  String get call_status_ringing => 'جارٍ الرنين…';

  @override
  String get call_status_inCall => 'في مكالمة';

  @override
  String get call_status_answering => 'جارٍ الرد…';

  @override
  String get call_status_declined => 'تم الرفض';

  @override
  String get call_status_missed => 'مكالمة فائتة';

  @override
  String get call_status_canceled => 'تم الإلغاء';

  @override
  String get call_status_busy => 'المستخدم مشغول';

  @override
  String get call_status_ended => 'انتهت المكالمة';

  @override
  String get call_status_canceling => 'جارٍ الإلغاء…';

  @override
  String call_failedWithError(Object error) {
    return 'فشلت المكالمة: $error';
  }

  @override
  String get incomingCall_voice => 'مكالمة صوتية واردة';

  @override
  String get incomingCall_video => 'مكالمة فيديو واردة';

  @override
  String get incomingCall_accept => 'قبول';

  @override
  String get incomingCall_decline => 'رفض';

  @override
  String get incomingCall_unknownCaller => 'متصل غير معروف';
}
