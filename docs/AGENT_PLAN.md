# Garad phone agent and accessibility plan

> **Soomaali (kooban):** Wejiga 1aad waa diyaar. Garad Voice wuxuu furi karaa apps iyo websites,
> wuxuu diyaarin karaa wicitaan iyo fariimo (WhatsApp/SMS), wuxuuna bilaabi karaa tilmaanta jidka.
> Wejiga 2aad wuxuu siinayaa Garad awood uu ku akhriyo shaashadda, ku riixo, ku qoro, kana jawaabo
> fariimaha, si uu u caawiyo dadka aan gacmaha ama indhaha lahayn. Taasi waxay u baahan tahay code
> Android native ah (AccessibilityService), oggolaansho cad oo user-ka laga helo, iyo ansixinta
> Google Play. Qorshahan wuxuu sharxayaa sida loo dhisayo si ammaan ah.
>
> **Marxaladda 1aad (code-ka waa la qoray):** shaashadda oggolaanshaha, shidid iyo demin, iyo
> akhrinta shaashadda. **Marxaladda 2aad (code-ka waa la qoray):** Garad Voice wuxuu akhriyaa
> shaashadda, wuu riixaa, wuu qoraa, wuuna scroll gareeyaa. Kahor dirid, daabacid, wicitaan,
> lacag bixin ama tirtirid, wuxuu sugayaa "haa" adiga ama badhanka "Haa, samee". Labaduba weli
> laguma tijaabin telefoon, ilaa APK la dhiso.

## Where we are

| Area | Status |
| --- | --- |
| Garad Voice, full screen (Gemini Live style) | Done: camera fills the screen, captions, camera switch |
| Voice sees the camera | Done: a frame goes to the realtime model with every spoken turn |
| Voice sees the screen | Done in desktop browsers (`getDisplayMedia`); **not in the Android app** (WebView has no screen capture) |
| Phone actions, phase 1 | Done: `open_app`, `open_website`, `call_phone`, `send_whatsapp_message`, `send_sms`, `navigate_to`. Calls and messages open ready; the user presses call or send |
| "Talk to Garad" shortcut | Done: long-press the app icon, or `garadai://voice` |
| Read aloud, dictation, downloads, copy in the app | Done |
| Admin control of the app | Done: Admin › Settings › Mobile App |
| Accessibility agent, milestones 1 and 2 | Written, not yet run on a phone: `modules/garad-agent` (read, tap, type, scroll, phone buttons, confirmations, Stop), the consent screen `src/app/agent.tsx`, and the voice tools in `Garad_ai/frontend/src/core/appShell.ts` |

Phase 1 only uses links the phone already understands, so it needs no special permission. It cannot
see or press anything inside other apps. That is phase 2.

## Phase 2: the accessibility agent (Android)

### What it adds

- **Read the screen:** "what's on my screen?", "read my last WhatsApp message".
- **Act in other apps:** tap, type, scroll, go back. For example: open Facebook, write a post and
  stop before *Post* so the user confirms; or play the next TikTok video.
- **Reply to messages:** read incoming WhatsApp and SMS messages aloud, dictate a reply and send it
  after a spoken "yes".
- **Calls:** announce who is calling; answer or reject by voice; call a contact by name.

### Architecture

1. **A native module, `garad-agent`** (Expo local module in Kotlin, added with a config plugin):
   - `GaradAccessibilityService`, which reads the current window as a tree of elements (text,
     description, role, clickable or editable, position). It can perform `click`, `setText`, `scroll`,
     back, home and notifications.
   - `GaradNotificationListener`. It reads messaging notifications and replies through the
     notification's own *Reply* action. This is more reliable than tapping through WhatsApp's screens.
   - Call handling: announce incoming calls; answer or reject with `ANSWER_PHONE_CALLS`. Calls are
     placed through the dialer, which needs no permission and gives the user a final confirmation.
   - JS API: `isEnabled()`, `openSettings()`, `readScreen()`, `perform(action, elementId, value)`,
     `onNotification(listener)`, `reply(notificationKey, text)`.
2. **Native voice for background use.** Once another app is in front, Android pauses the WebView,
   so the voice session has to run natively while the agent works. Two pieces carry it:
   - A foreground service with a persistent notification.
   - A small overlay bubble showing *Garad is working – Stop*.

   The overlay uses the same realtime session endpoint as the web (`/dashboard/user/realtime/chat/session`).

   **Backend work needed:** a token-authenticated way for the app to request that session. Today it
   uses the browser session cookie.
3. **The agent loop:**
   1. The user speaks.
   2. The model plans and calls tools: `read_screen`, `tap(element)`, `type(element, text)`,
      `scroll(direction)`, `go_back`, `open_app`, `wait`.
   3. After each step, a fresh screen summary goes back to the model. At most 20 steps per request.
   4. Hard rules run on the phone, not in the prompt (see Safety).

