<h1 align="center">PomodoroSense PreRelease</h1>

<p align="center">
  <em>A focus timer for Apple devices. Private, native, quietly rewarding.</em>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#screenshots">Screenshots</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#keyboard-shortcuts">Shortcuts</a> ·
  <a href="#tech-stack">Tech Stack</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="#license">License</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/iOS-27%2B-000000?logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/macOS-27%2B-000000?logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/SwiftUI-native-blue" />
  <a href="https://polyformproject.org/licenses/noncommercial/1.0.0/">
    <img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue" />
  </a>
  <img src="https://img.shields.io/badge/vibe--coded-yes-orange?logo=openai&logoColor=white" />
  <a href="https://github.com/tomasagustinrossi">
    <img src="https://img.shields.io/badge/Author-Tomas%20Rossi-blue" />
  </a>
</p>

<p align="center">
  <img src="Screenshots/pomodorosense-hero-card.png" width="820" alt="PomodoroSense — focus timer, audio, live activity and shop">
  <br>
  <sub><i><!-- TODO: add hero image (main timer screenshot, 820×460) --></i></sub>
</p>

---

**PomodoroSense** is a Pomodoro timer for iOS and macOS that combines deep focus sessions with a quiet progression system, a fully procedural audio engine, and a peer-to-peer Mirror Mode that keeps two devices in sync — without ever touching a server.

It is designed to feel like a native Apple app first: spring-based animations, consistent haptics, adaptive themes per soundscape, and native Live Activities, Home Screen widgets, and desktop widgets.

---

## Table of Contents

