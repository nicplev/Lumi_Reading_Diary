# App Privacy labels — App Store Connect answers

Copy these answers into **App Store Connect → your app → App Privacy**. They are
derived from the app's actual data flows (Firebase Auth/Firestore/Storage/
Messaging/Analytics/Crashlytics) and must stay in sync with
`ios/Runner/PrivacyInfo.xcprivacy`.

> Summary: Lumi collects account and child reading data to run the service.
> Optional product analytics and crash diagnostics are **off by default** and
> are collected only after an adult account holder opts in on that device. Lumi
> does **not** use data for third-party advertising and does **not track** users
> across other companies' apps or websites. No data is "Used to Track You".

## Data Used to Track You
**None.** (`NSPrivacyTracking = false`; no advertising or attribution SDKs.)

## Data Linked to You
For each type below: **Linked to identity = Yes**, **Used for tracking = No**.

| Data type (App Store category) | What it is in Lumi | Purpose(s) |
|---|---|---|
| Name | Account holder's name; a child's first/last name entered by the school/parent | App Functionality |
| Email Address | Optional account email (sign-in, recovery, contact) | App Functionality |
| Phone Number | Parent account phone (sign-in); optional teacher phone | App Functionality |
| Photos or Videos | Optional photos attached to a reading log; optional profile photos | App Functionality |
| Audio Data | Optional short "comprehension" voice recording of a child (school-gated) | App Functionality |
| Other User Content | Reading logs, book titles, notes, teacher⇄parent comments | App Functionality |
| User ID | Firebase account UID | App Functionality |
| Product Interaction | Optional pseudonymous feature-use event names; no Lumi UID, child identity, book title, recording, notes, reading duration/count, feeling, badge type or streak value | Analytics |
| Crash Data | Optional pseudonymous crash/exception reports; no Lumi UID is attached | App Functionality |
| Performance Data | Optional app/device diagnostics associated with a Crashlytics installation, not a Lumi account | App Functionality |

## Data Not Linked to You
**None declared.** Although Lumi no longer attaches a Firebase account UID to
optional analytics or crash reports, Firebase assigns pseudonymous Analytics
app-instance and Crashlytics installation identifiers. Apple treats data tied
to a device identifier as linked to identity, so the conservative declaration
is "Linked to You".

## Notes for the questionnaire
- **Sensitive/children's data:** Lumi is a children's reading product used *about*
  children by schools and parents/carers. Data is collected under the school
  relationship; the school is responsible for parental consent. Reflect this in
  the app's age rating and the "Made for Kids"/education positioning as
  appropriate.
- **Optional diagnostics controls:** Both switches are off on first launch and
  live in **Settings → Account → Privacy & diagnostics** for parent/carer and
  staff accounts. Withdrawing Analytics disables collection, removes any legacy
  UID/property and resets the local Analytics app-instance ID. Withdrawing crash
  reports disables collection, clears the user identifier and deletes unsent
  reports. Android and iOS native defaults are also disabled so neither SDK can
  send before Flutter loads the saved choice.
- **Third-party book look-ups:** ISBN/title is sent to Google Books / Open
  Library to fetch covers and titles. **No student data** is sent, so it does not
  add a collected-data category.
- **No purchases in-app:** payment is arranged off-app via schools (book packs);
  there is no In-App Purchase SDK, so no "Purchases" data type.
- Keep this file, the App Store Connect labels, and `PrivacyInfo.xcprivacy`
  identical. The questionnaire must still declare optional data collection.
  If you add/remove a data flow, update all three.
