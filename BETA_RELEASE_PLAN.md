# Lumi Reading Diary - Public Beta Release Plan

**Version:** 1.0.0-beta
**Created:** December 1, 2025
**Target Release:** January 2026
**Document Status:** Active

---

## Overview

This document outlines the comprehensive plan to release Lumi Reading Diary as a public beta. The plan is organized into 4 phases spanning approximately 4 weeks.

### Current State

- **Core Features:** 100% complete (35 screens, all roles)
- **Backend:** 100% complete (Firebase + 6 Cloud Functions)
- **UI/UX:** 100% complete (Lumi Design System migration)
- **Testing:** 40% complete (models tested, integration tests needed)
- **App Store Readiness:** 30% complete

### Beta Goals

1. **Quality Validation:** Confirm app stability with real users
2. **Feature Feedback:** Gather usage data and user feedback
3. **Performance Baseline:** Establish performance metrics
4. **Bug Discovery:** Identify and fix edge cases
5. **Onboarding Optimization:** Refine user flows

---

## Phase 1: Foundation (Week 1)

### 1.1 Cloud Functions Deployment

**Objective:** Verify all server-side functionality works correctly

| Task | Owner | Status | Priority |
|------|-------|--------|----------|
| Deploy Cloud Functions to Firebase | Dev | Pending | P0 |
| Test `aggregateStudentStats` trigger | Dev | Pending | P0 |
| Test `sendReadingReminders` scheduled job | Dev | Pending | P0 |
| Test `detectAchievements` trigger | Dev | Pending | P0 |
| Test `validateReadingLog` validation | Dev | Pending | P0 |
| Test `cleanupExpiredLinkCodes` scheduled job | Dev | Pending | P1 |
| Test `updateClassStats` trigger | Dev | Pending | P1 |
| Set up Cloud Function monitoring alerts | Dev | Pending | P1 |

**Deployment Commands:**
```bash
cd functions
npm install
npm run build
firebase deploy --only functions
```

### 1.2 Legal & Compliance

**Objective:** Ensure legal requirements are met for app store submission

| Task | Owner | Status | Priority |
|------|-------|--------|----------|
| Draft Privacy Policy | Legal/PM | Pending | P0 |
| Draft Terms of Service | Legal/PM | Pending | P0 |
| Review COPPA compliance | Legal | Pending | P0 |
| Create Data Retention Policy | PM | Pending | P1 |
| Create Cookie/Tracking Policy | PM | Pending | P1 |
| Add privacy policy link to app | Dev | Pending | P0 |
| Add terms link to app | Dev | Pending | P0 |

**Key COPPA Considerations:**
- Parental consent for children under 13
- Data minimization
- Secure data handling
- Right to deletion

### 1.3 App Store Assets

**Objective:** Create all required assets for iOS App Store and Google Play

#### iOS Assets Required

| Asset | Dimensions | Status |
|-------|------------|--------|
| App Icon | 1024x1024 (no alpha) | Pending |
| iPhone 6.7" Screenshots | 1290x2796 | Pending |
| iPhone 6.5" Screenshots | 1242x2688 | Pending |
| iPhone 5.5" Screenshots | 1242x2208 | Pending |
| iPad Pro 12.9" Screenshots | 2048x2732 | Pending |
| App Preview Video (optional) | 1920x1080 | Pending |

#### Android Assets Required

| Asset | Dimensions | Status |
|-------|------------|--------|
| App Icon | 512x512 | Pending |
| Feature Graphic | 1024x500 | Pending |
| Phone Screenshots | 1080x1920 | Pending |
| Tablet 7" Screenshots | 1200x1920 | Pending |
| Tablet 10" Screenshots | 1600x2560 | Pending |

### 1.4 App Store Configuration

**Objective:** Set up app store accounts and initial configuration

