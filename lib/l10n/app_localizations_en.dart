// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get mainTitle => 'MW';

  @override
  String get loginTitle => 'Welcome back';

  @override
  String get createAccount => 'Create your MW account';

  @override
  String get createNewAccount => 'Create new account';

  @override
  String get alreadyHaveAccount => 'Already have an account?';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get firstName => 'First name';

  @override
  String get lastName => 'Last name';

  @override
  String get birthday => 'Birthday';

  @override
  String get selectBirthday => 'Select your birthday';

  @override
  String get gender => 'Gender';

  @override
  String get male => 'Male';

  @override
  String get female => 'Female';

  @override
  String get preferNotToSay => 'Prefer not to say';

  @override
  String get choosePicture => 'Choose picture';

  @override
  String get choosePictureTooltip => 'Tap to choose a picture';

  @override
  String get login => 'Login';

  @override
  String get register => 'Register';

  @override
  String get requiredField => 'This field is required';

  @override
  String get invalidEmail => 'Invalid email';

  @override
  String get minPassword => 'Minimum 6 characters';

  @override
  String get authError => 'Something went wrong. Please try again.';

  @override
  String get failedToCreateUser => 'Failed to create user';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get resetPasswordTitle => 'Reset password';

  @override
  String get resetEmailSent => 'Password reset email sent. Check your inbox.';

  @override
  String get resetEmailIfExists =>
      'If this email exists, you will receive a reset link.';

  @override
  String get tooManyRequests => 'Too many attempts. Please try again later.';

  @override
  String get changePassword => 'Change password';

  @override
  String get changePasswordSubtitle => 'Update your password securely.';

  @override
  String get sendResetEmail => 'Send reset email';

  @override
  String get sendResetEmailSubtitle =>
      'Forgot it? We will email you a reset link.';

  @override
  String get changePasswordDialogTitle => 'Change password';

  @override
  String get currentPassword => 'Current password';

  @override
  String get newPassword => 'New password';

  @override
  String get confirmNewPassword => 'Confirm new password';

  @override
  String get updatePassword => 'Update';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get passwordUpdatedSuccess => 'Password updated successfully.';

  @override
  String get notSignedIn => 'You are not signed in.';

  @override
  String get noPasswordProvider =>
      'This account doesn’t use a password. Use reset email instead.';

  @override
  String get noEmailFound => 'No email found for this account.';

  @override
  String get currentPasswordIncorrect => 'Current password is incorrect.';

  @override
  String get weakPassword => 'New password is too weak.';

  @override
  String get requiresRecentLogin => 'Please re-login and try again.';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get passwordMinLength => 'Use at least 8 characters';

  @override
  String get passwordMustDiffer =>
      'New password must be different from current';

  @override
  String get genericError => 'Something went wrong. Please try again.';

  @override
  String get resetPasswordHelperText =>
      'We’ll send a reset link to your email.';

  @override
  String get settingUpProfile => 'Setting up your profile...';

  @override
  String get accountNotActive => 'Your account is not active yet.';

  @override
  String get waitForActivation =>
      'Please wait until your account is activated by the admin.';

  @override
  String get notLoggedIn => 'Not logged in';

  @override
  String get logout => 'Logout';

  @override
  String get logoutTooltip => 'Logout';

  @override
  String get goBack => 'Go back';

  @override
  String get autoUpdateNotice =>
      'This screen will update automatically once activated.';

  @override
  String get checkAgain => 'Check again';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileUpdated => 'Profile updated';

  @override
  String get saving => 'Saving...';

  @override
  String get save => 'Save';

  @override
  String saveFailed(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get userProfileTitle => 'User profile';

  @override
  String get userNotFound => 'User not found';

  @override
  String get ageLabel => 'Age';

  @override
  String get birthdayLabel => 'Birthday';

  @override
  String get genderLabel => 'Gender';

  @override
  String get notSpecified => 'Not specified';

  @override
  String get unknown => 'Unknown';

  @override
  String get languageLabel => 'Language';

  @override
  String get menuTitle => 'Menu';

  @override
  String get profile => 'Profile';

  @override
  String get viewProfile => 'View Profile';

  @override
  String get viewFriendProfile => 'View Friend Profile';

  @override
  String get viewMyProfile => 'View My Profile';

  @override
  String get removePhoto => 'Remove photo';

  @override
  String get usersTitle => 'Friends';

  @override
  String get mwUsersTabTitle => 'MW Friends';

  @override
  String get notActivated => 'Not activated';

  @override
  String get online => 'Online';

  @override
  String get offline => 'Offline';

  @override
  String get lastSeenJustNow => 'Last seen just now';

  @override
  String lastSeenMinutes(Object minutes) {
    return 'Last seen $minutes min ago';
  }

  @override
  String lastSeenHours(Object hours) {
    return 'Last seen $hours h ago';
  }

  @override
  String lastSeenDays(Object days) {
    return 'Last seen $days d ago';
  }

  @override
  String get noOtherUsers => 'No other friends yet';

  @override
  String get typeMessageHint => 'Type a message...';

  @override
  String isTyping(Object name) {
    return '$name is typing...';
  }

  @override
  String get noMessagesYet => 'No messages yet';

  @override
  String get sendFailed => 'Failed to send message. Please try again.';

  @override
  String get attachFile => 'Attach file';

  @override
  String get attachment => 'Attachment';

  @override
  String get photo => '📷 Photo';

  @override
  String photoWithName(Object fileName) {
    return '📷 Photo: $fileName';
  }

  @override
  String get video => '🎬 Video';

  @override
  String videoWithName(Object fileName) {
    return '🎬 Video: $fileName';
  }

  @override
  String get audio => '🎵 Audio';

  @override
  String audioWithName(Object fileName) {
    return '🎵 Audio: $fileName';
  }

  @override
  String get file => '📎 File';

  @override
  String fileWithName(Object fileName) {
    return '📎 File: $fileName';
  }

  @override
  String get failedToUploadFile => 'Failed to upload file';

  @override
  String get uploadFailedStorage => 'Upload failed (storage).';

  @override
  String get uploadFailedMessageSave => 'Upload failed (message save).';

  @override
  String get attachPhotoFromGallery => 'Photo from gallery';

  @override
  String get attachVideoFromGallery => 'Video from gallery';

  @override
  String get attachTakePhoto => 'Take a photo';

  @override
  String get attachRecordVideo => 'Record a video';

  @override
  String get attachFileFromDevice => 'File from device';

  @override
  String get voiceNotSupportedWeb =>
      'Voice messages are not supported on Web yet.';

  @override
  String get microphonePermissionRequired =>
      'Microphone permission is required to record audio.';

  @override
  String get holdMicToRecord => 'Hold the mic to record a voice message';

  @override
  String get previewVoiceMessage => 'Preview voice message';

  @override
  String get voiceMessageLabel => 'Voice message';

  @override
  String get genericFileLabel => 'File';

  @override
  String get websiteDomain => 'mwchats.com';

  @override
  String get deleteChatForMe => 'Delete for me';

  @override
  String get deleteChatForBoth => 'Delete for both';

  @override
  String get deletingChatInProgressTitle => 'Deleting chat...';

  @override
  String deletingChatProgress(int current, int total) {
    return '$current / $total messages';
  }

  @override
  String get deleteMessageTitle => 'Delete message';

  @override
  String get deleteMessageConfirm =>
      'Are you sure you want to delete this message?';

  @override
  String get deleteFailed => 'Failed to delete the message. Please try again.';

  @override
  String get deleteChatTitle => 'Delete chat';

  @override
  String get deleteChatWarning =>
      'Are you sure you want to delete this chat? This action cannot be undone.';

  @override
  String get deleteChatDescription =>
      'Are you sure you want to delete this chat history? This action cannot be undone.';

  @override
  String get delete => 'Delete';

  @override
  String get chatDeleted => 'Chat deleted successfully';

  @override
  String get chatHistoryDeleteFailed => 'Failed to delete chat history';

  @override
  String get chatHistoryDeleted => 'Chat history deleted successfully';

  @override
  String get remove => 'Remove';

  @override
  String get invite => 'Invite';

  @override
  String get inviteFriendsTitle => 'Invite Friends';

  @override
  String get inviteContactsTabTitle => 'Invite Contacts';

  @override
  String get inviteFromContactsFuture =>
      'Invite your friends to MW Chat and stay connected.';

  @override
  String get inviteShareManual =>
      'You can download MW Chat using the links below:';

  @override
  String get contactsPermissionDenied =>
      'We can’t access your contacts. Please enable contacts permission in Settings.';

  @override
  String get noContactsFound => 'No contacts with phone numbers were found.';

  @override
  String get inviteSubject => 'Join me on MW Chat';

  @override
  String inviteMessageTemplate(
    Object androidLink,
    Object iosLink,
    Object name,
  ) {
    return 'Hi $name, I’m using MW Chat to stay in touch. Download it here:\nAndroid: $androidLink\niOS: $iosLink\nSee you there!';
  }

  @override
  String inviteSent(Object name) {
    return 'Invite sent to $name';
  }

  @override
  String get inviteWebNotSupported =>
      'Inviting contacts is not supported on web.';

  @override
  String get invitePlatformAndroid => 'Android';

  @override
  String get invitePlatformIos => 'iOS';

  @override
  String get invitePlatformWeb => 'Web';

  @override
  String get search => 'Search';

  @override
  String get retry => 'Retry';

  @override
  String get unknownEmail => 'Unknown';

  @override
  String get addFriendTooltip => 'Add friend';

  @override
  String get friendRequestedChip => 'Requested';

  @override
  String get friendAcceptTooltip => 'Accept';

  @override
  String get friendDeclineTooltip => 'Decline';

  @override
  String get friendSectionRequests => 'Friend requests';

  @override
  String get friendSectionYourFriends => 'Your friends';

  @override
  String get friendSectionAllUsers => 'All MW users';

  @override
  String get friendSectionInactiveUsers => 'Inactive users';

  @override
  String get friendRequestAlreadyIncoming =>
      'This user already sent you a friend request. Check your requests.';

  @override
  String get friendRequestSent => 'Friend request sent';

  @override
  String get friendRequestSendFailed => 'Failed to send friend request';

  @override
  String get friendRequestAccepted => 'Friend request accepted';

  @override
  String get friendRequestAcceptFailed => 'Failed to accept friend request';

  @override
  String get friendRequestDeclined => 'Friend request declined';

  @override
  String get friendRequestDeclineFailed => 'Failed to decline friend request';

  @override
  String get friendRequestCancelled => 'Friend request cancelled';

  @override
  String get friendRequestIncomingBanner =>
      'This user sent you a friend request.';

  @override
  String get friendshipInfoOutgoing =>
      'Friend request sent. Please wait for approval.';

  @override
  String get friendshipInfoIncoming =>
      'You have a friend request pending. Accept it to start chatting.';

  @override
  String get friendshipInfoNotFriends =>
      'You need to be friends to send messages.';

  @override
  String get friendshipFileInfoOutgoing =>
      'Friend request sent. You can send files once it is accepted.';

  @override
  String get friendshipFileInfoIncoming =>
      'You have a friend request pending. Accept it to share files.';

  @override
  String get friendshipFileInfoNotFriends =>
      'Send a friend request to start sharing files.';

  @override
  String friendshipBannerNotFriends(Object name) {
    return 'You’re not friends with $name yet. Send a friend request to start chatting.';
  }

  @override
  String get friendshipBannerSendRequestButton => 'Send request';

  @override
  String friendshipBannerIncoming(Object name) {
    return '$name sent you a friend request.';
  }

  @override
  String friendshipBannerOutgoing(Object name) {
    return 'Friend request sent. Waiting for $name to accept.';
  }

  @override
  String get friendshipCannotSendOutgoing =>
      'Friend request sent. You can start chatting once it is accepted.';

  @override
  String get friendshipCannotSendIncoming =>
      'Accept the friend request above to start chatting.';

  @override
  String get friendshipCannotSendNotFriends =>
      'Send a friend request above to start chatting.';

  @override
  String get blockUserTitle => 'Block user';

  @override
  String get blockUserDescription =>
      'Blocking this user prevents them from contacting you.';

  @override
  String get userBlocked => 'User has been blocked.';

  @override
  String get userBlockedInfo =>
      'You have blocked this user. You cannot send or receive new messages with them.';

  @override
  String get blockedUserBanner =>
      'You have blocked this user. You will no longer receive their messages.';

  @override
  String get blockedByUserBanner =>
      'This user has blocked you. You cannot send messages in this chat.';

  @override
  String get unblockUserTitle => 'Unblock user';

  @override
  String get unblockUserDescription =>
      'Do you want to unblock this user? You will start seeing new messages from them again.';

  @override
  String get unblockUserConfirm => 'Unblock';

  @override
  String get userUnblocked => 'User unblocked';

  @override
  String get removeFriendTitle => 'Remove friend';

  @override
  String get removeFriendDescription =>
      'This will remove this person from your friends list. You can still chat with them if your privacy settings allow it.';

  @override
  String get removeFriendConfirm => 'Remove';

  @override
  String get friendRemoved => 'Friend removed';

  @override
  String get reportMessageTitle => 'Report message';

  @override
  String get reportMessageHint =>
      'Describe why you are reporting this message (harassment, spam, inappropriate content, etc.)';

  @override
  String get reportUserTitle => 'Report user';

  @override
  String get reportUserHint =>
      'Describe the problem (harassment, spam, inappropriate content, etc.)';

  @override
  String get reportUserReasonLabel => 'Reason';

  @override
  String get reportSubmitted => 'Thank you. Your report has been submitted.';

  @override
  String get messageContainsRestrictedContent =>
      'Your message contains language that is not allowed in MW Chat.';

  @override
  String get contentBlockedTitle => 'Message not sent';

  @override
  String get contentBlockedBody =>
      'Your message contains words that are not allowed in MW Chat. Please edit and try again.';

  @override
  String get dangerZone => 'Sensitive actions';

  @override
  String get optional => 'Optional';

  @override
  String get reasonHarassment => 'Harassment or bullying';

  @override
  String get reasonSpam => 'Spam or scam';

  @override
  String get reasonHate => 'Hate or abusive content';

  @override
  String get reasonSexual => 'Sexual or inappropriate content';

  @override
  String get reasonOther => 'Other';

  @override
  String get deleteMessageSuccess => 'Message deleted';

  @override
  String get deleteMessageFailed => 'Failed to delete message';

  @override
  String get deletedForMe => 'Deleted for me';

  @override
  String get deletedAccount => 'Deleted account';

  @override
  String get messageDeletedSuccess => 'Message deleted successfully';

  @override
  String get thisMessageWasDeleted => 'This message was deleted';

  @override
  String get deletingAccount => 'Deleting account...';

  @override
  String get deleteMyAccount => 'Delete my account';

  @override
  String get deleteAccountWarning =>
      'This will permanently delete your account, your messages, and all associated data. This action cannot be undone.';

  @override
  String get deleteAccountDescription =>
      'Deleting your account will permanently remove your profile, messages, and associated data.';

  @override
  String get loginAgainToDelete =>
      'Please log in again and retry account deletion.';

  @override
  String get deleteAccountFailed => 'Failed to delete account.';

  @override
  String get deleteAccountFailedRetry =>
      'Failed to delete account. Please try again.';

  @override
  String get accountDeletedSuccessfully => 'Account deleted successfully';

  @override
  String get termsTitle => 'Terms of Use';

  @override
  String get termsAcceptButton => 'I Agree';

  @override
  String get termsBody =>
      'Welcome to MW Chat!\n\nBy using this app, you agree to the following Terms of Use:\n\n1. No tolerance for objectionable content\n• Do not send or share content that is hateful, harassing, threatening, sexually explicit, violent, discriminatory, or harmful.\n• Do not bully, abuse, or intimidate others.\n• Do not impersonate others or use MW Chat for fraud or illegal activity.\n\n2. User-generated content\n• You are responsible for the messages and content you send.\n• MW Chat may remove any content that violates these terms.\n• MW Chat may suspend or permanently ban users who violate these rules.\n\n3. Reporting and blocking\n• MW Chat provides tools to report users and block abusive users.\n• Reports are reviewed promptly, and we act on objectionable content within 24 hours by removing the content and/or disabling offending accounts.\n\n4. Privacy and safety\n• Do not share sensitive personal information inside chats.\n• Review our Privacy Policy for more details on data handling.\n\n5. Account termination\n• MW Chat may restrict or terminate your access if you violate these terms.\n\nIf you encounter abusive content or behavior, contact us at support@mwchats.com.\n\nBy tapping \"I Agree\", you accept these Terms of Use.';

  @override
  String get byRegisteringYouAgree =>
      'By creating an account, you agree to the MW Chat Terms of Use.';

  @override
  String get viewTermsLink => 'View Terms of Use';

  @override
  String get iAgreeTo => 'I agree to the MW Chat Terms of Use';

  @override
  String get viewTermsOfUse => 'View Terms of Use';

  @override
  String get termsOfUse => 'Terms of Use';

  @override
  String get iAgree => 'I Agree';

  @override
  String get mustAcceptTerms =>
      'You must accept the Terms of Use before registering.';

  @override
  String get contactSupport => 'Contact support';

  @override
  String get contactSupportSubtitle => 'support@mwchats.com';

  @override
  String get about => 'About';

  @override
  String get website => 'Website';

  @override
  String get aboutTitle => 'About MW Chat';

  @override
  String get aboutDescription =>
      'MW Chat is a modern private messaging app designed for secure and smooth communication.\n\nChat with friends, send photos, videos, and voice messages through a clean and simple interface.\n\nFeatures:\n• Real-time messaging\n• Media sharing\n• Secure authentication\n• Simple & elegant design\n• Fast and lightweight';

  @override
  String get legalTitle => 'Legal';

  @override
  String get copyrightText =>
      'MW Chat – modern private messaging app.\nCopyright © 2025 Mousa Abu Hilal.';

  @override
  String get allRightsReserved => 'All rights reserved.';

  @override
  String get sidePanelAppName => 'MW Chat';

  @override
  String get sidePanelTagline => 'Stay close to your favorite people.';

  @override
  String get sidePanelMissingMascotsHint =>
      'Add your MW mascots image to assets/images/mw_bear_and_smurf.png';

  @override
  String get sidePanelFeatureTitle => 'Why people love MW';

  @override
  String get sidePanelFeaturePrivate => 'Private 1:1 conversations.';

  @override
  String get sidePanelFeatureStatus =>
      'Online status and last seen indicators.';

  @override
  String get sidePanelFeatureInvite => 'Invite friends with one tap.';

  @override
  String get sidePanelTip => 'Tip: online Friends appear at the top.';

  @override
  String get sidePanelFollowTitle => 'Follow MW';

  @override
  String get socialFacebook => 'Facebook';

  @override
  String get socialInstagram => 'Instagram';

  @override
  String get socialX => 'X / Twitter';

  @override
  String get loadMore => 'Load more';

  @override
  String get tapToPlay => 'Tap to play';

  @override
  String get videoLabel => 'Video';

  @override
  String get recordingLabel => 'Recording';

  @override
  String get cancelLabel => 'Cancel';

  @override
  String get stopLabel => 'Stop';

  @override
  String get sendLabel => 'Send';

  @override
  String get cancelFriendRequestTitle => 'Cancel friend request';

  @override
  String get send => 'Send';

  @override
  String get privacyTitle => 'Privacy Settings';

  @override
  String get ok => 'OK';

  @override
  String get cancelFriendRequestConfirm => 'Cancel request';

  @override
  String get cancelFriendRequestDescription =>
      'Do you want to cancel this friend request?';

  @override
  String get appBrandingBeta => 'MW Chat 2025';

  @override
  String get profileSafetyToolsSectionTitle => 'Safety tools';

  @override
  String get profileBlockedUserHintLimitedVisibility =>
      'This user has limited what you can see.';

  @override
  String get profileBlockDialogTitleBlock => 'Block user';

  @override
  String get profileBlockDialogTitleUnblock => 'Unblock user';

  @override
  String get profileBlockDialogBodyBlock =>
      'Do you want to block this user? You will no longer receive messages from them in MW Chat.';

  @override
  String get profileBlockDialogBodyUnblock =>
      'Do you want to unblock this user? You will be able to receive messages from them again.';

  @override
  String get profileBlockDialogConfirmBlock => 'Block';

  @override
  String get profileBlockDialogConfirmUnblock => 'Unblock';

  @override
  String get profileBlockButtonBlock => 'Block user';

  @override
  String get profileBlockButtonUnblock => 'Unblock user';

  @override
  String get profileBlockSnackbarBlocked => 'User blocked successfully.';

  @override
  String get profileBlockSnackbarUnblocked => 'User unblocked.';

  @override
  String get profileBlockSnackbarError =>
      'Failed to update block status. Please try again.';

  @override
  String get profileReportDialogTitle => 'Report user';

  @override
  String get profileReportDialogBody =>
      'Please describe why you are reporting this user. For example: spam, bullying, hate speech, or other abusive content.';

  @override
  String get profileReportDialogHint => 'Describe the problem…';

  @override
  String get profileReportDialogSubmit => 'Submit';

  @override
  String get profileReportButtonLabel => 'Report user';

  @override
  String get profileReportSnackbarSuccess =>
      'Report submitted. We will review it.';

  @override
  String get profileReportSnackbarError =>
      'Failed to submit report. Please try again.';

  @override
  String get generalErrorMessage => 'Something went wrong. Please try again.';

  @override
  String get downloadOnAppStore => 'Download on the App Store';

  @override
  String get getItOnGooglePlay => 'Get it on Google Play';

  @override
  String get shareAppLink => 'Share app link';

  @override
  String get presencePrivacyTitle => 'Privacy Settings';

  @override
  String get presencePrivacyNotSignedIn => 'Not signed in';

  @override
  String get presencePrivacySectionSubtitle =>
      'Control who can see your profile and activity.';

  @override
  String get presencePrivacySectionOnlineTitle => 'Online Status';

  @override
  String get presencePrivacyShowWhenOnlineTitle => 'Show when I’m online';

  @override
  String get presencePrivacyShowWhenOnlineSubtitleOn =>
      'Others can see when you are online.';

  @override
  String get presencePrivacyShowWhenOnlineSubtitleOff =>
      'You will appear offline to everyone.';

  @override
  String get presencePrivacyStatusHiddenOffline =>
      'You will appear offline to everyone.';

  @override
  String get presencePrivacyStatusVisibleOnline =>
      'Others can see you as online.';

  @override
  String get presencePrivacyStatusVisibleOfflineWhenInactive =>
      'Others will see you as offline when you’re not active.';

  @override
  String get presencePrivacyAutoOfflineTitle => 'Auto-offline (recommended)';

  @override
  String presencePrivacyAutoOfflineBody(Object staleWindow) {
    return 'If the app is closed, uninstalled, or loses connection, your status may stay “online” briefly. MW Chat automatically treats accounts as offline if there is no recent activity for $staleWindow.';
  }

  @override
  String presencePrivacyStaleMinutes(num minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get presencePrivacyLastSeenUnavailable => 'Last seen: unavailable';

  @override
  String presencePrivacyLastSeenLine(Object value) {
    return 'Last seen: $value';
  }

  @override
  String get presencePrivacyTip =>
      'Tip: Turning this off hides your online status everywhere in the app.';

  @override
  String get privacySectionTitle => 'Privacy';

  @override
  String get onlineStatusTitle => 'Privacy & visibility';

  @override
  String get onlineStatusSubtitle =>
      'Manage who can see your status, activity, and profile';

  @override
  String get presencePrivacySectionProfileTitle => 'Profile & Requests';

  @override
  String get presencePrivacySectionProfileSubtitle =>
      'Control who can view your profile and who can add you as a friend.';

  @override
  String get presencePrivacyProfileVisTitle => 'Profile visibility';

  @override
  String get presencePrivacyProfileVisSubtitle =>
      'Choose who can see your profile details.';

  @override
  String get presencePrivacyProfileVisSheetHint =>
      'This controls visibility of your profile to other users.';

  @override
  String get presencePrivacyProfileVisEveryoneTitle => 'Everyone';

  @override
  String get presencePrivacyProfileVisEveryoneSubtitle =>
      'Anyone can view your profile.';

  @override
  String get presencePrivacyProfileVisFriendsTitle => 'Friends only';

  @override
  String get presencePrivacyProfileVisFriendsSubtitle =>
      'Only your friends can view your profile.';

  @override
  String get presencePrivacyProfileVisNobodyTitle => 'Nobody';

  @override
  String get presencePrivacyProfileVisNobodySubtitle =>
      'Hide your profile from other users.';

  @override
  String get presencePrivacyProfileVisValueEveryone => 'Everyone';

  @override
  String get presencePrivacyProfileVisValueFriends => 'Friends';

  @override
  String get presencePrivacyProfileVisValueNobody => 'Nobody';

  @override
  String get presencePrivacyFriendReqTitle => 'Who can add me as a friend';

  @override
  String get presencePrivacyFriendReqSubtitle =>
      'Control who is allowed to send you friend requests.';

  @override
  String get presencePrivacyFriendReqSheetHint =>
      'This controls whether people can send you friend requests.';

  @override
  String get presencePrivacyFriendReqEveryoneTitle => 'Everyone';

  @override
  String get presencePrivacyFriendReqEveryoneSubtitle =>
      'Anyone can send you a friend request.';

  @override
  String get presencePrivacyFriendReqNobodyTitle => 'Nobody';

  @override
  String get presencePrivacyFriendReqNobodySubtitle =>
      'Disable friend requests from other users.';

  @override
  String get presencePrivacyFriendReqValueEveryone => 'Everyone';

  @override
  String get presencePrivacyFriendReqValueNobody => 'Nobody';

  @override
  String get friendRequestNotAllowed => 'Friend requests are not allowed';

  @override
  String get profilePrivateChatRestricted =>
      'This profile is private. Chat is restricted';

  @override
  String get profilePrivate => 'This profile is private';

  @override
  String get deleteMessageDescription =>
      'Choose how you want to delete this message';

  @override
  String get deleteForMe => 'Delete for me';

  @override
  String get deleteForEveryone => 'Delete for everyone';

  @override
  String get deletingMessageInProgressTitle => 'Deleting message';

  @override
  String get pleaseWait => 'Please wait';

  @override
  String get messageAlreadyDeleted => 'This message was already deleted';

  @override
  String get deletedForMeSuccess => 'Message deleted for you';

  @override
  String get deletedForEveryoneSuccess => 'Message deleted for everyone';

  @override
  String get searchFriendsHint => 'Search friends…';

  @override
  String get searchUsersHint => 'Search MW users…';

  @override
  String get noFriendsFound => 'No friends found.';

  @override
  String get noUsersFound => 'No users found.';

  @override
  String get loading => 'Loading';

  @override
  String get peopleOnMw => 'People on MW';

  @override
  String get myFriends => 'My Friends';

  @override
  String get searchPeopleHint => 'Search people';

  @override
  String get noSearchResults => 'No results found';

  @override
  String get friendRequestsTitle => 'Friend Requests';

  @override
  String get friendRequestsSearchHint => 'Search requests';

  @override
  String get friendRequestsEmpty => 'No requests';

  @override
  String friendRequestsSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You have $count new requests',
      one: 'You have 1 new request',
      zero: 'No new requests',
    );
    return '$_temp0';
  }

  @override
  String get unknownUser => 'Unknown user';

  @override
  String get accountUnavailableSubtitle =>
      'This account is no longer available.';

  @override
  String get invitePlatformTitle => 'Invite via platform';

  @override
  String get tapIconToOpen => 'Tap an icon to open';

  @override
  String get reply => 'Reply';

  @override
  String get more => 'More';

  @override
  String get replyingToMessage => 'Replying to message';

  @override
  String get replying => 'Replying';

  @override
  String get originalMessageNotFound => 'Original message not found';

  @override
  String get fontAndDisplay => 'Font & Display';

  @override
  String get noEmailOnAccount => 'No email linked to this account';

  @override
  String get copied => 'Copied';

  @override
  String get copy => 'Copy';

  @override
  String get fontAndDisplaySubtitle => 'Customize text size and appearance';

  @override
  String get fontSizeLabel => 'Font size';

  @override
  String get fontSizeDesc =>
      'Change how big text looks across MW Chat (including messages).';

  @override
  String get fontStyleLabel => 'Font style';

  @override
  String get fontStyleDesc =>
      'Pick a clean font style that matches your taste.';

  @override
  String get previewLabel => 'Preview';

  @override
  String get previewHeadline => 'MW Chat — messages will look like this.';

  @override
  String get previewBody =>
      'You can keep it small, or make it more comfortable for your eyes.';

  @override
  String get resetToDefault => 'Reset to default';

  @override
  String get backToDefault => 'Back to default.';

  @override
  String get previewMiniLine => 'This is how your chat text feels in real use.';

  @override
  String get fontHintNote =>
      'Tip: Font changes apply instantly across the app.';

  @override
  String get account => 'Account';

  @override
  String get preferences => 'Preferences';

  @override
  String get sensitiveActions => 'Sensitive actions';

  @override
  String get legal => 'Legal & policies';

  @override
  String get webFontNote => 'Font settings apply to the web version only';

  @override
  String get arabicLabel => 'Arabic';

  @override
  String get messageDeletedForMeSuccess => 'Message deleted for you';

  @override
  String get messageDeletedForEveryoneSuccess => 'Message deleted for everyone';

  @override
  String get messageSelectedTitle => 'Message selected';

  @override
  String get copyNotAvailable => 'Copy not available';

  @override
  String get deleteMessageDescriptionEveryone =>
      'Choose how you want to delete this message.';

  @override
  String get deleteMessageDescriptionMe =>
      'This will delete the message for you only.';

  @override
  String get report => 'Report';

  @override
  String get selectedOne => 'Selected';

  @override
  String get selectedMany => 'Multiple selected';

  @override
  String get chooseArabicFont => 'Please choose an Arabic font.';

  @override
  String get chooseEnglishFont => 'Please choose an English font.';

  @override
  String get typographyTip =>
      'Tip: Cool fonts look great for young vibes, clean fonts are best for long chats, and Love fonts are perfect for cute profiles or headings.';

  @override
  String get typographyWebTip =>
      'Web tip: If a font looks unchanged, do a hot restart (R) to reload.';

  @override
  String get englishSample =>
      'English sample: The quick brown fox jumps over the lazy dog.';

  @override
  String get arabicSample =>
      'Arabic sample: Arabic looks beautiful with the right font.';

  @override
  String get newLabel => 'New';

  @override
  String get callLogs_title => 'Call logs';

  @override
  String get callLogs_notSignedIn => 'Not signed in';

  @override
  String get callLogs_filter_all => 'All';

  @override
  String get callLogs_filter_missed => 'Missed';

  @override
  String get callLogs_filter_incoming => 'Incoming';

  @override
  String get callLogs_filter_outgoing => 'Outgoing';

  @override
  String get callLogs_tooltip_retry => 'Retry';

  @override
  String get callLogs_tooltip_markMissedRead => 'Mark missed as read';

  @override
  String get callLogs_tooltip_clearLogs => 'Clear logs';

  @override
  String get callLogs_snack_markedMissedRead => 'Marked missed calls as read';

  @override
  String get callLogs_snack_markedAsRead => 'Marked as read';

  @override
  String callLogs_snack_failedWithError(Object error) {
    return 'Failed: $error';
  }

  @override
  String callLogs_snack_clearedWithCount(Object count, Object filter) {
    return 'Cleared $count $filter call logs';
  }

  @override
  String callLogs_snack_clearFailedWithError(Object error) {
    return 'Clear failed: $error';
  }

  @override
  String callLogs_confirm_clearTitle(Object filter) {
    return 'Clear $filter call logs?';
  }

  @override
  String get callLogs_confirm_clearAllBody =>
      'This will delete all call logs from your history.';

  @override
  String callLogs_confirm_clearFilterBody(Object filter) {
    return 'This will delete only the $filter call logs from your history.';
  }

  @override
  String callLogs_chip_errorPermission(String title) {
    return '$title (permission denied)';
  }

  @override
  String get common_cancel => 'Cancel';

  @override
  String get common_clear => 'Clear';

  @override
  String get common_retry => 'Retry';

  @override
  String get callLogs_error_indexRequired => 'Firestore index required';

  @override
  String get callLogs_error_failedToLoad => 'Failed to load call logs';

  @override
  String get callLogs_error_createIndexHint =>
      'Create the composite index shown in the Firestore error link.';

  @override
  String get callLogs_loading => 'Loading...';

  @override
  String get callLogs_empty_all => 'No call logs yet';

  @override
  String get callLogs_empty_missed => 'No missed calls';

  @override
  String get callLogs_empty_incoming => 'No incoming calls';

  @override
  String get callLogs_empty_outgoing => 'No outgoing calls';

  @override
  String get callLogs_unknownUser => 'Unknown';

  @override
  String get callLogs_result_ended => 'Ended';

  @override
  String get callLogs_result_declined => 'Declined';

  @override
  String get callLogs_result_canceled => 'Canceled';

  @override
  String get callLogs_result_missed => 'Missed';

  @override
  String get callLogs_result_busy => 'Busy';

  @override
  String get callLogs_direction_incoming => 'Incoming';

  @override
  String get callLogs_direction_outgoing => 'Outgoing';

  @override
  String callLogs_chip_indexNeeded(String title) {
    return '$title (index needed)';
  }

  @override
  String callLogs_chip_error(String title) {
    return '$title (error)';
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
  String get debug_insertedCallLog => 'DEBUG: Inserted call log';

  @override
  String get callLogs_tooltip_voiceCall => 'Voice call';

  @override
  String get callLogs_tooltip_videoCall => 'Video call';

  @override
  String get outgoingCall_failedToStart => 'Failed to start call';

  @override
  String get outgoingCall_calling => 'Calling…';

  @override
  String get outgoingCall_connecting => 'Connecting…';

  @override
  String get outgoingCall_pleaseWait => 'Please wait…';

  @override
  String get outgoingCall_notSignedIn => 'Not signed in';

  @override
  String get outgoingCall_invalidPeer => 'Invalid peer';

  @override
  String get call_status_ringing => 'Ringing…';

  @override
  String get call_status_inCall => 'In call';

  @override
  String get call_status_answering => 'Answering…';

  @override
  String get call_status_declined => 'Declined';

  @override
  String get call_status_missed => 'Missed call';

  @override
  String get call_status_canceled => 'Canceled';

  @override
  String get call_status_busy => 'User busy';

  @override
  String get call_status_ended => 'Call ended';

  @override
  String get call_status_canceling => 'Canceling…';

  @override
  String call_failedWithError(Object error) {
    return 'Call failed: $error';
  }

  @override
  String get incomingCall_voice => 'Incoming voice call';

  @override
  String get incomingCall_video => 'Incoming video call';

  @override
  String get incomingCall_accept => 'Accept';

  @override
  String get incomingCall_decline => 'Decline';

  @override
  String get incomingCall_unknownCaller => 'Unknown caller';

  @override
  String get phoneNumberLabel => 'Phone Number';

  @override
  String get phoneNumberHint => 'Enter your phone number';

  @override
  String get invalidPhoneNumber => 'Invalid phone number';

  @override
  String get sendCode => 'Send Code';

  @override
  String get resendCode => 'Resend Code';

  @override
  String get verifyCode => 'Verify Code';

  @override
  String get otpCodeLabel => 'Verification Code';

  @override
  String get otpCodeHint => 'Enter the verification code';

  @override
  String get invalidOtp => 'Invalid verification code';

  @override
  String get sendOtpToContinue => 'Send a verification code to continue';

  @override
  String get enterOtpToContinue => 'Enter the verification code to continue';

  @override
  String get emailLinkedSuccess => 'Email linked successfully';

  @override
  String get addEmailTitle => 'Add your email';

  @override
  String get addEmailSubtitle =>
      'Secure your account by linking an email address';

  @override
  String get confirmPassword => 'Confirm Password';

  @override
  String get linkEmailButton => 'Link Email';

  @override
  String get skipForNow => 'Skip for now';

  @override
  String get emailAlreadyInUseLinking =>
      'This email is already in use by another account';

  @override
  String get credentialAlreadyInUse =>
      'This credential is already associated with another account';

  @override
  String get providerAlreadyLinked =>
      'This sign-in method is already linked to your account';

  @override
  String get countryCodeLabel => 'Country Code';

  @override
  String get phoneNumberHintDigits => 'Enter phone number (digits only)';

  @override
  String get phoneNumber => 'Phone number';

  @override
  String get profileDetailsHint => 'Add your details to complete your profile.';

  @override
  String get completeYourProfile => 'Complete your profile';

  @override
  String get webProfileCompletionNote =>
      'Web note: this screen forces profile completion so names never stay empty.';

  @override
  String minLengthError(int min) {
    return 'Must be at least $min characters.';
  }

  @override
  String maxLengthError(int max) {
    return 'Must be $max characters or less.';
  }

  @override
  String get invalidNameCharacters =>
      'Only letters are allowed. You can use spaces, - and \'.';

  @override
  String get invalidNameFormat =>
      'Please enter a valid name (no extra spaces or symbols).';

  @override
  String get emailOrPhoneLabel => 'Email or Phone';

  @override
  String get emailOrPhoneHintPhone => 'Enter your phone number';

  @override
  String get emailOrPhoneHintEmail => 'Enter your email address';

  @override
  String get emailOrPhone => 'Email or Phone';

  @override
  String get checkYourEmailToVerify =>
      'Check your email to verify your account.';

  @override
  String get addPhoneTitle => 'Add your phone number';

  @override
  String get addPhoneSubtitle =>
      'Link your phone number to secure your account.';

  @override
  String get phoneLinkedSuccess => 'Phone number linked successfully.';

  @override
  String get searchCountryHint => 'Search country';

  @override
  String get phoneHintExample => 'Enter phone number';

  @override
  String get emailHintExample => 'Enter email address';

  @override
  String get phoneAlreadyRegisteredPleaseLogin =>
      'This phone number is already registered. Please log in.';

  @override
  String get emailAlreadyRegisteredPleaseLogin =>
      'This email is already registered. Please log in.';

  @override
  String get emailNotVerifiedYet => 'Your email is not verified yet.';

  @override
  String get verifyEmailToActivate =>
      'Verify your email to activate your account.';

  @override
  String get verifyYourEmailTitle => 'Verify your email';

  @override
  String get verifyEmailPanelBodyNoEmail =>
      'We’ve sent you a verification email. Please check your inbox.';

  @override
  String verifyEmailPanelBodyWithEmail(String email) {
    return 'We’ve sent a verification email to $email. Please check your inbox.';
  }

  @override
  String get iVerifiedMyEmail => 'I verified my email';

  @override
  String get iVerified => 'I verified';

  @override
  String get resend => 'Resend';

  @override
  String get recaptchaRejected =>
      'reCAPTCHA verification was rejected. Please try again.';

  @override
  String get fixChecklistTitle => 'Try the following:';

  @override
  String get fixChecklistAuthorizedDomains =>
      'Make sure your domain is authorized in Firebase.';

  @override
  String get fixChecklistDisableAdBlockers =>
      'Disable ad blockers or privacy extensions.';

  @override
  String get fixChecklistAllowCookies => 'Allow third-party cookies.';

  @override
  String get fixChecklistTryIncognito => 'Try using Incognito / Private mode.';

  @override
  String get fixChecklistAvoidRetries =>
      'Avoid repeated attempts in a short time.';

  @override
  String get devTipTestPhoneNumbers =>
      'Developer tip: Use Firebase test phone numbers to avoid rate limits.';

  @override
  String get recaptchaFailedRefresh =>
      'reCAPTCHA failed. Please refresh the page and try again.';

  @override
  String get otpRateLimited15Min =>
      'Too many attempts. Please try again in 15 minutes.';

  @override
  String get otpTimedOutRefresh =>
      'Verification timed out. Please refresh and try again.';

  @override
  String get unauthorizedDomainFix =>
      'This domain is not authorized. Please check Firebase settings.';

  @override
  String get confirmationNotReadyResend =>
      'Confirmation is not ready yet. Please resend the code.';

  @override
  String get sessionExpiredResend => 'Session expired. Please resend the code.';

  @override
  String get timedOutTryAgain => 'Request timed out. Please try again.';

  @override
  String cooldownLabel(int seconds) {
    return 'You can resend in ${seconds}s';
  }

  @override
  String get linkPhoneTitle => 'Link phone number';

  @override
  String get requestCode => 'Request code';

  @override
  String get smsCode => 'SMS code';

  @override
  String get smsCodeHint => 'Enter the SMS code';

  @override
  String get confirm => 'Confirm';

  @override
  String get selectCountry => 'Select country';

  @override
  String get enterSmsCode => 'Please enter the SMS code';

  @override
  String get requestCodeFirst => 'Please request a verification code first';

  @override
  String get somethingWentWrong => 'Something went wrong. Please try again.';

  @override
  String get linkPhoneSubtitle =>
      'Add a phone number to secure your account and enable phone login.';

  @override
  String get presencePrivacyEveryone => 'Everyone';

  @override
  String get presencePrivacyFriends => 'Friends';

  @override
  String get presencePrivacyNobody => 'Nobody';

  @override
  String get presencePrivacyProfileVisSheetSubtitle =>
      'This controls who can view your profile information.';

  @override
  String get presencePrivacyProfileEveryone =>
      'Anyone can see your profile details.';

  @override
  String get presencePrivacyProfileFriends =>
      'Only your friends can see your profile details.';

  @override
  String get presencePrivacyProfileNobody =>
      'Hide your profile details from everyone.';

  @override
  String get presencePrivacyEmailVisTitle => 'Email visibility';

  @override
  String get presencePrivacyEmailVisSubtitle =>
      'Choose who can see your email on your profile.';

  @override
  String get presencePrivacyEmailVisSheetSubtitle =>
      'This only affects what other users can see. You will always see your own email.';

  @override
  String get presencePrivacyEmailEveryone =>
      'Anyone can see your email on your profile.';

  @override
  String get presencePrivacyEmailFriends =>
      'Only your friends can see your email.';

  @override
  String get presencePrivacyEmailNobody => 'Hide your email from everyone.';
}
