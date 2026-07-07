# Classroom Kiosk — Lock-Down Guide (teacher one-pager)

The Lumi kiosk ("Scan-in") runs inside **your teacher account**. Two layers keep
students from wandering out of it into your account — use **both** on any iPad
students touch:

## Layer 1 — Lumi exit PIN (in the app)

1. Open the kiosk (Class → Scan-in). The first time, Lumi offers **"Lock the
   kiosk with a PIN?"** → tap **Set PIN** and choose 4 digits.
2. Set or change it any time with the **lock button (🔒)** in the kiosk's top
   bar. Changing or removing the PIN always asks for the current PIN first.
3. With the PIN set, leaving the kiosk (the ✕ button or system back) requires
   the PIN.
4. **Forgot the PIN?** Tap *Forgot PIN?* on the exit prompt → **Sign out**. This
   removes the PIN and returns to the login screen — you'll need your password
   to sign back in, so a student can't use it to get anywhere.

## Layer 2 — iOS Guided Access (locks the whole iPad to Lumi)

One-time setup (per iPad):
1. **Settings → Accessibility → Guided Access** → turn **ON**.
2. Tap **Passcode Settings → Set Guided Access Passcode** — pick a code
   students don't know (not the Lumi exit PIN; write it in the class folder).
3. Optional: turn on **Accessibility Shortcut** so a triple-click starts it.

Every lesson:
1. Open Lumi and go to the kiosk screen.
2. **Triple-click the top (or home) button** → tap **Start**. The iPad is now
   locked to Lumi — the home gesture, app switcher and notifications are off.
3. To end: triple-click again → enter the **Guided Access passcode** → **End**.

> Android iPads-equivalent: use **screen pinning** (Settings → Security → App
> pinning), then pin Lumi; unpinning asks for the device PIN.

## If something goes wrong

- **Kiosk stopped working mid-lesson** (spinner, "couldn't load students"):
  the teacher session has usually expired — end Guided Access, sign back into
  Lumi, reopen the kiosk.
- **iPad frozen in Guided Access:** triple-click → passcode → End. If the
  passcode is lost, force-restart the iPad (hold top button + a volume button).
- **Student got out anyway?** Tell your Lumi contact — that's exactly the kind
  of beta feedback we need.