| Task | Owner | Status | Priority |
|------|-------|--------|----------|
| Verify Apple Developer account | PM | Pending | P0 |
| Verify Google Play Console account | PM | Pending | P0 |
| Create App Store Connect app entry | Dev | Pending | P0 |
| Create Play Console app entry | Dev | Pending | P0 |
| Configure app signing (iOS) | Dev | Pending | P0 |
| Configure app signing (Android) | Dev | Pending | P0 |
| Set up internal testing track (Play) | Dev | Pending | P0 |
| Set up TestFlight | Dev | Pending | P0 |

---

## Phase 2: Testing & Quality (Week 2)

### 2.1 Device Testing Matrix

**Objective:** Verify app works on range of devices

#### iOS Test Devices

| Device | iOS Version | Status | Notes |
|--------|-------------|--------|-------|
| iPhone 15 Pro | iOS 17.x | Pending | Primary test |
| iPhone 13 | iOS 17.x | Pending | Mid-range |
| iPhone SE (3rd gen) | iOS 16.x | Pending | Small screen |
| iPad Pro 12.9" | iPadOS 17.x | Pending | Tablet |
| iPhone 11 | iOS 15.x | Pending | Older device |

#### Android Test Devices

| Device | Android Version | Status | Notes |
|--------|-----------------|--------|-------|
| Pixel 8 | Android 14 | Pending | Reference device |
| Samsung Galaxy S23 | Android 14 | Pending | Popular flagship |
| Samsung Galaxy A54 | Android 13 | Pending | Mid-range |
| OnePlus Nord | Android 12 | Pending | Budget device |
| Samsung Tab S9 | Android 14 | Pending | Tablet |

### 2.2 Critical Flow Testing

**Objective:** Verify all critical user journeys work correctly

#### Parent Critical Flows

| Flow | Steps | Status | Bugs Found |
|------|-------|--------|------------|
| Registration | Register > Verify email > Link student > Complete | Pending | - |
| First Reading Log | Open app > Select child > Log reading > Save | Pending | - |
| View History | Open history > Switch periods > View chart | Pending | - |
| Achievements | Open achievements > Filter > View details | Pending | - |
| Offline Log | Disable network > Log reading > Re-enable > Verify sync | Pending | - |
| Goal Setting | Open goals > Create goal > Track progress | Pending | - |
| Push Notification | Receive reminder > Tap > Navigate to log | Pending | - |

#### Teacher Critical Flows

| Flow | Steps | Status | Bugs Found |
|------|-------|--------|------------|
| Registration | Register with school code > Complete profile | Pending | - |
| Create Allocation | Select class > Choose type > Set target > Assign | Pending | - |
| View Class | Open class > Sort students > View individual | Pending | - |
| Generate Report | Select class > Set date range > Export CSV | Pending | - |
| Reading Groups | Create group > Drag students > Save | Pending | - |

#### Admin Critical Flows

| Flow | Steps | Status | Bugs Found |
|------|-------|--------|------------|
| User Management | View users > Add teacher > Assign to class | Pending | - |
| Student Import | Upload CSV > Preview > Confirm import | Pending | - |
| Parent Linking | Select student > Generate code > Copy code | Pending | - |
| Analytics | View dashboard > Filter by date > Drill down | Pending | - |

### 2.3 Integration Test Development

**Objective:** Create automated integration tests for critical paths

| Test Suite | Coverage | Priority | Status |
|------------|----------|----------|--------|
| Auth Flow Tests | Login, Register, Logout | P0 | Pending |
| Reading Log Tests | Create, Read, Update, Offline | P0 | Pending |
| Allocation Tests | Create, Assign, View | P1 | Pending |
| Sync Tests | Offline create, Online sync | P0 | Pending |
| Navigation Tests | Route guards, Deep links | P1 | Pending |

### 2.4 Performance Testing

**Objective:** Establish performance baselines

| Metric | Target | Current | Status |
|--------|--------|---------|--------|
| Cold Start (iOS) | <3s | Unknown | Pending |
| Cold Start (Android) | <4s | Unknown | Pending |
| Screen Transition | <300ms | Unknown | Pending |
| Reading Log Save | <1s | Unknown | Pending |
| History Load (30 days) | <2s | Unknown | Pending |
| Memory Usage | <200MB | Unknown | Pending |

