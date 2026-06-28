# App Privacy labels — App Store Connect answers

Copy these answers into **App Store Connect → your app → App Privacy**. They are
derived from the app's actual data flows (Firebase Auth/Firestore/Storage/
Messaging/Analytics/Crashlytics) and must stay in sync with
`ios/Runner/PrivacyInfo.xcprivacy`.

> Summary: Lumi collects account, child reading, and diagnostic data to run the
> service. It does **not** use data for third-party advertising and does **not
> track** users across other companies' apps or websites. No data is "Used to
> Track You".

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
| User ID | Firebase account UID | App Functionality, Analytics |
| Product Interaction | In-app events (e.g. reading logged, badge earned) — production builds only | Analytics |
| Crash Data | Crash/exception reports — production builds only | App Functionality |
| Performance Data | Diagnostics/performance — production builds only | App Functionality |

## Data Not Linked to You
**None declared.** (Analytics/crash data is associated with the Firebase UID, so
it is declared as Linked above.)

## Notes for the questionnaire
- **Sensitive/children's data:** Lumi is a children's reading product used *about*
  children by schools and parents/carers. Data is collected under the school
  relationship; the school is responsible for parental consent. Reflect this in
  the app's age rating and the "Made for Kids"/education positioning as
  appropriate.
- **Third-party book look-ups:** ISBN/title is sent to Google Books / Open
  Library to fetch covers and titles. **No student data** is sent, so it does not
  add a collected-data category.
- **No purchases in-app:** payment is arranged off-app via schools (book packs);
  there is no In-App Purchase SDK, so no "Purchases" data type.
- Keep this file, the App Store Connect labels, and `PrivacyInfo.xcprivacy`
  identical. If you add/remove a data flow, update all three.