### Screen sharing in the app

Android needs **MediaProjection**: the system "start recording?" prompt, plus a foreground service of
type `mediaProjection`. Frames are sampled once per spoken turn, as with the camera, and sent to the
same realtime session. This shares the native-voice work above, so it belongs in the same milestone.

### Safety and consent (non-negotiable)

- **Opt-in:** a full-screen explanation in Somali and English of what Garad can see and do, before
  the user is sent to the Accessibility settings. It can be turned off from the app at any time.
- **Always visible:** while the agent acts, the overlay shows what it is doing and a large *Stop*
  button. Saying "stop" or "jooji" also stops it.
- **Spoken confirmation is required before any action that is hard to undo:** sending a message,
  posting, calling, buying or paying, deleting, or changing settings. Garad reads back the exact
  text and recipient, then waits for "yes" / "haa".
- **Never touched:** password and OTP fields, banking and mobile-money apps (EVC Plus, Zaad, e-Dahab
  and bank apps), and the phone's security settings. The block list is enforced in Kotlin.
- **Screen text is data, not instructions:** anything Garad reads on screen cannot start an action
  by itself; only the user's request can (prompt-injection defence).
- **No storage of screens:** screen content is sent only for the current step and is not stored on
  Garad servers beyond the normal conversation record. The privacy policy and Play Data safety form
  must say this.
- **Activity log in the app:** what Garad did, when, and in which app.

### Google Play

- An AccessibilityService that is not the app's core accessibility purpose needs a **prominent
  disclosure, an in-app consent screen, the Play Console accessibility declaration and a review
  video**. Only declare `isAccessibilityTool` if the feature is genuinely built for people with
  disabilities. Here it can be, if the blind and low-vision features are the focus.
- `ANSWER_PHONE_CALLS`, notification access and overlays each need a justification in the
  declaration.
- Until approval, phase 2 can ship in a separate build distributed as an APK to testers.

### Milestone 1: what is in the code

Milestone 2 changed parts of this; see the next section.

- `modules/garad-agent/` is an Expo local module, autolinked on Android; iOS and the web get
  `isSupported = false`.
  - `GaradAccessibilityService` is read-only: no gestures, no key filtering, no event handling.
  - `ScreenReader` turns the active window into at most 300 visible elements. Password fields
    come back as `••••`. Packages whose name contains a blocked keyword (bank, wallet, pay, evc,
    zaad, edahab, dahabshiil, authenticator, password…) return `blocked_app` and are not read.
  - JS API: `isSupported`, `isEnabled()`, `isConnected()`, `openSettings()`, `disable()` and
    `readScreen(delayMs)`. The delay runs natively, because JS timers pause while Garad is in
    the background.
- `src/app/agent.tsx`, reached from App menu › Garad agent (beta):
  - Explains what is read and the safety rules, in Somali or English.
  - "I understand and agree" must be ticked before the settings button works.
  - Shows on / starting / off, re-checked whenever the app comes back to the front.
  - A tester read: switch to another app and see what Garad read 5 seconds later. Nothing read
    leaves the phone in this milestone.
- Checked so far:
  - The Kotlin compiles against the Android 14 API (Expo DSL stubbed).
  - The block list was run on sample packages.
  - TypeScript passes.
  - The Android JS bundle exports.
  - Autolinking resolves `garad-agent` for Gradle.
