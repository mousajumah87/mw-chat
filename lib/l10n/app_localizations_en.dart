// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get loginTitle => 'Welcome back';

  @override
  String get createAccount => 'Create your MW account';

  @override
  String get choosePicture => 'Choose picture';

  @override
  String get choosePictureTooltip => 'Tap to choose a picture';

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
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get login => 'Login';

  @override
  String get register => 'Register';

  @override
  String get createNewAccount => 'Create new account';

  @override
  String get alreadyHaveAccount => 'Already have an account?';

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
  String get about => 'About';

  @override
  String get settingUpProfile => 'Setting up your profile...';

  @override
  String get accountNotActive => 'Your account is not active yet.';

  @override
  String get waitForActivation => 'Please wait until your account is activated by the admin.';

  @override
  String get logout => 'Logout';

  @override
  String get goBack => 'Go back';

  @override
  String get usersTitle => 'Friends';

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
  String get notLoggedIn => 'Not logged in';

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
  String get failedToUploadFile => 'Failed to upload file';

  @override
  String get uploadFailedStorage => 'Upload failed (storage).';

  @override
  String get uploadFailedMessageSave => 'Upload failed (message save).';

  @override
  String isTyping(Object name) {
    return '$name is typing...';
  }

  @override
  String get attachFile => 'Attach file';

  @override
  String get typeMessageHint => 'Type a message...';

  @override
  String get noMessagesYet => 'No messages yet';

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
  String get attachment => 'Attachment';

  @override
  String get invite => 'Invite';

  @override
  String get inviteFriendsTitle => 'Invite Friends';

  @override
  String get contactsPermissionDenied => 'We can’t access your contacts. Please enable contacts permission in Settings to invite your friends.';

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
  String get inviteContactsTabTitle => 'Invite Contacts';

  @override
  String get inviteWebNotSupported => 'Inviting contacts from your address book is not supported on web. Please use the mobile app instead.';

  @override
  String get search => 'Search contacts';

  @override
  String get retry => 'Retry';

  @override
  String get sidePanelAppName => 'MW Chat';

  @override
  String get sidePanelTagline => 'Stay close to your favorite people.';

  @override
  String get sidePanelMissingMascotsHint => 'Add your MW mascots image to assets/images/mw_bear_and_smurf.png';

  @override
  String get sidePanelFeatureTitle => 'Why people love MW';

  @override
  String get sidePanelFeaturePrivate => 'Private 1:1 conversations with your favorite people.';

  @override
  String get sidePanelFeatureStatus => 'Online status and last seen so you know when friends are around.';

  @override
  String get sidePanelFeatureInvite => 'Invite friends from your contacts with one tap.';

  @override
  String get sidePanelTip => 'Tip: online Friends appear at the top. Tap a user to start chatting instantly.';

  @override
  String get sidePanelFollowTitle => 'Follow MW';

  @override
  String get socialFacebook => 'Facebook';

  @override
  String get socialInstagram => 'Instagram';

  @override
  String get socialX => 'X / Twitter';

  @override
  String get mwUsersTabTitle => 'MW Friends';

  @override
  String get deleteChatTitle => 'Delete chat';

  @override
  String get deleteChatWarning => 'Are you sure you want to delete this chat? This action cannot be undone.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get chatDeleted => 'Chat deleted successfully';

  @override
  String get sendFailed => 'Failed to send message. Please try again.';

  @override
  String get deleteMessageTitle => 'Delete message';

  @override
  String get deleteMessageConfirm => 'Are you sure you want to delete this message?';

  @override
  String get deleteFailed => 'Failed to delete the message. Please try again.';

  @override
  String get chatHistoryDeleteFailed => 'Failed to delete chat history';

  @override
  String get deleteChatDescription => 'Are you sure you want to delete this chat history? This action cannot be undone.';

  @override
  String get chatHistoryDeleted => 'Chat history deleted successfully';

  @override
  String get aboutTitle => 'About MW Chat';

  @override
  String get aboutDescription => 'MW Chat is a modern private messaging app designed for secure and smooth communication.\n\nChat with friends, send photos, videos, and voice messages with a clean and easy interface. MW Chat focuses on privacy, speed, and simplicity.\n\nFeatures:\n• Real-time messaging\n• Media sharing (photos & videos)\n• Secure authentication\n• Simple & elegant design\n• Fast and lightweight\n\nWhether for personal chats or family conversations, MW Chat keeps your communication safe and enjoyable.';

  @override
  String get legalTitle => 'Legal';

  @override
  String get copyrightText => 'MW Chat – modern private messaging app.\nCopyright © 2025 Mousa Abu Hilal. All rights reserved.';

  @override
  String get allRightsReserved => 'All rights reserved.';

  @override
  String get appBrandingBeta => 'MW Chat • beta';
}
