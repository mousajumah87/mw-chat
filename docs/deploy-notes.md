# MW Chat – Deploy & Backend Notes

## 1. Project Pieces

MW Chat has **two main parts**:

1. **Flutter App (iOS / Android / Web)**
    - Code lives under: `lib/`, `ios/`, `android/`
    - Examples: `main.dart`, UI screens, login, chat, etc.
    - Deployed via **Xcode / App Store Connect** (for iOS).

2. **Firebase Cloud Functions (Backend)**
    - Code lives under: `functions/`
    - Main file: `functions/index.js`
    - Example function:
        - `onPrivateMessageCreate` → sends push notifications when a new private message is created in `privateChats/{roomId}/messages/{messageId}`.
    - Deployed via **Firebase CLI** (`firebase deploy`).

---

## 2. When Do I Need a New iOS Build?

You **only need a new iOS build** when you change something in the **Flutter app** itself:

- UI changes
- New screens / flows
- Changes in `main.dart`, auth logic, etc.
- Anything that requires code to run **on the device**

### iOS build flow (short version)

1. Update Flutter code.
2. Build via Xcode (Archive).
3. Upload to App Store Connect.
4. Use TestFlight / submit for review.

---

## 3. When Do I *Not* Need a New iOS Build?

You **do NOT** need a new build when you change **only backend logic** in `functions/index.js`.

Examples:

- Change how notifications are sent.
- Change who should receive the push notification.
- Add new logging, safety checks, etc.

As soon as you deploy the function, **all installed apps** (TestFlight and future App Store users) will use the new backend behavior automatically.

---

## 4. Cloud Functions – Everyday Workflow

### 4.1. Files

- Functions root:  
  `mw/functions/`
- Main file to edit:  
  `mw/functions/index.js`
- Config file:  
  `mw/functions/package.json`

### 4.2. Typical deploy steps

From project root (`mw`):

```bash
cd functions
npm run lint        # optional but good to check style & errors
cd ..
firebase use mw-chat-prod
firebase deploy --only functions:onPrivateMessageCreate
