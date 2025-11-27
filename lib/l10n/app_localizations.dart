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

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get goBack;

  /// No description provided for @usersTitle.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get usersTitle;

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

  /// No description provided for @notLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'Not logged in'**
  String get notLoggedIn;

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

  /// No description provided for @isTyping.
  ///
  /// In en, this message translates to:
  /// **'{name} is typing...'**
  String isTyping(Object name);

  /// No description provided for @attachFile.
  ///
  /// In en, this message translates to:
  /// **'Attach file'**
  String get attachFile;

  /// No description provided for @typeMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get typeMessageHint;

  /// No description provided for @noMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noMessagesYet;

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

  /// No description provided for @attachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get attachment;

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

  /// No description provided for @contactsPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'We can’t access your contacts. Please enable contacts permission in Settings to invite your friends.'**
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

  /// No description provided for @inviteContactsTabTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite Contacts'**
  String get inviteContactsTabTitle;

  /// No description provided for @inviteWebNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Inviting contacts from your address book is not supported on web. Please use the mobile app instead.'**
  String get inviteWebNotSupported;

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
  /// **'Private 1:1 conversations with your favorite people.'**
  String get sidePanelFeaturePrivate;

  /// No description provided for @sidePanelFeatureStatus.
  ///
  /// In en, this message translates to:
  /// **'Online status and last seen so you know when friends are around.'**
  String get sidePanelFeatureStatus;

  /// No description provided for @sidePanelFeatureInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite friends from your contacts with one tap.'**
  String get sidePanelFeatureInvite;

  /// No description provided for @sidePanelTip.
  ///
  /// In en, this message translates to:
  /// **'Tip: online Friends appear at the top. Tap a user to start chatting instantly.'**
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

  /// No description provided for @mwUsersTabTitle.
  ///
  /// In en, this message translates to:
  /// **'MW Friends'**
  String get mwUsersTabTitle;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'search'**
  String get search;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About MW Chat'**
  String get aboutTitle;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'MW Chat is a modern private messaging app designed for secure and smooth communication.\n\nChat with friends, send photos, videos, and voice messages with a clean and easy interface. MW Chat focuses on privacy, speed, and simplicity.\n\nFeatures:\n• Real-time messaging\n• Media sharing (photos & videos)\n• Secure authentication\n• Simple & elegant design\n• Fast and lightweight\n\nWhether for personal chats or family conversations, MW Chat keeps your communication safe and enjoyable.'**
  String get aboutDescription;

  /// No description provided for @legalTitle.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get legalTitle;

  /// No description provided for @copyrightText.
  ///
  /// In en, this message translates to:
  /// **'MW Chat – modern private messaging app.\nCopyright © 2025 Mousa Abu Hilal. All rights reserved.'**
  String get copyrightText;

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