- Not yet checked: a Gradle build and a run on a phone (blocked by milestone 0).
- Android 13+ greys out accessibility services of apps installed from an APK file ("restricted
  settings") until the user allows them in App info. The settings hint on the consent screen says
  how. Installs from Google Play are not affected.
- The package keyword list is a heuristic. A precise list managed from the admin panel is a follow-up.

### Milestone 2: what is in the code

**Voice tools.** Garad Voice gets these tools only in the Android app with the agent built in
(`window.__garadAgent.screen`):

| Tool | What it does |
| --- | --- |
| `read_screen` | The app name and its elements as short lines, e.g. `[4] button "Send"`, `[3] field (empty)` |
| `tap` | Taps an element, or its nearest tappable parent |
| `type_text` | Replaces the text in a field; never sends |
| `scroll` | Scrolls the largest list, or the one given, up or down |
| `phone_button` | Back, home, recent apps, notifications |
| `confirm_action` | Answers a waiting confirmation from the user's own words |

After each action the phone waits until the app has settled, at most 2.5 s, and returns a fresh
screen. The model can keep going without calling `read_screen` again.

**Rules enforced in Kotlin (`AgentController.kt`).**

- Element ids are valid only for the latest read in the same app. Anything else returns "the screen
  has changed".
- No typing into password fields.
- No reading or acting in blocked apps.
- No acting in Garad itself, system settings, permission screens, the package installer or the Play
  Store.
- A tap whose label or view id matches send, post, share, call, pay, buy, order, delete, remove,
  confirm, submit, install, allow, sign out, or Somali dir, wac, bixi, iibso, tirtir, xaqiiji,
  gudbi, daabac, oggolow, lacag, waits for confirmation:
  - A panel appears over the app: *Garad wants to press "Send" in WhatsApp. Go ahead?*, with
    *Yes, do it* and *No*.
  - The model is told to read back exactly what will happen and ask.
  - The confirmation expires after 90 s.
- *Garad · Stop* (a pill at the top while it acts) refuses every action for 20 s.

**Rules enforced in the web page (`appShell.ts`), not in the prompt.**

- `confirm_action` ignores the model's arguments. It reads the user's latest transcript (from the
  speech-to-text, which the model cannot write) that came after the question:
  - *haa / yes / dir / ok…* approves.
  - *maya / no / ha dirin / jooji…* refuses.
  - Anything else is "not a clear answer".
- Saying *stop* or *jooji* stops the agent on the phone.
- At most 20 screen actions per spoken request.

**Background delivery.** While another app is in front, React Native holds back
`WebView.injectJavaScript`, because view commands wait for frames that pause with the activity. The
agent therefore returns results with `evaluateJavascript` straight from Kotlin (`PageBridge.kt`).
Requests from the page still go through React Native's message event, which RN delivers while
paused.

**Checked here.**

- The Kotlin compiles against the Android 14 API.
- The screen descriptions and the confirmation word list were run on samples.
- TypeScript passes in both repos, and the Android JS bundle exports.
- A Playwright run against Chat Pro with a fake phone and a fake realtime server checked:
  - the tools are offered;
  - yes, no and an unclear answer;
  - confirming with nothing waiting;
  - an on-screen Yes while the model is talking, where `response.create` is sent after
    `response.done`;
  - "jooji" stops the agent;
  - the 21st step is refused;
  - phase 1 still works.

**Needs a phone (milestone 0).** Each of the following is the main open question for its feature:

- **Microphone while another app is in front.** Android silences the microphone of background apps
  unless they run a microphone foreground service. Until milestone 4, spoken follow-ups from inside
  WhatsApp may not be heard. The on-screen Yes and No still work, and so does a request that runs
  start to finish in one go, like "open WhatsApp and read my last message".
- **Starting apps from the background.** This is allowed while the accessibility service is bound.
- **Different phones and app versions:** WhatsApp and Facebook layouts, and Somali speech
  recognition of *haa* and *maya*.

## Blind and low-vision users

| Feature | How |
| --- | --- |
| Start without looking | Done: launcher shortcut. Next: make Garad the phone's **default assistant** (`VoiceInteractionService`), so long-pressing the power or home button starts Garad Voice |
| Works with TalkBack | Voice screen buttons have labels and the status is announced. Next: test every Chat Pro screen with TalkBack and fix unlabeled controls |
| "What's in front of me?" | Done with the camera; add short presets: read text, recognise banknotes, colours, find an object |
| "What's on my screen?" | Phase 2: `read_screen` |
| Messages and calls by voice | Phase 2: notification replies and call announcements |
| Somali speech | Check how well the realtime voices understand and speak Somali; if weak, use the existing Garad TTS for replies |
| Haptics | A short vibration when Garad starts and stops listening |

## Milestones

| # | Milestone | Done when |
| --- | --- | --- |
| 0 | **Android build pipeline** (blocking everything below) | An APK builds in CI or locally; today GitHub Actions is blocked by the account's billing lock and the cloud environment cannot reach `dl.google.com` |
| 1 | `garad-agent` module skeleton, consent screen, enable/disable (**code written**, waiting for a phone test) | The service turns on and off from the app and logs screen trees on a test phone |
| 2 | Read screen and tap or type with confirmations (**code written**, waiting for a phone test) | "Open WhatsApp and read my last message" and "write a Facebook post (don't publish)" work on 3 phones |
| 3 | Notification replies and call announcements | Reply to WhatsApp and SMS by voice with a spoken confirmation |
| 4 | Native background voice and overlay | Voice keeps running while another app is in front; Stop works everywhere |
| 5 | Screen sharing (MediaProjection) | "What's on my screen?" uses a live frame |
| 6 | Default assistant and TalkBack pass | Power-button launch; TalkBack test report with no blocking issues |
| 7 | Play Store review | Accessibility declaration approved |

Each milestone needs testing on real phones, at least one low-end Android device. An emulator alone
is not enough.

## Risks

- Play may reject broad accessibility use. Mitigation: keep the accessibility purpose central, follow
  the disclosure rules, and offer the phase 2 build outside Play first.
- App screens change. Element-based actions with retries are more robust than coordinates; notification
  replies avoid most of the UI.
- Background limits on some Android brands (battery savers) can stop the foreground service. A
  per-brand setup guide may be needed.
- Model mistakes. Confirmations, the block list, step limits and the Stop button contain them.
