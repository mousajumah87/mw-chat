import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get loginTitle;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create your MW account'**
  String get createAccount;

  /// No description provided for @createNewAccount.
  ///
  /// In en, this message translates to:
  /// **'Create new account'**
  String get createNewAccount;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get alreadyHaveAccount;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @firstName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get firstName;

  /// No description provided for @lastName.
  ///
  /// In en, this message translates to:
  /// **'Last name'**
  String get lastName;

  /// No description provided for @birthday.
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get birthday;

  /// No description provided for @selectBirthday.
  ///
  /// In en, this message translates to:
  /// **'Select birthday'**
  String get selectBirthday;

  /// No description provided for @gender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get gender;

  /// No description provided for @male.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get male;

  /// No description provided for @female.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get female;

  /// No description provided for @preferNotToSay.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get preferNotToSay;

  /// No description provided for @choosePicture.
  ///
  /// In en, this message translates to:
  /// **'Choose picture'**
  String get choosePicture;

  /// No description provided for @choosePictureTooltip.
  ///
  /// In en, this message translates to:
  /// **'Tap to choose a picture'**
  String get choosePictureTooltip;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredField;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email'**
  String get invalidEmail;

  /// No description provided for @minPassword.
  ///
  /// In en, this message translates to:
  /// **'Minimum 6 characters'**
  String get minPassword;

  /// No description provided for @authError.
  ///
  /// In en, this message translates to:
  /// **'Authentication error'**
  String get authError;

  /// No description provided for @failedToCreateUser.
  ///
  /// In en, this message translates to:
  /// **'Failed to create user'**
  String get failedToCreateUser;

  /// No description provided for @settingUpProfile.
  ///
  /// In en, this message translates to:
  /// **'Setting up your profile...'**
  String get settingUpProfile;

  /// No description provided for @accountNotActive.
  ///
  /// In en, this message translates to:
  /// **'Your account is not active yet.'**
  String get accountNotActive;

  /// No description provided for @waitForActivation.
  ///
  /// In en, this message translates to:
  /// **'Please wait until your account is activated by the admin.'**
  String get waitForActivation;

  /// No description provided for @notLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'Not logged in'**
  String get notLoggedIn;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @logoutTooltip.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logoutTooltip;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get goBack;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileUpdated;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailed(Object error);

  /// No description provided for @userProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'User profile'**
  String get userProfileTitle;

  /// No description provided for @userNotFound.
  ///
  /// In en, this message translates to:
  /// **'User not found'**
  String get userNotFound;

  /// No description provided for @ageLabel.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get ageLabel;

  /// No description provided for @birthdayLabel.
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get birthdayLabel;

  /// No description provided for @genderLabel.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get genderLabel;

  /// No description provided for @notSpecified.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get notSpecified;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @usersTitle.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get usersTitle;

  /// No description provided for @mwUsersTabTitle.
  ///
  /// In en, this message translates to:
  /// **'MW Friends'**
  String get mwUsersTabTitle;

  /// No description provided for @notActivated.
  ///
  /// In en, this message translates to:
  /// **'Not activated'**
  String get notActivated;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @lastSeenJustNow.
  ///
  /// In en, this message translates to:
  /// **'Last seen just now'**
  String get lastSeenJustNow;

  /// No description provided for @lastSeenMinutes.
  ///
  /// In en, this message translates to:
  /// **'Last seen {minutes} min ago'**
  String lastSeenMinutes(Object minutes);

  /// No description provided for @lastSeenHours.
  ///
  /// In en, this message translates to:
  /// **'Last seen {hours} h ago'**
  String lastSeenHours(Object hours);

  /// No description provided for @lastSeenDays.
  ///
  /// In en, this message translates to:
  /// **'Last seen {days} d ago'**
  String lastSeenDays(Object days);

  /// No description provided for @noOtherUsers.
  ///
  /// In en, this message translates to:
  /// **'No other friends yet'**
  String get noOtherUsers;

  /// No description provided for @typeMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get typeMessageHint;

  /// No description provided for @isTyping.
  ///
  /// In en, this message translates to:
  /// **'{name} is typing...'**
  String isTyping(Object name);

  /// No description provided for @noMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noMessagesYet;

  /// No description provided for @sendFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send message. Please try again.'**
  String get sendFailed;

  /// No description provided for @attachFile.
  ///
  /// In en, this message translates to:
  /// **'Attach file'**
  String get attachFile;

  /// No description provided for @attachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get attachment;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'📷 Photo'**
  String get photo;

  /// No description provided for @photoWithName.
  ///
  /// In en, this message translates to:
  /// **'📷 Photo: {fileName}'**
  String photoWithName(Object fileName);

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'🎬 Video'**
  String get video;

  /// No description provided for @videoWithName.
  ///
  /// In en, this message translates to:
  /// **'🎬 Video: {fileName}'**
  String videoWithName(Object fileName);

  /// No description provided for @audio.
  ///
  /// In en, this message translates to:
  /// **'🎵 Audio'**
  String get audio;

  /// No description provided for @audioWithName.
  ///
  /// In en, this message translates to:
  /// **'🎵 Audio: {fileName}'**
  String audioWithName(Object fileName);

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'📎 File'**
  String get file;

  /// No description provided for @fileWithName.
  ///
  /// In en, this message translates to:
  /// **'📎 File: {fileName}'**
  String fileWithName(Object fileName);

  /// No description provided for @failedToUploadFile.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload file'**
  String get failedToUploadFile;

  /// No description provided for @uploadFailedStorage.
  ///
  /// In en, this message translates to:
  /// **'Upload failed (storage).'**
  String get uploadFailedStorage;

  /// No description provided for @uploadFailedMessageSave.
  ///
  /// In en, this message translates to:
  /// **'Upload failed (message save).'**
  String get uploadFailedMessageSave;

  /// No description provided for @deleteMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get deleteMessageTitle;

  /// No description provided for @deleteMessageConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this message?'**
  String get deleteMessageConfirm;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete the message. Please try again.'**
  String get deleteFailed;

  /// No description provided for @deleteChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get deleteChatTitle;

  /// No description provided for @deleteChatWarning.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this chat? This action cannot be undone.'**
  String get deleteChatWarning;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @chatDeleted.
  ///
  /// In en, this message translates to:
  /// **'Chat deleted successfully'**
  String get chatDeleted;

  /// No description provided for @chatHistoryDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete chat history'**
  String get chatHistoryDeleteFailed;

  /// No description provided for @deleteChatDescription.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this chat history? This action cannot be undone.'**
  String get deleteChatDescription;

  /// No description provided for @chatHistoryDeleted.
  ///
  /// In en, this message translates to:
  /// **'Chat history deleted successfully'**
  String get chatHistoryDeleted;

  /// No description provided for @invite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get invite;

  /// No description provided for @inviteFriendsTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite Friends'**
  String get inviteFriendsTitle;

  /// No description provided for @inviteContactsTabTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite Contacts'**
  String get inviteContactsTabTitle;

  /// No description provided for @inviteFromContactsFuture.
  ///
  /// In en, this message translates to:
  /// **'Inviting friends directly from your contacts will be available in a future update.'**
  String get inviteFromContactsFuture;

  /// No description provided for @inviteShareManual.
  ///
  /// In en, this message translates to:
  /// **'For now, you can share the app link manually.'**
  String get inviteShareManual;

  /// No description provided for @contactsPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'We can’t access your contacts. Please enable contacts permission in Settings.'**
  String get contactsPermissionDenied;

  /// No description provided for @noContactsFound.
  ///
  /// In en, this message translates to:
  /// **'No contacts with phone numbers were found.'**
  String get noContactsFound;

  /// No description provided for @inviteSubject.
  ///
  /// In en, this message translates to:
  /// **'Join me on MW Chat'**
  String get inviteSubject;

  /// No description provided for @inviteMessageTemplate.
  ///
  /// In en, this message translates to:
  /// **'Hi {name}, I’m using MW Chat to stay in touch. Download it here:\nAndroid: {androidLink}\niOS: {iosLink}\nSee you there!'**
  String inviteMessageTemplate(Object androidLink, Object iosLink, Object name);

  /// No description provided for @inviteSent.
  ///
  /// In en, this message translates to:
  /// **'Invite sent to {name}'**
  String inviteSent(Object name);

  /// No description provided for @inviteWebNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Inviting contacts is not supported on web.'**
  String get inviteWebNotSupported;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @unknownEmail.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownEmail;

  /// No description provided for @addFriendTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add friend'**
  String get addFriendTooltip;

  /// No description provided for @friendRequestedChip.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get friendRequestedChip;

  /// No description provided for @friendAcceptTooltip.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get friendAcceptTooltip;

  /// No description provided for @friendDeclineTooltip.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get friendDeclineTooltip;

  /// No description provided for @friendSectionRequests.
  ///
  /// In en, this message translates to:
  /// **'Friend requests'**
  String get friendSectionRequests;

  /// No description provided for @friendSectionYourFriends.
  ///
  /// In en, this message translates to:
  /// **'Your friends'**
  String get friendSectionYourFriends;

  /// No description provided for @friendSectionAllUsers.
  ///
  /// In en, this message translates to:
  /// **'All MW users'**
  String get friendSectionAllUsers;

  /// No description provided for @friendSectionInactiveUsers.
  ///
  /// In en, this message translates to:
  /// **'Inactive users'**
  String get friendSectionInactiveUsers;

  /// No description provided for @friendRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Friend request sent'**
  String get friendRequestSent;

  /// No description provided for @friendRequestSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send friend request'**
  String get friendRequestSendFailed;

  /// No description provided for @friendRequestAccepted.
  ///
  /// In en, this message translates to:
  /// **'Friend request accepted'**
  String get friendRequestAccepted;

  /// No description provided for @friendRequestAcceptFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to accept friend request'**
  String get friendRequestAcceptFailed;

  /// No description provided for @friendRequestDeclined.
  ///
  /// In en, this message translates to:
  /// **'Friend request declined'**
  String get friendRequestDeclined;

  /// No description provided for @friendRequestDeclineFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to decline friend request'**
  String get friendRequestDeclineFailed;

  /// No description provided for @friendshipInfoOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Friend request sent. Please wait for approval.'**
  String get friendshipInfoOutgoing;

  /// No description provided for @friendshipInfoIncoming.
  ///
  /// In en, this message translates to:
  /// **'You have a friend request pending. Accept it to start chatting.'**
  String get friendshipInfoIncoming;

  /// No description provided for @friendshipInfoNotFriends.
  ///
  /// In en, this message translates to:
  /// **'You need to be friends to send messages.'**
  String get friendshipInfoNotFriends;

  /// No description provided for @friendshipFileInfoOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Friend request sent. You can send files once it is accepted.'**
  String get friendshipFileInfoOutgoing;

  /// No description provided for @friendshipFileInfoIncoming.
  ///
  /// In en, this message translates to:
  /// **'You have a friend request pending. Accept it to share files.'**
  String get friendshipFileInfoIncoming;

  /// No description provided for @friendshipFileInfoNotFriends.
  ///
  /// In en, this message translates to:
  /// **'Send a friend request to start sharing files.'**
  String get friendshipFileInfoNotFriends;

  /// No description provided for @friendshipBannerNotFriends.
  ///
  /// In en, this message translates to:
  /// **'You’re not friends with {name} yet. Send a friend request to start chatting.'**
  String friendshipBannerNotFriends(Object name);

  /// No description provided for @friendshipBannerSendRequestButton.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get friendshipBannerSendRequestButton;

  /// No description provided for @friendshipBannerIncoming.
  ///
  /// In en, this message translates to:
  /// **'{name} sent you a friend request.'**
  String friendshipBannerIncoming(Object name);

  /// No description provided for @friendshipBannerOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Friend request sent. Waiting for {name} to accept.'**
  String friendshipBannerOutgoing(Object name);

  /// No description provided for @friendshipCannotSendOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Friend request sent. You can start chatting once it is accepted.'**
  String get friendshipCannotSendOutgoing;

  /// No description provided for @friendshipCannotSendIncoming.
  ///
  /// In en, this message translates to:
  /// **'Accept the friend request above to start chatting.'**
  String get friendshipCannotSendIncoming;

  /// No description provided for @friendshipCannotSendNotFriends.
  ///
  /// In en, this message translates to:
  /// **'Send a friend request above to start chatting.'**
  String get friendshipCannotSendNotFriends;

  /// No description provided for @blockUserTitle.
  ///
  /// In en, this message translates to:
  /// **'Block user'**
  String get blockUserTitle;

  /// No description provided for @blockUserDescription.
  ///
  /// In en, this message translates to:
  /// **'Blocking this user prevents them from contacting you.'**
  String get blockUserDescription;

  /// No description provided for @userBlocked.
  ///
  /// In en, this message translates to:
  /// **'User has been blocked.'**
  String get userBlocked;

  /// No description provided for @userBlockedInfo.
  ///
  /// In en, this message translates to:
  /// **'You have blocked this user. You cannot send or receive new messages with them.'**
  String get userBlockedInfo;

  /// No description provided for @blockedUserBanner.
  ///
  /// In en, this message translates to:
  /// **'You have blocked this user. You will no longer receive their messages.'**
  String get blockedUserBanner;

  /// No description provided for @blockedByUserBanner.
  ///
  /// In en, this message translates to:
  /// **'This user has blocked you. You cannot send messages in this chat.'**
  String get blockedByUserBanner;

  /// No description provided for @unblockUserTitle.
  ///
  /// In en, this message translates to:
  /// **'Unblock user'**
  String get unblockUserTitle;

  /// No description provided for @unblockUserDescription.
  ///
  /// In en, this message translates to:
  /// **'Do you want to unblock this user? You will start seeing new messages from them again.'**
  String get unblockUserDescription;

  /// No description provided for @unblockUserConfirm.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblockUserConfirm;

  /// No description provided for @userUnblocked.
  ///
  /// In en, this message translates to:
  /// **'User unblocked'**
  String get userUnblocked;

  /// No description provided for @removeFriendTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove friend'**
  String get removeFriendTitle;

  /// No description provided for @removeFriendDescription.
  ///
  /// In en, this message translates to:
  /// **'This will remove this person from your friends list. You can still chat with them if your privacy settings allow it.'**
  String get removeFriendDescription;

  /// No description provided for @removeFriendConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeFriendConfirm;

  /// No description provided for @friendRemoved.
  ///
  /// In en, this message translates to:
  /// **'Friend removed'**
  String get friendRemoved;

  /// No description provided for @reportMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Report message'**
  String get reportMessageTitle;

  /// No description provided for @reportMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Describe why you are reporting this message (harassment, spam, inappropriate content, etc.)'**
  String get reportMessageHint;

  /// No description provided for @reportUserTitle.
  ///
  /// In en, this message translates to:
  /// **'Report user'**
  String get reportUserTitle;

  /// No description provided for @reportUserHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the problem (harassment, spam, inappropriate content, etc.)'**
  String get reportUserHint;

  /// No description provided for @reportUserReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reportUserReasonLabel;

  /// No description provided for @reportSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Thank you. Your report has been submitted.'**
  String get reportSubmitted;

  /// No description provided for @messageContainsRestrictedContent.
  ///
  /// In en, this message translates to:
  /// **'Your message contains language that is not allowed in MW Chat.'**
  String get messageContainsRestrictedContent;

  /// No description provided for @contentBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Message not sent'**
  String get contentBlockedTitle;

  /// No description provided for @contentBlockedBody.
  ///
  /// In en, this message translates to:
  /// **'Your message contains words that are not allowed in MW Chat. Please edit and try again.'**
  String get contentBlockedBody;

  /// No description provided for @dangerZone.
  ///
  /// In en, this message translates to:
  /// **'Sensitive actions'**
  String get dangerZone;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @reasonHarassment.
  ///
  /// In en, this message translates to:
  /// **'Harassment or bullying'**
  String get reasonHarassment;

  /// No description provided for @reasonSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam or scam'**
  String get reasonSpam;

  /// No description provided for @reasonHate.
  ///
  /// In en, this message translates to:
  /// **'Hate or abusive content'**
  String get reasonHate;

  /// No description provided for @reasonSexual.
  ///
  /// In en, this message translates to:
  /// **'Sexual or inappropriate content'**
  String get reasonSexual;

  /// No description provided for @reasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get reasonOther;

  /// No description provided for @deletingAccount.
  ///
  /// In en, this message translates to:
  /// **'Deleting account...'**
  String get deletingAccount;

  /// No description provided for @deleteMyAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get deleteMyAccount;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete your account, your messages, and all associated data. This action cannot be undone.'**
  String get deleteAccountWarning;

  /// No description provided for @deleteAccountDescription.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account will permanently remove your profile, messages, and associated data.'**
  String get deleteAccountDescription;

  /// No description provided for @loginAgainToDelete.
  ///
  /// In en, this message translates to:
  /// **'Please log in again and retry account deletion.'**
  String get loginAgainToDelete;

  /// No description provided for @deleteAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete account.'**
  String get deleteAccountFailed;

  /// No description provided for @deleteAccountFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete account. Please try again.'**
  String get deleteAccountFailedRetry;

  /// No description provided for @accountDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Account deleted successfully'**
  String get accountDeletedSuccessfully;

  /// No description provided for @termsTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get termsTitle;

  /// No description provided for @termsAcceptButton.
  ///
  /// In en, this message translates to:
  /// **'I Agree'**
  String get termsAcceptButton;

  /// No description provided for @termsBody.
  ///
  /// In en, this message translates to:
  /// **'Welcome to MW Chat!\n\nBy using this app, you agree to the following Terms of Use:\n\n1. No tolerance for objectionable content\n• Do not send or share content that is hateful, harassing, threatening, sexually explicit, violent, discriminatory, or harmful.\n• Do not bully, abuse, or intimidate others.\n• Do not impersonate others or use MW Chat for fraud or illegal activity.\n\n2. User-generated content\n• You are responsible for the messages and content you send.\n• MW Chat may remove any content that violates these terms.\n• MW Chat may suspend or permanently ban users who violate these rules.\n\n3. Reporting and blocking\n• MW Chat provides tools to report users and block abusive users.\n• Reports are reviewed promptly, and we act on objectionable content within 24 hours by removing the content and/or disabling offending accounts.\n\n4. Privacy and safety\n• Do not share sensitive personal information inside chats.\n• Review our Privacy Policy for more details on data handling.\n\n5. Account termination\n• MW Chat may restrict or terminate your access if you violate these terms.\n\nIf you encounter abusive content or behavior, contact us at support@mwchats.com.\n\nBy tapping \"I Agree\", you accept these Terms of Use.'**
  String get termsBody;

  /// No description provided for @byRegisteringYouAgree.
  ///
  /// In en, this message translates to:
  /// **'By creating an account, you agree to the MW Chat Terms of Use.'**
  String get byRegisteringYouAgree;

  /// No description provided for @viewTermsLink.
  ///
  /// In en, this message translates to:
  /// **'View Terms of Use'**
  String get viewTermsLink;

  /// No description provided for @iAgreeTo.
  ///
  /// In en, this message translates to:
  /// **'I agree to the MW Chat Terms of Use'**
  String get iAgreeTo;

  /// No description provided for @viewTermsOfUse.
  ///
  /// In en, this message translates to:
  /// **'View Terms of Use'**
  String get viewTermsOfUse;

  /// No description provided for @termsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get termsOfUse;

  /// No description provided for @iAgree.
  ///
  /// In en, this message translates to:
  /// **'I Agree'**
  String get iAgree;

  /// No description provided for @mustAcceptTerms.
  ///
  /// In en, this message translates to:
  /// **'You must accept the Terms of Use before registering.'**
  String get mustAcceptTerms;

  /// No description provided for @contactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get contactSupport;

  /// No description provided for @contactSupportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'support@mwchats.com'**
  String get contactSupportSubtitle;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @website.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get website;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About MW Chat'**
  String get aboutTitle;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'MW Chat is a modern private messaging app designed for secure and smooth communication.\n\nChat with friends, send photos, videos, and voice messages through a clean and simple interface.\n\nFeatures:\n• Real-time messaging\n• Media sharing\n• Secure authentication\n• Simple & elegant design\n• Fast and lightweight'**
  String get aboutDescription;

  /// No description provided for @legalTitle.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get legalTitle;

  /// No description provided for @copyrightText.
  ///
  /// In en, this message translates to:
  /// **'MW Chat – modern private messaging app.\nCopyright © 2025 Mousa Abu Hilal.'**
  String get copyrightText;

  /// No description provided for @allRightsReserved.
  ///
  /// In en, this message translates to:
  /// **'All rights reserved.'**
  String get allRightsReserved;

  /// No description provided for @cancelFriendRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel friend request'**
  String get cancelFriendRequestTitle;

  /// No description provided for @cancelFriendRequestDescription.
  ///
  /// In en, this message translates to:
  /// **'Do you want to cancel this friend request?'**
  String get cancelFriendRequestDescription;

  /// No description provided for @cancelFriendRequestConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get cancelFriendRequestConfirm;

  /// No description provided for @friendRequestCancelled.
  ///
  /// In en, this message translates to:
  /// **'Friend request cancelled'**
  String get friendRequestCancelled;

  /// No description provided for @friendRequestIncomingBanner.
  ///
  /// In en, this message translates to:
  /// **'This user sent you a friend request.'**
  String get friendRequestIncomingBanner;

  /// No description provided for @sidePanelAppName.
  ///
  /// In en, this message translates to:
  /// **'MW Chat'**
  String get sidePanelAppName;

  /// No description provided for @sidePanelTagline.
  ///
  /// In en, this message translates to:
  /// **'Stay close to your favorite people.'**
  String get sidePanelTagline;

  /// No description provided for @sidePanelMissingMascotsHint.
  ///
  /// In en, this message translates to:
  /// **'Add your MW mascots image to assets/images/mw_bear_and_smurf.png'**
  String get sidePanelMissingMascotsHint;

  /// No description provided for @sidePanelFeatureTitle.
  ///
  /// In en, this message translates to:
  /// **'Why people love MW'**
  String get sidePanelFeatureTitle;

  /// No description provided for @sidePanelFeaturePrivate.
  ///
  /// In en, this message translates to:
  /// **'Private 1:1 conversations.'**
  String get sidePanelFeaturePrivate;

  /// No description provided for @sidePanelFeatureStatus.
  ///
  /// In en, this message translates to:
  /// **'Online status and last seen indicators.'**
  String get sidePanelFeatureStatus;

  /// No description provided for @sidePanelFeatureInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite friends with one tap.'**
  String get sidePanelFeatureInvite;

  /// No description provided for @sidePanelTip.
  ///
  /// In en, this message translates to:
  /// **'Tip: online Friends appear at the top.'**
  String get sidePanelTip;

  /// No description provided for @sidePanelFollowTitle.
  ///
  /// In en, this message translates to:
  /// **'Follow MW'**
  String get sidePanelFollowTitle;

  /// No description provided for @socialFacebook.
  ///
  /// In en, this message translates to:
  /// **'Facebook'**
  String get socialFacebook;

  /// No description provided for @socialInstagram.
  ///
  /// In en, this message translates to:
  /// **'Instagram'**
  String get socialInstagram;

  /// No description provided for @socialX.
  ///
  /// In en, this message translates to:
  /// **'X / Twitter'**
  String get socialX;

  /// No description provided for @appBrandingBeta.
  ///
  /// In en, this message translates to:
  /// **'MW Chat • beta'**
  String get appBrandingBeta;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar': return AppLocalizationsAr();
    case 'en': return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