- [Why PomodoroSense](#why-pomodorosense)
- [Features](#features)
  - [Focus Timer](#-focus-timer)
  - [Free Mode](#-free-mode)
  - [Audio Engine](#-audio-engine)
  - [Live Activities & Widgets](#-live-activities--widgets)
  - [Mirror Mode](#-mirror-mode)
  - [Economy & Streaks](#-economy--streaks)
  - [Shop](#-shop)
  - [Calendar & Stats](#-calendar--stats)
  - [Design](#-design)
- [Screenshots](#screenshots)
- [Installation](#installation)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Privacy](#privacy)
- [How PomodoroSense was built](#how-pomodorosense-was-built)
- [Contributing](#contributing)
- [Author](#author)
- [License](#license)
- [Acknowledgments](#acknowledgments)

---

## Why PomodoroSense

Most Pomodoro apps are either **too simple** or **too social**. PomodoroSense is what you get when you build a focus timer for yourself first:

- **Native on iOS and macOS.** Not a port, not a web wrapper. SwiftUI all the way down, with platform-specific experiences where it matters (menu bar app on Mac, Dynamic Island on iPhone).
- **No account, no cloud, no telemetry.** Mirror Mode syncs over your local network with end-to-end encryption. Your focus data never leaves your devices.
- **A quiet economy.** Earn chips for finishing sessions. Build a streak. Unlock something new. The rewards are real, the loop is gentle, and the math is tuned so it never feels like a slot machine.
- **Audio you actually want to hear.** Procedural noise, binaural beats, and ambient soundscapes, each with its own carefully-tuned volume curve.
- **Crafted, not cobbled.** HIG-aligned motion, contextual haptics, per-sound adaptive color themes.

---

## Features

### ⏱ Focus Timer

- **Custom presets**: focus length, break length, and number of sessions, fully configurable.
- **In-session controls**: pause, resume, skip forward, skip backward, and reset — from the app, the widget, or the Live Activity.
- **Session selection**: jump to any session inside the current preset by tapping the session bar.
- **State restoration**: if the app is killed, an interrupted session is preserved and resumed on relaunch (configurable).
- **Smart phase transitions**: focus → break → focus → … → done, with automatic cross-midnight handling (a preset that starts at 23:50 and finishes at 00:20 counts entirely for the day it ended).

### ♾ Free Mode

- **Unlimited timer** with no structure: start, pause, stop.
- Ideal for deep work sessions that don't fit a Pomodoro pattern.
- **Session history** with duration, time range, and optional notes.
- **Full audio support** (noise, binaural, ambient) — same engine as Pomodoro, isolated session.

### 🎧 Audio Engine

- **Procedural noise** generated in real time on the audio thread: brown, pink, white, violet.
- **Binaural beats** with a 432 Hz carrier:
  - Gamma (40 Hz) — peak focus
  - Beta (15 Hz) — active concentration
  - Alpha (10 Hz) — relaxed alertness
  - Theta (6 Hz) — deep calm
- **Ambient soundscapes**: nature, rain, ocean, classical music, fireplace.
- **Per-source volume** with smooth exponential curves, fade-in / fade-out on play, pause, and stop.
- **Independent mixing**: binaural, noise, and ambience can all play simultaneously.
- **Real-time equalizer** in the app to adjust each source on the fly.
- **Background audio**: continues while the app is in the background (required `UIBackgroundModes: audio`).

### 📱 Live Activities & Widgets

- **Dynamic Island** (iPhone) with live countdown, phase label, session progress, and controls: pause, resume, skip, stop.
- **Lock Screen Live Activity** with the same controls plus a larger clock.
- **Home Screen widget** (iOS) and **desktop widget** (macOS) showing the current timer, chips balance, and streak.
- **Reward panel**: when a session completes, the Live Activity transforms into a compact reward summary (chips earned, streak update).
- **Smart deduplication**: updates are only sent when the state actually changes, so the ActivityKit system never drops frames.
- **Foreground retry**: if iOS blocked the initial `Activity.request` while the app was in the background, the Live Activity is automatically retried when you return to the app.

### 🔗 Mirror Mode

- **Peer-to-peer sync** between two devices over the local network.
- **No cloud, no account, no server.** Pairing uses a shared key derived from a 16-character code (shown as QR or copy-paste), transmitted over TLS-PSK.
- **Master / Mirror roles** negotiated automatically by the connection handshake.
- **Automatic reconnection** with state reconciliation — if the connection drops, both sides resume without losing the active session.
- **Full control from either side**: pause, resume, skip, stop — mirrored in real time.
- **Live Activity on the Mirror**: the Mirror shows the Master's timer in its own Dynamic Island, updated in real time while the app is in the foreground.

> Mirror Mode is designed for the common case: your iPhone and your Mac, or two iPhones on the same Wi-Fi, with no setup beyond scanning a QR.

### 🏆 Economy & Streaks

- **Daily streaks** with an exponential multiplier — the longer you keep the habit, the more each session is worth.
- **Chips**: earned for every completed focus session, with a soft cap that scales with your streak.
- **Session quality multipliers**: longer focus sessions earn more per minute than shorter ones.
- **Lucky sessions**: rare bonuses on longer sessions that keep the economy interesting without feeling random.
- **Daily soft caps** on every currency to prevent grind, keep the balance meaningful, and preserve the streak as the primary signal.
- **Prestige progression**: as your streak grows, new item tiers unlock in the shop (the details are a surprise — discover them by playing).
- **Tier unlock popups**: a moment of celebration when a new milestone is reached.

### 🛍 Shop

- **3D items** rendered in SceneKit with per-tier metallic materials (bronze, silver, and higher).
- **Multiple visual sources**: SF Symbols, PNG/JPG images, and full `.usdz` models.
- **Procedural extrusion**: image-based items are extruded from their alpha silhouette with a beveled edge and proper hole handling.
- **Rotating previews** on the item detail popup with drag-to-rotate.
- **Persistent collection**: purchased items stay in your collection forever.
- **"My Collection" view**: a curated gallery of everything you own, with 3D previews.

### 📅 Calendar & Stats

- **Focus heatmap** of the last 90 days, colored by session intensity.
- **Adaptive color tiers**: thresholds are recalculated from the last 30 days using percentiles, so the calendar self-calibrates to your pace.
- **Daily goals**: set a goal for any day, track completion with a star, and see focus time accumulated toward each goal.
- **Day detail popup**: tap any day to see the full session list (focus minutes, break minutes, total sessions) and manage that day's goal.
- **Monthly reports**: records older than 90 days are automatically compacted into monthly summaries, keeping the app lightweight without losing history.
- **Wallet summary**: chips, silver, and streak totals at a glance.

### 🎨 Design

- **Adaptive themes**: each ambient soundscape has its own color palette for focus and break phases.
- **Spring-based motion** everywhere (no linear easing).
- **Contextual haptics** on iOS: press, release, success, warning, error.
- **Native macOS experience**: menu bar app with live timer label, keyboard-driven navigation, Dock bounce on phase change.
- **Multi-platform, single codebase**: shared models, shared view models, platform-specific views.

---

## Screenshots

<!-- TODO: Replace with real screenshots. Suggested 4–6 images, 2x retina, ~800–1200px wide. -->

<p align="center">
  <img src="Screenshots/timer.png" width="220" alt="Focus timer with active session">
  <img src="Screenshots/equalizer.png" width="220" alt="Audio equalizer with binaural and noise controls">
  <img src="Screenshots/shop.png" width="220" alt="3D shop with rotating items">
  <img src="Screenshots/calendar.png" width="220" alt="Calendar heatmap with daily goals">
</p>

<p align="center">
  <sub>Timer · Equalizer · Shop · Calendar</sub>
</p>

<!-- TODO (optional):
- Screenshot of the Dynamic Island with a running session.
- Photo of two devices side by side in Mirror Mode.
- Screenshot of Free Mode with session history.
- macOS menu bar with the timer label.
-->

---

## Installation

### Requirements

- **iOS 17.0+** or **macOS 14.0+**
- Xcode 16.0+ (for building from source)
- Swift 5.9+

### App Store

<!-- TODO: Link to App Store / Mac App Store if published. Otherwise remove this section. -->

_Coming soon. App 1 of 10._

### Build from source

```bash
git clone https://github.com/tomasagustinrossi/PomodoroSense.git
cd PomodoroSense
open PomodoroSense.xcodeproj
```

Then in Xcode:

1. Select the **PomodoroSense** scheme.
2. Pick a destination (iOS Simulator, physical iPhone, or "My Mac").
3. `⌘ + R` to build and run.

> **Note**: Mirror Mode uses the local network. On iOS, you'll be prompted for Local Network permission the first time you open Sync Settings.

---

## Keyboard Shortcuts

### macOS

| Action | Shortcut |
|--------|----------|
| Play / Pause | `Space` or `Return` |
| Skip to previous session | `←` |
| Skip to next session | `→` |
| Back to presets | `↓` or `↑` |
| Close popup / dismiss | `Esc` |
| New preset | `⌘ + N` (when on presets screen) |
| Focus next control | `Tab` |
| Focus previous control | `Shift + Tab` |
| Activate focused control | `Return` |

### iOS

| Action | Gesture |
|--------|---------|
| Play / Pause | Tap the timer |
| Skip / Previous | Swipe on the session bar |
| Back to presets | Swipe up (portrait) or left (landscape) |
| Select a session | Long-press on the session bar, then drag |
| Open equalizer | Tap the sliders icon (top right) |

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| UI | **SwiftUI** (iOS + macOS) |
| 3D | **SceneKit** with custom extrusion for shop items |
| Audio | **AVFoundation** (procedural noise, binaural, ambient files) |
| Live Activities | **ActivityKit** (iOS 16.2+, Dynamic Island + Lock Screen) |
| Widgets | **WidgetKit** (Home Screen + macOS desktop) |
| P2P Sync | **Network.framework** (Bonjour + TLS-PSK, `_pomodorosense._tcp`) |
| Crypto | **CryptoKit** (SHA-256 for pairing key derivation) |
| Persistence | **UserDefaults** + **Keychain** (peer ID, pairing key) |
| Testing | **Swift Testing** (`@Test`, `@Suite`, `#expect`) |

**No external dependencies.** Zero pods, zero SPM packages. Everything ships with the SDK.

---

## Architecture

- **MVVM** with `@MainActor` ViewModels and pure SwiftUI views.
- **Balance files**: every tuning number lives in `*Balance.swift` files (audio, score, quality, sync). Change one file, the whole app rebalances.
- **Single source of truth**: `SessionStore` owns all persistent state (records, wallet, goals, reports). Everything else observes it.
- **Testable predicates**: Live Activity and widget logic is split into pure functions (`LiveActivityFilter`, `WidgetCommandDecision`) tested independently of UI.
- **P2P first**: Mirror Mode never touches a server. Key derivation, framing, connection lifecycle, and reconnection are all local.
- **Graceful degradation**: every feature has a fallback path. Audio missing? Silent mode. Live Activities disabled? Widget still works. Connection lost? Local session continues.

---

## Privacy

- **No accounts, no sign-in.**
- **No analytics, no telemetry, no crash reporting.**
- **No server.** Nothing leaves your devices.
- **Mirror Mode is peer-to-peer**: data is transmitted directly between paired devices over your local network, encrypted with TLS-PSK.
- **Pairing keys** are stored in the system Keychain and never leave the device.
- **Session records** are stored locally in `UserDefaults` and (optionally) compacted monthly to keep the app lightweight.

The only network permissions the app requests are:

- **Local Network** — required for Mirror Mode discovery via Bonjour.

---

## How PomodoroSense was built

PomodoroSense was not built by a team. It was built by **one developer with a clear vision, a stack of AIs, and a group of friends who cared enough to give honest feedback.**

The vision came first. Every decision in this app — from the spring animations to the balance of the reward loop, from the color palettes per soundscape to the way the Dynamic Island behaves under stress — started as a single sentence in a conversation. The AIs helped turn those sentences into code. The friends helped turn that code into something that *feels* premium.

### The vision

The author's primary language is **C#**. Swift, SwiftUI, ActivityKit, Network.framework, and the entire Apple ecosystem were new territory. The AIs were not a shortcut — they were a tutor, a translator, and a second pair of hands at the same time. Every pattern in this codebase (MVVM, `@MainActor`, property wrappers, phase management, Live Activity lifecycle) was learned while building.

But the vision was never delegated. What the app should feel like, what the reward loop should reward, what a session should *taste* like after 25 minutes of focus — those were decisions made by the author, in dialogue with himself, and later validated by the people who actually use the app. The AIs wrote the syntax. The author wrote the intent.

### The AI stack

- **DeepSeek** — the central engine. Architecture, most of the Swift implementation, refactors, and the day-to-day dialogue. If PomodoroSense has a "brain," it lives here.
- **Gemini** — planner and co-creator of the base. Visual design, color systems, structural decisions, and early review passes. The original skeleton of the app started as a Gemini conversation.
- **Claude** — surgical fixes, bug hunting, and code review. Every fix shipped in this repository was validated by tests before being merged.
- **ChatGPT** — images and visual assets. The rendered shop items, the icon compositions, and some of the screenshots in this README were generated with ChatGPT.

The human in the loop — the author — decided what to build, held the vision, tested on real devices, rejected broken code, and kept the AIs honest. Nothing was shipped without being run.

### The friends

An app that *works* is not the same as an app that *feels premium*. The gap between those two was closed by a small circle of friends who used early builds, complained about the right things, and celebrated the small wins with the same energy as the big ones.

They are the reason:

- The timer doesn't feel like a countdown — it feels like a companion.
- The reward popup lands at the exact moment it should.
- The shop previews rotate at the right speed.
- The dynamic island doesn't flicker on a real device.
- The balance between "challenging" and "rewarding" actually feels like a balance, not a spreadsheet.
- The soundscapes are mixed at a volume you can live with for hours.
- The animations have a *feel*, not just a duration.

Every piece of feedback — "esto se siente lento", "no entiendo para qué es esto", "me encanta cuando pasa X" — was written down, discussed, and translated into either a fix, a feature, or a deliberate decision to leave it alone. The friends did not write code. But the app would not exist in this form without them.

If you are one of those friends reading this: thank you. This app is as much yours as it is mine.

### A note on cost

This project was built on **free tiers**. Every model listed above was used through its free plan, with the single exception of Gemini, which was covered by a Google **student pack**. Total AI budget: zero. The real cost was time — and the return was a very steep learning curve compressed into a single project.

### A note on quality

Vibe coding is not a shortcut. Every line of code in this repository was prompted, reviewed, iterated, and — crucially — executed. The 35+ unit tests, the tested predicates for Live Activities and widget commands, and the balance files that centralize every tuning number are not the result of pressing a button. They are the result of thousands of small decisions made in dialogue with a stack of AIs — and of a developer who refused to ship anything he didn't understand.

PomodoroSense is proof that a single developer with the right tools, a clear vision, and honest friends can build something that feels native, tested, and carefully tuned — without a team, without a budget, and without pretending to already know the language he was writing it in.

If you are a C# developer wondering whether you can build for Apple platforms without a Swift background, this repository is the answer: yes, you can — as long as you are willing to read the docs, write the tests, learn the idioms one error at a time, and listen to the people who actually use what you build.

---

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you'd like to change.

### Development guidelines

- Keep the `*Balance.swift` files as the single source of truth for tuning numbers.
- All ViewModels stay `@MainActor`.
- New logic in Live Activity or Mirror Mode must be covered by tests in `PomodoroSenseTests/`.
- No external dependencies.
- Follow the HIG for motion and haptics.

### Reporting bugs

When opening an issue, please include:

- Platform (iOS / macOS) and version.
- Steps to reproduce.
- What you expected vs. what happened.
- Screenshots or screen recording if visual.

---

## Author

**Tomas Rossi**

- GitHub: [@tomasagustinrossi](https://github.com/tomasagustinrossi)
- 🇦🇷 Built in Argentina.

PomodoroSense is a personal project. It is not a company, not a startup, and not a product. It is a tool I built because I wanted it to exist, and I am sharing it because it might be useful to someone else.

---

## License

PomodoroSense is licensed under the **PolyForm Noncommercial License 1.0.0**.

[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue)](https://polyformproject.org/licenses/noncommercial/1.0.0/)

### Why this license

PolyForm Noncommercial is a modern source-available license designed specifically for software. Unlike Creative Commons licenses, it is unambiguous about code, patents, and linking, and it is enforceable in court. It was chosen because it is the cleanest way to express two things:

1. **You can read, run, learn from, and adapt this code.**
2. **You cannot sell it, and you cannot publish it on the App Store.**

### What you can do

- ✅ **Read and learn from the code** — every file, every comment, every test.
- ✅ **Clone and run it locally** on your own devices.
- ✅ **Fork it for personal use** — modify it, break it, fix it, rebuild it.
- ✅ **Share it with friends** who want to run it on their own devices.
- ✅ **Contribute back** through pull requests.
- ✅ **Use it in education, research, charity, or government** — those are explicitly noncommercial uses under PolyForm.

### What you cannot do

- ❌ **Sell PomodoroSense, or a derivative of it**, in any form.
- ❌ **Publish it on the App Store, Mac App Store, Google Play, Microsoft Store, Steam, or any other commercial app distribution platform.** This applies even if you publish it for free — the restriction is about the platform, not the price.
- ❌ **Use the code in any commercial product or service.**
- ❌ **Remove the copyright notice or the license file.**
- ❌ **Sublicense or transfer your rights to someone else.**

If you want to publish a product based on this work, you must obtain **prior written permission from the author** and publish it under a substantially different product identity.

### Required notice

Per the PolyForm license, any distribution of PomodoroSense or of a derivative work must include a copy of the license and the following notice:

> **PomodoroSense** — Copyright (c) 2026 Tomas Rossi.
> Licensed under the PolyForm Noncommercial License 1.0.0.
> Source: https://github.com/tomasagustinrossi/PomodoroSense

### Full license text

The full text of the PolyForm Noncommercial License 1.0.0 — including the additional App Store restriction added by the author — is in [LICENSE](LICENSE), and the canonical version is at [polyformproject.org/licenses/noncommercial/1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/).

---

## Acknowledgments

- Inspired by the original Pomodoro Technique by Francesco Cirillo.
- Audio design borrows ideas from Paul Kellet's pink noise filter and the broader ambient audio community.
- **Built with AI, for humans.** PomodoroSense is a vibe-coded project. DeepSeek, Gemini, Claude, and ChatGPT were not tools I used — they were the team I built it with. The full story is in [How PomodoroSense was built](#how-pomodorosense-was-built).
- Built with love in Argentina.

<p align="center">
  <sub>Made with ❤️, a lot of focus sessions, and a stack of AIs.</sub>
</p>