---

## Phase 3: Beta Preparation (Week 3)

### 3.1 Beta Tester Recruitment

**Objective:** Assemble diverse beta testing group

| Tester Group | Target Count | Recruited | Status |
|--------------|--------------|-----------|--------|
| Parents | 20-30 | 0 | Pending |
| Teachers | 10-15 | 0 | Pending |
| School Admins | 3-5 | 0 | Pending |
| Internal Team | 5-10 | 0 | Pending |
| **Total** | **40-60** | **0** | Pending |

**Recruitment Criteria:**
- Mix of iOS and Android users
- Range of device ages (new and older)
- Different school sizes
- Various technical skill levels

### 3.2 Feedback Collection Setup

**Objective:** Prepare mechanisms for collecting beta feedback

| Channel | Purpose | Setup Status |
|---------|---------|--------------|
| In-app Feedback | Bug reports, suggestions | Pending |
| Beta Slack/Discord | Discussion, questions | Pending |
| Survey Forms | Structured feedback | Pending |
| Crash Reports | Automated via Crashlytics | Ready |
| Analytics Events | Usage patterns | Partial |

### 3.3 Documentation

**Objective:** Create user-facing documentation

| Document | Audience | Status |
|----------|----------|--------|
| Parent Quick Start Guide | Parents | Pending |
| Teacher Quick Start Guide | Teachers | Pending |
| Admin Setup Guide | School Admins | Pending |
| FAQ | All Users | Pending |
| Troubleshooting Guide | Support | Pending |

### 3.4 Support Preparation

**Objective:** Prepare support infrastructure

| Item | Status | Notes |
|------|--------|-------|
| Support email configured | Pending | support@lumiapp.com |
| Issue tracking system | Pending | GitHub Issues or similar |
| Response templates | Pending | Common questions |
| Escalation process | Pending | Critical bugs |
| Bug triage criteria | Pending | P0-P3 definitions |

---

## Phase 4: Beta Launch (Week 4)

### 4.1 Build & Deploy

**Objective:** Create and distribute beta builds

#### iOS Deployment

| Step | Command/Action | Status |
|------|----------------|--------|
| Increment version | Update pubspec.yaml to 1.0.0+1 | Pending |
| Archive build | `flutter build ios --release` | Pending |
| Upload to App Store Connect | Xcode Organizer | Pending |
| Submit for TestFlight review | App Store Connect | Pending |
| Distribute to testers | Add testers in TestFlight | Pending |

#### Android Deployment

| Step | Command/Action | Status |
|------|----------------|--------|
| Create signed APK/AAB | `flutter build appbundle --release` | Pending |
| Upload to Play Console | Internal Testing Track | Pending |
| Add testers | Play Console tester list | Pending |
| Enable internal distribution | Set to Available | Pending |

### 4.2 Launch Checklist

**Pre-Launch (Day -1):**

- [ ] All P0 bugs resolved
- [ ] Cloud Functions deployed and verified
- [ ] Legal documents published
- [ ] App store listings complete
- [ ] Beta tester list finalized
- [ ] Support channels ready
- [ ] Monitoring dashboards configured

**Launch Day (Day 0):**

- [ ] Deploy iOS TestFlight build
- [ ] Deploy Android Internal Testing build
- [ ] Send invite emails to testers
- [ ] Post welcome message in feedback channel
- [ ] Monitor crash reports
- [ ] Monitor support channels

**Post-Launch (Day 1-7):**

- [ ] Daily crash report review
- [ ] Respond to critical feedback within 24h
- [ ] Collect and triage bugs
- [ ] Release patch if critical issues found
- [ ] Send Day 3 feedback survey
- [ ] Send Day 7 feedback survey

### 4.3 Success Criteria

