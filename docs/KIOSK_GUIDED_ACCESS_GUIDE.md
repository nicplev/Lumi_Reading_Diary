# Locking Down the Lumi Class Scan-In Kiosk
### A 5-minute setup guide for teachers

The kiosk ("Class scan-in") lets students scan their own books on a shared
iPad — but it runs **inside your teacher account**. Two locks keep students
where they belong. Use **both** on any device students touch:

| Lock | What it stops |
|---|---|
| **1 · Lumi exit PIN** | A student tapping ✕ and landing in your teacher account |
| **2 · Guided Access** (iPad) / **App pinning** (Android) | A student leaving the Lumi app altogether — home screen, other apps, notifications |

> **Every lesson, in 20 seconds:** open Lumi → Class tab → **Class scan-in**
> → triple-click the iPad's top (or Home) button → **Start**. Prop the iPad on
> a stand (the kiosk works in landscape) and leave it plugged in.

---

## Lock 1 — the Lumi exit PIN (inside the app)

**Where the kiosk lives:** Lumi teacher app → **Class** tab → the white
**"Class scan-in"** button (tablet icon, bottom-right).

**First time on each iPad:** when the kiosk opens, Lumi asks
**"Lock the kiosk with a PIN?"** → tap **Set PIN** and enter 4 digits twice.
(If you tapped *Not now*, use the **lock button 🔒** in the kiosk's top bar
any time.)

**Day to day:**
- Leaving the kiosk (the ✕ button, or the system back gesture) now asks for
  the PIN.
- **Change or remove the PIN:** tap 🔒 in the kiosk top bar — it always asks
  for the current PIN first.
- **Forgot the PIN?** On the exit prompt tap *Forgot PIN?* → **Sign Out**.
  That wipes the PIN and returns to the login screen — you'll need your
  password to sign back in, so it's useless to a student.

The PIN is per-teacher, per-device: set it once on each classroom iPad you use.

**What students see:** a "Find your name" roster — each child taps their own
photo, scans their books, and the kiosk returns to the roster (automatically
after 30 seconds of inactivity, ready for the next child).

---

## Lock 2 (iPad) — Guided Access

Guided Access locks the whole iPad to the Lumi app: no home screen, no app
switcher, no notifications.

### One-time setup (per iPad, ~2 minutes)

1. Open **Settings → Accessibility → Guided Access** and turn it **on**.
2. Tap **Passcode Settings → Set Guided Access Passcode** and choose a
   6-digit code. Make it different from the Lumi exit PIN, and keep it where
   students won't see it (class folder, not a sticky note on the iPad).
   - Optional: enable **Face ID / Touch ID** here so *you* can end sessions
     without typing the code.
3. Still in Guided Access settings, tap **Display Auto-Lock** and pick a
   long value so the screen doesn't sleep mid-lesson.

### Every lesson

1. Open Lumi and go to the kiosk (Class tab → **Class scan-in**).
2. **Triple-click the top button** (iPads with Face ID) or the **Home
   button** (older iPads).
   - If a menu pops up listing accessibility options, tap **Guided Access**.
3. Tap **Start** (top-right). Done — the iPad is locked to Lumi.
   - Before Start you can also tap **Options** (bottom-left) to switch off
     the **volume buttons**; leave **Touch** on and **don't** set a
     **Time Limit** for kiosk use.

### Ending the session

Triple-click the same button → enter the **Guided Access passcode** → tap
**End** (top-left). With Face ID enabled, **double-click** and glance instead.

---

## Lock 2 (Android tablet) — App pinning

1. One-time: **Settings → Security & privacy → More security & privacy →
   App pinning** → turn on, and enable **"Ask for PIN before unpinning."**
   *(Samsung: Settings → Biometrics and security → Other security settings →
   **Pin windows**.)*
2. Every lesson: open Lumi's kiosk → open **Recents** (swipe up from the
   bottom and hold) → tap the **Lumi icon at the top of its card** → **Pin**.
3. To unpin: swipe up and hold (or hold **Back + Recents** on button
   navigation) → enter the device PIN.

---

## Classroom tips

- **Power:** keep the iPad plugged in; scanning all lesson drains batteries.
- **The two codes are different on purpose:** the Lumi PIN guards your
  account *inside* the app; the Guided Access passcode guards the *device*.
- **Relief teacher day:** the kiosk runs on the signed-in teacher's account.
  If it must run under someone else, they sign in as themselves and set
  their own PIN (each teacher's PIN is their own).

## If something goes wrong

| Problem | Fix |
|---|---|
| Kiosk shows a spinner / "Could not load students" | The session has usually expired. End Guided Access, sign into Lumi again, reopen the kiosk. |
| Forgot the **Lumi exit PIN** | Exit prompt → *Forgot PIN?* → Sign Out → sign back in with your password and set a new PIN. |
| Forgot the **Guided Access passcode** | If Face ID was enabled: double-click and glance to end. Otherwise force-restart the iPad (hold top button + either volume button, slide to power off — on stubborn models hold both until the Apple logo). Reset the passcode in Settings afterwards. |
| Triple-click does nothing | Settings → Accessibility → Guided Access — confirm it's on. Clicks must be quick. |
| A student got out anyway | Note how and tell your Lumi contact — that's exactly the beta feedback we need. |

---

*Steps verified July 2026 against Apple's Guided Access documentation
(support.apple.com/111795 and the iPad User Guide) and Google/Samsung
app-pinning documentation, and against the Lumi kiosk code (exit PIN offer,
🔒 management, forgot-PIN sign-out, 30-second idle return).*
