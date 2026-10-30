# Garad AI — Android & iOS apps

The Garad AI mobile app for Android and iOS, built with Expo (SDK 58) and React Native. One
codebase produces the Android app (APK + Play Store AAB) and the iOS app.

> **Soomaali:** App-kani waa Garad AI web-ka (https://garad.ai/chat) oo ku dhex jira app native ah.
> Naqshadda, akoonka, xogta iyo dhammaan astaamaha AI waa kuwa web-ka. Wixii web-ka lagu
> beddelo si toos ah ayay app-ka uga muuqanayaan, update app la'aan.

## How it works

The app is a native shell around the Garad AI web app at `https://garad.ai/chat`. It shows the
same design, uses the same account and data, and has every AI feature the website has. There is
one backend and one admin panel for both, and changes deployed to the website appear in the app
without an app update.

What the native shell adds:

| Feature | Details |
| --- | --- |
| App icon, splash screen | Garad branding; the splash stays until the site has loaded |
| Back button (Android) | Goes back inside the site before leaving the app |
| Swipe back, pull to refresh (iOS) | Native gestures |
| Uploads, camera, microphone | File inputs, photo capture and voice work inside the site |
| External links | Other websites open in the in-app browser; `mailto:`/`tel:` open the system app |
| Downloads | Documents, images, videos and exports Chat Pro creates (including `blob:`/`data:` files a WebView can't save) open in the share sheet to save or send; files on other domains open in the browser |
| Copy | `navigator.clipboard.writeText` goes to the native clipboard |
| Read aloud | Android WebView has no `speechSynthesis`; the bridge reads replies with the phone's voice (`expo-speech`) |
| Admin control | Reads Admin › Settings › Mobile App (`/api/mobile-app/config`): forced or optional updates, maintenance screen, announcement banner, menu links |
| App menu | "Garad app" in the Chat Pro sidebar opens a native sheet: Talk to Garad, plans, help, WhatsApp, email, privacy, terms, check for updates, version |
| Talk to Garad | Long-press the app icon (Android) or open `garadai://voice` to start Garad Voice straight away; Voice can see the camera (and the screen on desktop browsers) |
| Voice actions | In Garad Voice, ask Garad to open an app (WhatsApp, Facebook, TikTok, YouTube, Maps…), open a website, call a number, prepare a WhatsApp or SMS message, or start directions (`src/lib/agentActions.ts`). Calls and messages open ready; the user presses call or send |
| Garad agent (beta, Android) | App menu › Garad agent: a consent screen, then the user turns on Garad's accessibility service in the phone settings. Garad Voice can then read the screen and tap, type and scroll in other apps. Sending, posting, calling, paying or deleting waits for a spoken "yes"/"haa" or the on-screen Yes. It never reads password fields, skips banking and mobile-money apps, and has a Stop button. With notification access it also reads new messages (WhatsApp, SMS, Telegram…), replies after confirmation, announces incoming calls and answers or declines them; one-time codes are masked. See `docs/AGENT_PLAN.md` |
| Offline screen | Shown when the site can't be reached, with a retry button |
| App mode | The user agent ends with `GaradApp/<version>`; Chat Pro then switches to app mode (no pinch or focus zoom, no tap highlights or shortcut hints) |
| Theme sync | Chat Pro reports its background colour, so the status bar and safe areas follow the user's light/dark theme |

App mode lives in the website itself (`Garad_ai/frontend/src/core/appShell.ts`), so app-specific
polish ships with normal web deploys. The site and start page are set in `app.json › expo.extra`
(`siteUrl`, `startPath`).

### Known limitations

- **Google sign-in:** Google blocks OAuth inside embedded browsers, so the Google button opens the
  system browser and that login does not carry back into the app. Email/password login works. A
  native Google sign-in can be added later.
- **Payments on iOS:** Apple requires In-App Purchase for digital subscriptions. Checkout pages on
  other domains open outside the app. Before submitting to the App Store, hide web checkout when
  the user agent contains `GaradApp`, or add In-App Purchase (the backend has RevenueCat fields).
- **App Store review (guideline 4.2):** Apple can reject apps that are only a website. The native
  features above help; push notifications are the next recommended addition.

## Project layout

```text
src/app/index.tsx      the web shell (WebView, back button, links, offline screen)
src/app/agent.tsx      Garad agent consent, on/off and read test
modules/garad-agent/   Android accessibility service and its JS API (Expo local module)
src/lib/config.ts      site URL, start page, allowed domains, user agent
src/lib/bridge.ts      injected script + native handlers for downloads, clipboard and read aloud
src/lib/agentActions.ts phone actions requested by Garad Voice
src/lib/remoteConfig.ts admin settings for updates, maintenance, announcement and links
src/components/        app menu, banners, full-screen notices
plugins/withVoiceShortcut.js  Android "Talk to Garad" launcher shortcut
plugins/               config plugin that applies the Android upload key
assets/images/         app icon, adaptive icon, splash
.github/workflows/     Android (APK/AAB) and iOS builds
```

## Develop

Requirements: Node.js 22+, and for native runs Android Studio (Android) or Xcode on a Mac (iOS).

```bash
npm ci
npm run typecheck
npx expo start            # scan the QR code with a development build
npm run android           # build and run on an Android emulator/device
npm run ios               # macOS only
```

Point the app at a staging site with an environment variable:

```bash
EXPO_PUBLIC_SITE_URL=https://staging.garad.ai npx expo start
```

`android/` and `ios/` are generated by `npx expo prebuild` and are not committed. Configure native
behaviour in `app.json` and config plugins instead.

## Android builds (APK + AAB)

Every push to `main` runs **Actions › Android**, which type-checks, bundles, and builds:

- `garad-ai.apk` — install directly on a phone (share the file or a download link)
- `garad-ai.aab` — upload to Google Play

Download both from the run's **Artifacts** (`garad-ai-android`). Pushing a tag like `v1.0.0` also
attaches them to a GitHub Release.

### Upload key (required for Google Play)

Generate the key **once** and keep a backup in the team's secrets manager. Losing it means
you can no longer update the app unless you go through Google's key reset.

```bash
keytool -genkeypair -v -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 \
  -keystore garad-upload.jks -alias garad-upload
base64 -w0 garad-upload.jks > garad-upload.jks.b64   # macOS: base64 -i garad-upload.jks
```

Add these repository secrets (**Settings › Secrets and variables › Actions**):

| Secret | Value |
| --- | --- |
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | contents of `garad-upload.jks.b64` |
| `ANDROID_UPLOAD_STORE_PASSWORD` | keystore password |
| `ANDROID_UPLOAD_KEY_ALIAS` | `garad-upload` |
| `ANDROID_UPLOAD_KEY_PASSWORD` | key password |

Without these secrets the build is signed with the debug key: the APK installs for testing, but
the files are named `*-unsigned-for-store` and Google Play rejects them.

### Google Play

1. Create a Google Play Console developer account.
2. Create the app with package name **`ai.garad.app`**.
3. Enable Play App Signing and upload `garad-ai.aab` to an internal testing track first.
4. Complete the store listing, content rating, Data safety form, and the privacy policy URL.
5. For each release, bump `expo.version` and `expo.android.versionCode` in `app.json`.

## iOS builds

Building for the App Store needs a Mac or a cloud build. This repo uses
[EAS Build](https://docs.expo.dev/build/introduction/) so no Mac is required.

One-time setup:

1. Enrol in the Apple Developer Program and create the app in App Store Connect with bundle ID
   **`ai.garad.app`**.
2. Create an Expo account, then on any computer run `npx eas-cli login` and `npx eas-cli init` in
   this repo. Commit the `extra.eas.projectId` it adds to `app.json`.
3. Run `npx eas-cli credentials` (or the first `eas build`) to let EAS create the distribution
   certificate and provisioning profile, and add an App Store Connect API key for submission.
4. Create an Expo access token and save it as the `EXPO_TOKEN` repository secret.

Then run **Actions › iOS** (tick *submit* to send it to TestFlight), or push a `v*` tag. Without
`EXPO_TOKEN` the workflow only compiles a Simulator build to confirm the native project builds.

For each release, bump `expo.version` and `expo.ios.buildNumber` in `app.json`.

## Store review checklist

- [ ] Account deletion reachable from the website's account settings (Apple guideline 5.1.1(v))
- [ ] Privacy policy URL and Data safety / App Privacy answers in both consoles
- [ ] Reviewer demo account with credits, added to the review notes
- [ ] If Google sign-in is offered on iOS, Sign in with Apple must be offered too (guideline 4.8)
- [ ] No web checkout for digital subscriptions inside the iOS app (see Known limitations)
- [ ] Google Play accessibility declaration and review video for the Garad agent, or ship the agent
      only in a tester build until it is approved (see `docs/AGENT_PLAN.md`)

## Roadmap

- Push notifications
- Native Google and Apple sign-in
- In-app purchases with RevenueCat
