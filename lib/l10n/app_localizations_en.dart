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
  String get selectBirthday => 'Select birthday';

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
  String get requiredField => 'Required';

  @override
  String get invalidEmail => 'Invalid email';

  @override
  String get minPassword => 'Minimum 6 characters';

  @override
  String get authError => 'Authentication error';

  @override
  String get failedToCreateUser => 'Failed to create user';

  @override
  String get languageLabel => 'Language';

  @override
  String get menuTitle => 'Menu';

  @override
  String get settingUpProfile => 'Setting up your profile...';

  @override
  String get accountNotActive => 'Your account is not active yet.';

  @override
  String get waitForActivation => 'Please wait until your account is activated by the admin.';

  @override
  String get notLoggedIn => 'Not logged in';

  @override
  String get logout => 'Logout';

  @override
  String get logoutTooltip => 'Logout';

  @override
  String get goBack => 'Go back';

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
  String get profile => 'Profile';

  @override
  String get viewProfile => 'View Profile';

  @override
  String get viewFriendProfile => 'View Friend Profile';

  @override
  String get viewMyProfile => 'View My Profile';

  @override
  String get autoUpdateNotice => 'This screen will update automatically once activated.';

  @override
  String get checkAgain => 'Check again';

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
  String get voiceNotSupportedWeb => 'Voice messages are not supported on Web yet.';

  @override
  String get microphonePermissionRequired => 'Microphone permission is required to record audio.';

  @override
  String get holdMicToRecord => 'Hold the mic to record a voice message';

  @override
  String get previewVoiceMessage => 'Preview voice message';

  @override
  String get voiceMessageLabel => 'Voice message';

  @override
  String get genericFileLabel => 'File';

  @override
  String get removePhoto => 'Remove photo';

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
  String get deleteMessageConfirm => 'Are you sure you want to delete this message?';

  @override
  String get deleteFailed => 'Failed to delete the message. Please try again.';

  @override
  String get deleteChatTitle => 'Delete chat';

  @override
  String get deleteChatWarning => 'Are you sure you want to delete this chat? This action cannot be undone.';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get chatDeleted => 'Chat deleted successfully';

  @override
  String get chatHistoryDeleteFailed => 'Failed to delete chat history';

  @override
  String get deleteChatDescription => 'Are you sure you want to delete this chat history? This action cannot be undone.';

  @override
  String get chatHistoryDeleted => 'Chat history deleted successfully';

  @override
  String get invite => 'Invite';

  @override
  String get inviteFriendsTitle => 'Invite Friends';

  @override
  String get inviteContactsTabTitle => 'Invite Contacts';

  @override
  String get inviteFromContactsFuture => 'Inviting friends directly from your contacts will be available in a future update.';

  @override
  String get inviteShareManual => 'For now, you can share the app link manually.';

  @override
  String get contactsPermissionDenied => 'We can’t access your contacts. Please enable contacts permission in Settings.';

  @override
  String get noContactsFound => 'No contacts with phone numbers were found.';

  @override
  String get inviteSubject => 'Join me on MW Chat';

  @override
  String inviteMessageTemplate(Object androidLink, Object iosLink, Object name) {
    return 'Hi $name, I’m using MW Chat to stay in touch. Download it here:\nAndroid: $androidLink\niOS: $iosLink\nSee you there!';
  }

  @override
  String inviteSent(Object name) {
    return 'Invite sent to $name';
  }

  @override
  String get inviteWebNotSupported => 'Inviting contacts is not supported on web.';

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
  String get friendshipInfoOutgoing => 'Friend request sent. Please wait for approval.';

  @override
  String get friendshipInfoIncoming => 'You have a friend request pending. Accept it to start chatting.';

  @override
  String get friendshipInfoNotFriends => 'You need to be friends to send messages.';

  @override
  String get friendshipFileInfoOutgoing => 'Friend request sent. You can send files once it is accepted.';

  @override
  String get friendshipFileInfoIncoming => 'You have a friend request pending. Accept it to share files.';

  @override
  String get friendshipFileInfoNotFriends => 'Send a friend request to start sharing files.';

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
  String get friendshipCannotSendOutgoing => 'Friend request sent. You can start chatting once it is accepted.';

  @override
  String get friendshipCannotSendIncoming => 'Accept the friend request above to start chatting.';

  @override
  String get friendshipCannotSendNotFriends => 'Send a friend request above to start chatting.';

  @override
  String get blockUserTitle => 'Block user';

  @override
  String get blockUserDescription => 'Blocking this user prevents them from contacting you.';

  @override
  String get userBlocked => 'User has been blocked.';

  @override
  String get userBlockedInfo => 'You have blocked this user. You cannot send or receive new messages with them.';

  @override
  String get blockedUserBanner => 'You have blocked this user. You will no longer receive their messages.';

  @override
  String get blockedByUserBanner => 'This user has blocked you. You cannot send messages in this chat.';

  @override
  String get unblockUserTitle => 'Unblock user';

  @override
  String get unblockUserDescription => 'Do you want to unblock this user? You will start seeing new messages from them again.';

  @override
  String get unblockUserConfirm => 'Unblock';

  @override
  String get userUnblocked => 'User unblocked';

  @override
  String get removeFriendTitle => 'Remove friend';

  @override
  String get removeFriendDescription => 'This will remove this person from your friends list. You can still chat with them if your privacy settings allow it.';

  @override
  String get removeFriendConfirm => 'Remove';

  @override
  String get friendRemoved => 'Friend removed';

  @override
  String get reportMessageTitle => 'Report message';

  @override
  String get reportMessageHint => 'Describe why you are reporting this message (harassment, spam, inappropriate content, etc.)';

  @override
  String get reportUserTitle => 'Report user';

  @override
  String get reportUserHint => 'Describe the problem (harassment, spam, inappropriate content, etc.)';

  @override
  String get reportUserReasonLabel => 'Reason';

  @override
  String get reportSubmitted => 'Thank you. Your report has been submitted.';

  @override
  String get messageContainsRestrictedContent => 'Your message contains language that is not allowed in MW Chat.';

  @override
  String get contentBlockedTitle => 'Message not sent';

  @override
  String get contentBlockedBody => 'Your message contains words that are not allowed in MW Chat. Please edit and try again.';

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
  String get deletingAccount => 'Deleting account...';

  @override
  String get deleteMyAccount => 'Delete my account';

  @override
  String get deleteAccountWarning => 'This will permanently delete your account, your messages, and all associated data. This action cannot be undone.';

  @override
  String get deleteAccountDescription => 'Deleting your account will permanently remove your profile, messages, and associated data.';

  @override
  String get loginAgainToDelete => 'Please log in again and retry account deletion.';

  @override
  String get deleteAccountFailed => 'Failed to delete account.';

  @override
  String get deleteAccountFailedRetry => 'Failed to delete account. Please try again.';

  @override
  String get accountDeletedSuccessfully => 'Account deleted successfully';

  @override
  String get termsTitle => 'Terms of Use';

  @override
  String get termsAcceptButton => 'I Agree';

  @override
  String get termsBody => 'Welcome to MW Chat!\n\nBy using this app, you agree to the following Terms of Use:\n\n1. No tolerance for objectionable content\n• Do not send or share content that is hateful, harassing, threatening, sexually explicit, violent, discriminatory, or harmful.\n• Do not bully, abuse, or intimidate others.\n• Do not impersonate others or use MW Chat for fraud or illegal activity.\n\n2. User-generated content\n• You are responsible for the messages and content you send.\n• MW Chat may remove any content that violates these terms.\n• MW Chat may suspend or permanently ban users who violate these rules.\n\n3. Reporting and blocking\n• MW Chat provides tools to report users and block abusive users.\n• Reports are reviewed promptly, and we act on objectionable content within 24 hours by removing the content and/or disabling offending accounts.\n\n4. Privacy and safety\n• Do not share sensitive personal information inside chats.\n• Review our Privacy Policy for more details on data handling.\n\n5. Account termination\n• MW Chat may restrict or terminate your access if you violate these terms.\n\nIf you encounter abusive content or behavior, contact us at support@mwchats.com.\n\nBy tapping \"I Agree\", you accept these Terms of Use.';

  @override
  String get byRegisteringYouAgree => 'By creating an account, you agree to the MW Chat Terms of Use.';

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
  String get mustAcceptTerms => 'You must accept the Terms of Use before registering.';

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
  String get aboutDescription => 'MW Chat is a modern private messaging app designed for secure and smooth communication.\n\nChat with friends, send photos, videos, and voice messages through a clean and simple interface.\n\nFeatures:\n• Real-time messaging\n• Media sharing\n• Secure authentication\n• Simple & elegant design\n• Fast and lightweight';

  @override
  String get legalTitle => 'Legal';

  @override
  String get copyrightText => 'MW Chat – modern private messaging app.\nCopyright © 2025 Mousa Abu Hilal.';

  @override
  String get allRightsReserved => 'All rights reserved.';

  @override
  String get cancelFriendRequestTitle => 'Cancel friend request';

  @override
  String get cancelFriendRequestDescription => 'Do you want to cancel this friend request?';

  @override
  String get cancelFriendRequestConfirm => 'Cancel request';

  @override
  String get friendRequestCancelled => 'Friend request cancelled';

  @override
  String get friendRequestIncomingBanner => 'This user sent you a friend request.';

  @override
  String get sidePanelAppName => 'MW Chat';

  @override
  String get sidePanelTagline => 'Stay close to your favorite people.';

  @override
  String get sidePanelMissingMascotsHint => 'Add your MW mascots image to assets/images/mw_bear_and_smurf.png';

  @override
  String get sidePanelFeatureTitle => 'Why people love MW';

  @override
  String get sidePanelFeaturePrivate => 'Private 1:1 conversations.';

  @override
  String get sidePanelFeatureStatus => 'Online status and last seen indicators.';

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
  String get appBrandingBeta => 'MW Chat 2025 beta';

  @override
  String get profileSafetyToolsSectionTitle => 'Safety tools';

  @override
  String get profileBlockedUserHintLimitedVisibility => 'This user has limited what you can see.';

  @override
  String get profileBlockDialogTitleBlock => 'Block user';

  @override
  String get profileBlockDialogTitleUnblock => 'Unblock user';

  @override
  String get profileBlockDialogBodyBlock => 'Do you want to block this user? You will no longer receive messages from them in MW Chat.';

  @override
  String get profileBlockDialogBodyUnblock => 'Do you want to unblock this user? You will be able to receive messages from them again.';

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
  String get profileBlockSnackbarError => 'Failed to update block status. Please try again.';

  @override
  String get profileReportDialogTitle => 'Report user';

  @override
  String get profileReportDialogBody => 'Please describe why you are reporting this user. For example: spam, bullying, hate speech, or other abusive content.';

  @override
  String get profileReportDialogHint => 'Describe the problem…';

  @override
  String get profileReportDialogSubmit => 'Submit';

  @override
  String get profileReportButtonLabel => 'Report user';

  @override
  String get profileReportSnackbarSuccess => 'Report submitted. We will review it.';

  @override
  String get profileReportSnackbarError => 'Failed to submit report. Please try again.';

  @override
  String get generalErrorMessage => 'Something went wrong. Please try again.';
}
