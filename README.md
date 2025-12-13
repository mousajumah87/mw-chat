# MW Chat

Modern private messaging app built with Flutter, Firebase, and Cloud Functions.  
Clean. Secure. Fast. Multilingual (English & Arabic).  
Copyright ©2025 Mousa Abu Hilal.

---

## 🚀 Overview

MW Chat is a real-time messaging application designed for privacy, clarity, and performance.

### It supports:

- Direct **1-to-1 private messaging**
- Media sharing (**photos, videos, voice messages, files**)
- **Push notifications** using Firebase Cloud Messaging (FCM)
- **User blocking** & content reporting
- **Typing indicators**
- **Read/unread** message counters
- Secure backend enforced with **Firestore security rules**
- Multilingual UI (**Arabic / English**)
- **App Check** (App Attest on iOS, Play Integrity on Android)

---

## 📁 Repository Contents

mw/
├── lib/ # Flutter application source
├── ios/ # iOS native setup (App Attest, Firebase)
├── android/ # Android native config
├── assets/ # Images, icons, fonts
├── functions/ # Firebase Cloud Functions backend
│ ├── index.js # Push notification trigger
│ └── package.json
├── docs/ # Internal documentation
│ └── deploy-notes.md # Deployment instructions
├── firebase.json # Firebase hosting & functions config
├── firestore.rules # Firestore security rules
├── pubspec.yaml # Flutter dependencies & assets
└── README.md


---

## 🛠️ Technologies Used

- **Flutter 3.x** (iOS, Android, Web)
- **Firebase Authentication**
- **Cloud Firestore**
- **Firebase Cloud Messaging (FCM)**
- **Firebase Cloud Functions**
- **Firebase Storage**
- **App Check (iOS: App Attest, Android: Play Integrity)**

---

## ⚡ Cloud Functions Overview

MW Chat uses a backend trigger (`functions/index.js`) to:

- Deliver **push notifications** when a new message is created
- Prevent notifications from blocked users
- Prevent duplicate notifications
- Handle localization (English / Arabic)
- Secure sending via Firebase Admin SDK

To deploy updated Functions:

### 🔧 Deploy Only Cloud Functions
firebase deploy --only functions

### 🌐 Deploy Hosting (Website)
firebase deploy --only hosting

flutter run
### Build release (Android):

flutter build apk --release


### Build release (iOS):
flutter build ios --release

---

## 🔐 App Security (High Level)

| Area                    | Protection |
|------------------------|------------|
| Authentication         | Firebase Auth |
| Backend Rules          | Firestore security rules |
| App Attestation (iOS)  | App Attest |
| App Attestation (Android) | Play Integrity |
| Database Access        | User-scoped document rules |
| Cloud Messaging        | Device tokens stored securely |

---

## 📦 Deployment Checklist

Before releasing:

- [ ] Update pubspec version
- [ ] Build release version (iOS & Android)
- [ ] Deploy Firebase Functions
- [ ] Deploy Firebase Hosting (website)
- [ ] Test push notifications on a physical device
- [ ] Upload new build to App Store Connect
- [ ] Test account creation + deletion workflow
- [ ] Snap new screenshots (if UI changed)

---

## © License

Private proprietary project.  
All rights reserved to **Mousa Abu Hilal**.


Full steps documented in:  
`docs/deploy-notes.md`

---

## 🛡 Security

- Firestore is fully locked down using rules
- App Check enforced
- All messages validated on server
- FCM tokens securely stored

---

## 📄 License

This project is private and copyrighted ©2025 Mousa Abu Hilal.

Unauthorized use or distribution is prohibited.

---