**Week 1 Success Metrics:**

| Metric | Target | Notes |
|--------|--------|-------|
| Active Testers | >30 | Users who completed onboarding |
| Crash-free Rate | >99% | Crashlytics metric |
| Daily Active Users | >50% of testers | Firebase Analytics |
| Critical Bugs | <3 | P0 issues |
| Reading Logs Created | >100 | Adoption indicator |

### 4.4 Rollback Plan

**If critical issues are discovered:**

1. **Severity Assessment**
   - P0: Data loss, security breach, total crash
   - P1: Major feature broken, UX blocking
   - P2: Minor bugs, cosmetic issues

2. **P0 Response Protocol**
   - Immediately disable app distribution
   - Notify all testers via email
   - Fix and re-deploy within 24h
   - Post-mortem within 48h

3. **P1 Response Protocol**
   - Continue distribution
   - Fix in next build (within 72h)
   - Communicate workaround to testers

---

## Phase 5: Beta Iteration (Weeks 5-8)

### 5.1 Feedback Processing

| Activity | Frequency | Output |
|----------|-----------|--------|
| Bug triage | Daily | Prioritized backlog |
| Feature requests | Weekly | Feature consideration list |
| UX feedback | Weekly | UX improvement tickets |
| Performance review | Weekly | Performance tickets |

### 5.2 Release Cadence

| Release | Timeline | Focus |
|---------|----------|-------|
| Beta 1.0.0 | Week 4 | Initial release |
| Beta 1.0.1 | Week 5 | Critical bug fixes |
| Beta 1.0.2 | Week 6 | Additional fixes + minor improvements |
| Beta 1.1.0 | Week 7 | Feature refinements |
| RC 1.0.0 | Week 8 | Release candidate |

### 5.3 Go/No-Go Decision (End of Week 8)

**Public Release Criteria:**

| Criteria | Threshold | Status |
|----------|-----------|--------|
| Crash-free rate | >99.5% | Pending |
| Critical bugs open | 0 | Pending |
| Core flows working | 100% | Pending |
| User satisfaction (survey) | >4.0/5.0 | Pending |
| Performance targets met | 100% | Pending |
| Legal review complete | Yes | Pending |
| App store approval | Yes | Pending |

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| App store rejection | Medium | High | Follow guidelines strictly |
| Critical bug in production | Medium | High | Extensive testing, rollback plan |
| Low beta engagement | Medium | Medium | Proactive outreach, incentives |
| Scaling issues | Low | High | Firebase auto-scaling |
| Security vulnerability | Low | Critical | Security audit before launch |
| Negative feedback | Medium | Medium | Quick response, iteration |

---

## Resource Requirements

### Personnel

| Role | Allocation | Duration |
|------|------------|----------|
| Flutter Developer | Full-time | 4 weeks |
| QA Tester | Part-time | 4 weeks |
| Product Manager | Part-time | 4 weeks |
| Designer | As needed | 2 weeks |

### Infrastructure

| Item | Cost Estimate |
|------|---------------|
| Apple Developer Account | $99/year |
| Google Play Console | $25 one-time |
| Firebase (Blaze plan) | ~$50-100/month |
| Test devices (if needed) | Variable |

---

## Appendix A: Bug Priority Definitions

| Priority | Definition | Response Time | Fix Timeline |
|----------|------------|---------------|--------------|
| P0 | Critical - App unusable, data loss, security | Immediate | <24h |
| P1 | Major - Core feature broken | <4h | <72h |
| P2 | Moderate - Feature degraded | <24h | Next release |
| P3 | Minor - Cosmetic, edge case | <48h | Backlog |

## Appendix B: Key Contacts

| Role | Contact | Notes |
|------|---------|-------|
| Technical Lead | TBD | Code decisions |
| Product Owner | TBD | Feature decisions |
| QA Lead | TBD | Testing coordination |
| Support Lead | TBD | User issues |

---

*This plan is a living document and will be updated as the beta progresses.*
