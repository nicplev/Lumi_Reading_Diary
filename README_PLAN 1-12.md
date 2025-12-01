# Lumi Reading Diary - Beta Launch Plan Summary

**Date:** December 1, 2025
**Target Launch:** January 2026
**Status:** Planning Complete

---

## What is Lumi?

Lumi is a digital reading diary app for schools that helps:
- **Parents** log and track their child's daily reading
- **Teachers** assign reading and monitor class progress
- **School Admins** manage users and view school-wide analytics

---

## Current State: 85-90% Ready

| Area | Status |
|------|--------|
| All Features | Done |
| UI Design | Done |
| Backend | Done |
| Security | Done |
| Testing | 40% |
| App Store | 30% |

---

## The 4-Week Plan

### Week 1: Foundation

**Goal:** Set up operational requirements

1. **Deploy Cloud Functions** - 6 backend functions ready to deploy
2. **Create Legal Documents** - Privacy Policy, Terms of Service
3. **Prepare App Store Assets** - Icons, screenshots, descriptions
4. **Configure App Stores** - TestFlight + Play Console setup

### Week 2: Quality Assurance

**Goal:** Verify everything works

1. **Test on Real Devices** - iOS (5 devices) + Android (5 devices)
2. **Run Critical User Flows** - Registration, logging, syncing
3. **Performance Check** - App startup < 3s, smooth transitions
4. **Fix Any Bugs Found** - Prioritize by severity

### Week 3: Beta Preparation

**Goal:** Get ready for testers

1. **Recruit Beta Testers** - 40-60 users (parents, teachers, admins)
2. **Set Up Feedback Channels** - In-app feedback, support email
3. **Write User Guides** - Quick start guides for each role
4. **Prepare Support Process** - How to handle issues

### Week 4: Launch Beta

**Goal:** Release to testers

1. **Build & Deploy** - Upload to TestFlight and Play Console
2. **Invite Testers** - Send access to all beta testers
3. **Monitor** - Watch crash reports, respond to feedback
4. **Iterate** - Fix issues quickly, release updates

---

## Key Milestones

| Week | Milestone | Success Criteria |
|------|-----------|------------------|
| 1 | Foundation Complete | Functions deployed, legal docs ready |
| 2 | QA Complete | All critical flows tested, bugs fixed |
| 3 | Beta Ready | Testers recruited, channels set up |
| 4 | Beta Live | Apps distributed, testers active |

---

## What Needs to Be Done

### Must Have (P0)

- [ ] Deploy 6 Cloud Functions to Firebase
- [ ] Write Privacy Policy (COPPA compliant)
- [ ] Write Terms of Service
- [ ] Create app icons (iOS: 1024x1024, Android: 512x512)
- [ ] Take screenshots for app stores
- [ ] Set up TestFlight for iOS beta
- [ ] Set up Play Console internal testing
- [ ] Test on 5+ real devices each platform

### Should Have (P1)

- [ ] Integration tests for critical paths
- [ ] Performance baseline measurements
- [ ] User documentation (quick start guides)
- [ ] Feedback collection system
- [ ] Support email and process

### Nice to Have (P2)

- [ ] App preview videos
- [ ] Advanced analytics events
- [ ] Multi-language support
- [ ] Accessibility audit

---

## Features Ready for Beta

### Parent App
- Home dashboard with child selector
- One-tap reading logging
- Reading history with charts
- 19 achievement badges
- Customizable reminders
- Offline mode with sync
- Student reports (PDF)
- Book browser

### Teacher App
- Class dashboard
- Reading allocation (by level, title, or free choice)
- Student progress tracking
- Reading groups management
- Class reports (CSV export)

### Admin Portal
- School-wide analytics
- User management
- Student/class management
- Parent linking codes
- CSV import

---

## Known Gaps

| Gap | Impact | Plan |
|-----|--------|------|
| Limited test coverage | Medium | Focus on integration tests |
| No load testing | Low | Monitor in beta |
| Basic analytics | Low | Enhance post-beta |
| Single language | Medium | Add after launch |

---

## Success Metrics for Beta

| Metric | Target |
|--------|--------|
| Crash-free rate | >99% |
| Active testers | >30 users |
| Reading logs created | >100 in first week |
| Critical bugs | <3 |
| User satisfaction | >4.0/5.0 |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| App store rejection | Follow all guidelines, test thoroughly |
| Critical bugs found | Rollback plan ready, quick fixes |
| Low engagement | Proactive outreach, incentives |
| Security issues | Already audited, monitoring in place |

---

## Quick Reference

### Key Files
- `BETA_INVESTIGATION.md` - Detailed codebase analysis
- `BETA_RELEASE_PLAN.md` - Full release plan with tasks
- `APP_FLOW.md` - Navigation and screen flows
- `DESIGN_SYSTEM.md` - UI component reference

### Important Commands
```bash
# Deploy Cloud Functions
cd functions && npm run build && firebase deploy --only functions

# Build iOS
flutter build ios --release

# Build Android
flutter build appbundle --release

# Run tests
flutter test
```

### Support Contacts
- Technical issues: [TBD]
- Product questions: [TBD]
- Legal/compliance: [TBD]

---

## Next Steps

1. **Review this plan** - Get team alignment
2. **Assign owners** - Each task needs an owner
3. **Start Week 1 tasks** - Begin with Cloud Functions deployment
4. **Set up daily standups** - Track progress through the 4 weeks

---

*For detailed information, see the full `BETA_RELEASE_PLAN.md` document.*
