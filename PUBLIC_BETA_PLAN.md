# Lumi Public Beta Plan

This document outlines the plan to get the Lumi application ready for a public beta release. The plan is divided into three phases: Security and Stability, Feature Completion and UX Refinement, and Beta Preparation and Deployment.

## Phase 1: Security and Stability

This phase focuses on addressing critical security vulnerabilities and ensuring the application is stable.

### Task 1.1: Fix Role-Based Access Control (RBAC)

**Priority:** Highest

**Problem:** The `_requireRole` function in `lib/core/routing/app_router.dart` is incomplete, which creates a critical security vulnerability. Users may be able to access routes and data they are not authorized to see.

**Plan:**
1.  **Investigate `_requireRole`:** Fully understand the current implementation and its shortcomings.
2.  **Implement Robust Role Checking:** Implement logic to correctly check the current user's role against the required role for the route. This will likely involve fetching the user's role from a `UserState` or similar provider.
3.  **Testing:** Write unit and widget tests to verify that the RBAC logic is working correctly for all user roles (parent, teacher, admin) and for all protected routes.

### Task 1.2: Comprehensive Testing of Core Functionality

**Priority:** High

**Problem:** The current test suite is minimal. Core business logic in both the Flutter app and Firebase Functions is not adequately tested.

**Plan:**
1.  **Flutter App Testing:**
    *   Write unit tests for all ViewModels/Notifiers to ensure business logic is correct.
    *   Write widget tests for critical UI components, especially those with complex state.
    *   Write integration tests for key user flows (e.g., logging a reading, creating a student, generating a report).
2.  **Firebase Functions Testing:**
    *   Set up a test environment for the Firebase Functions.
    *   Write unit tests for individual functions (e.g., `aggregateStudentStats`, `sendReadingReminders`).

### Task 1.3: Firestore Rules Review and Testing

**Priority:** High

**Problem:** Firestore rules can be complex and are a critical part of the security model. They need to be reviewed and tested to prevent unauthorized data access.

**Plan:**
1.  **Review existing rules:** Analyze `firestore.rules` to ensure they correctly enforce the application's access control policies.
2.  **Write Firestore rules tests:** Use the Firebase Local Emulator Suite to write and run tests for the Firestore rules.

## Phase 2: Feature Completion and UX Refinement

This phase focuses on improving the user experience and completing any unfinished features.

### Task 2.1: UI/UX Polish

**Priority:** Medium

**Problem:** A polished and intuitive UI is essential for a successful public beta.

**Plan:**
1.  **Conduct a UI/UX review:** Go through every screen in the app for all user roles and identify areas for improvement.
2.  **Create a design system/style guide:** If one doesn't exist, create a simple one to ensure consistency across the app. The file `DESIGN_SYSTEM.md` suggests this has been considered.
3.  **Implement UI improvements:** Address the issues identified in the review.

### Task 2.2: Complete Incomplete Features

**Priority:** Medium

**Problem:** There may be features that are partially implemented or missing.

**Plan:**
1.  **Feature audit:** Create a list of all intended features and their current status.
2.  **Prioritize feature development:** Decide which features are essential for the public beta.
3.  **Implement and test missing features.**

### Task 2.3: Onboarding Flow

**Priority:** Medium

**Problem:** A smooth onboarding experience is crucial for user retention.

**Plan:**
1.  **Review the current onboarding flow:** Identify any pain points or areas of confusion.
2.  **Design and implement improvements:** This could include adding tutorials, simplifying forms, or providing clearer instructions.

## Phase 3: Beta Preparation and Deployment

This phase focuses on the final steps before releasing the app to beta testers.

### Task 3.1: Setup Analytics and Crash Reporting

**Priority:** High

**Problem:** We need to be able to monitor the app's performance and stability during the beta.

**Plan:**
1.  **Integrate Firebase Crashlytics:** The project seems to have the dependency, but we need to ensure it's properly configured.
2.  **Integrate Firebase Analytics:** To track user engagement and feature usage.

### Task 3.2: Beta Deployment Strategy

**Priority:** Medium

**Plan:**
1.  **Use Firebase App Distribution:** To easily distribute the beta app to a closed group of testers.
2.  **Create a testing group:** Recruit a diverse group of users to test the app.

### Task 3.3: Feedback Mechanism

**Priority:** Medium

**Plan:**
1.  **Implement an in-app feedback tool:** This will allow beta testers to easily report bugs and provide feedback. There are several third-party libraries that can be used for this.
