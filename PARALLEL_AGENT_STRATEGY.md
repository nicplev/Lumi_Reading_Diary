# Parallel Agent Execution Strategy
## Lumi Design System Migration

**Created:** 2025-11-23
**Strategy:** Run 3 agents in parallel for maximum efficiency
**Estimated Completion:** 2-3 days (vs 12-15 days sequential)

---

## 🎯 Agent Assignment Strategy

### Agent 1: "Auth & Simple Screens" 🔐
**Focus:** Authentication + Simple screens
**Estimated Time:** 8-10 hours
**Screens:** 7 total

#### Assigned Files:
```
lib/screens/auth/splash_screen.dart              (172 lines, Simple)
lib/screens/auth/forgot_password_screen.dart     (326 lines, Simple)
lib/screens/auth/web_not_available_screen.dart   (345 lines, Medium)
lib/screens/teacher/teacher_profile_screen.dart  (368 lines, Simple)
lib/screens/admin/database_migration_screen.dart (494 lines, Simple)
lib/screens/onboarding/demo_request_screen.dart  (348 lines, Simple)
lib/screens/onboarding/school_demo_screen.dart   (388 lines, Medium)
```

#### Special Instructions:
- Start with `splash_screen.dart` (quick win)
- Remove LinearGradient from `web_not_available_screen.dart` and `school_demo_screen.dart`
- Commit after each screen individually
- **Track progress in `AGENT_1_PROGRESS.md`** (create and update after each screen)

---

### Agent 2: "Teacher & Admin Complex" 👨‍🏫
**Focus:** Teacher screens + Admin dashboard
**Estimated Time:** 12-14 hours
**Screens:** 8 total

#### Assigned Files:
```
lib/screens/teacher/teacher_home_screen.dart          (1,065 lines, Complex)
lib/screens/teacher/class_detail_screen.dart          (576 lines, Medium)
lib/screens/teacher/class_report_screen.dart          (535 lines, Medium)
lib/screens/teacher/reading_groups_screen.dart        (1,102 lines, Complex)
lib/screens/teacher/teacher_home_screen_minimal.dart  (882 lines, Complex)
lib/screens/admin/admin_home_screen.dart              (1,183 lines, Complex)
lib/screens/admin/admin_home_screen_minimal.dart      (1,168 lines, Complex)
lib/screens/admin/school_analytics_dashboard.dart     (1,091 lines, Complex)
```

#### Special Instructions:
- **CRITICAL:** Remove glass_widgets from `teacher_home_screen.dart`
- Remove MinimalTheme from `teacher_home_screen_minimal.dart` and both admin screens
- Update fl_chart colors in analytics dashboard
- Start with simpler screens (`class_report_screen.dart`) before complex ones
- Commit after each screen individually
- **Track progress in `AGENT_2_PROGRESS.md`** (create and update after each screen)

---

### Agent 3: "Forms, Admin Tools & Marketing" 📝
**Focus:** Registration flows + Admin management + Marketing
**Estimated Time:** 10-12 hours
**Screens:** 9 total

#### Assigned Files:
```
lib/screens/auth/register_screen.dart                  (711 lines, Medium)
lib/screens/auth/parent_registration_screen.dart       (701 lines, Medium)
lib/screens/teacher/allocation_screen.dart             (1,115 lines, Complex)
lib/screens/admin/class_management_screen.dart         (914 lines, Medium)
lib/screens/admin/student_management_screen.dart       (1,039 lines, Medium)
lib/screens/admin/parent_linking_management_screen.dart(1,092 lines, Medium)
lib/screens/admin/csv_import_dialog.dart               (981 lines, Medium)
lib/screens/onboarding/school_registration_wizard.dart (608 lines, Medium)
lib/screens/marketing/landing_screen.dart              (1,135 lines, Complex)
```

#### Special Instructions:
- Keep flutter_form_builder, update styling only
- Keep CSV import logic unchanged in `csv_import_dialog.dart`
- Remove RadialGradient from `landing_screen.dart`
- `allocation_screen.dart` is the largest screen - save for last
- Commit after each screen individually
- **Track progress in `AGENT_3_PROGRESS.md`** (create and update after each screen)

---

## 📝 Progress Tracking Files

Each agent has a dedicated progress file to track their work:

- **AGENT_1_PROGRESS.md** - Tracks Agent 1's 7 screens (Auth + Simple)
- **AGENT_2_PROGRESS.md** - Tracks Agent 2's 8 screens (Teacher + Admin Complex)
- **AGENT_3_PROGRESS.md** - Tracks Agent 3's 9 screens (Forms + Admin Tools + Marketing)

These files are **already created** and ready to use. Each agent will update their own file after completing each screen.

**Benefits:**
- ✅ No file conflicts between agents
- ✅ Real-time progress visibility
- ✅ Audit trail of what each agent did
- ✅ Easy debugging if issues arise
- ✅ Simple compilation at the end

After all agents complete, see **COMPILE_PROGRESS.md** for instructions on merging these into MIGRATION_STATUS.md.

---

## 🔄 Execution Workflow

### Phase 1: Launch Agents (5 minutes)

**In a single message, launch all 3 agents in parallel:**

```
I need you to launch 3 agents in parallel to work on the Lumi Design System migration.

Please launch the following agents simultaneously:

AGENT 1 - Auth & Simple Screens:
Migrate the following screens to Lumi Design System following the process in MIGRATION_STATUS.md:
- lib/screens/auth/splash_screen.dart
- lib/screens/auth/forgot_password_screen.dart
- lib/screens/auth/web_not_available_screen.dart
- lib/screens/teacher/teacher_profile_screen.dart
- lib/screens/admin/database_migration_screen.dart
- lib/screens/onboarding/demo_request_screen.dart
- lib/screens/onboarding/school_demo_screen.dart

Work on these screens in order. Make individual commits after each screen. Do NOT update MIGRATION_STATUS.md.

AGENT 2 - Teacher & Admin Complex:
Migrate the following screens to Lumi Design System following the process in MIGRATION_STATUS.md:
- lib/screens/teacher/class_report_screen.dart (start here)
- lib/screens/teacher/class_detail_screen.dart
- lib/screens/teacher/teacher_home_screen.dart (REMOVE glass_widgets)
- lib/screens/teacher/reading_groups_screen.dart
- lib/screens/teacher/teacher_home_screen_minimal.dart (REMOVE MinimalTheme)
- lib/screens/admin/school_analytics_dashboard.dart
- lib/screens/admin/admin_home_screen.dart (REMOVE MinimalTheme)
- lib/screens/admin/admin_home_screen_minimal.dart (REMOVE MinimalTheme)

Work on these screens in order. Make individual commits after each screen. Do NOT update MIGRATION_STATUS.md.

AGENT 3 - Forms, Admin Tools & Marketing:
Migrate the following screens to Lumi Design System following the process in MIGRATION_STATUS.md:
- lib/screens/auth/register_screen.dart
- lib/screens/auth/parent_registration_screen.dart
- lib/screens/admin/class_management_screen.dart
- lib/screens/admin/student_management_screen.dart
- lib/screens/admin/csv_import_dialog.dart (keep CSV logic unchanged)
- lib/screens/admin/parent_linking_management_screen.dart
- lib/screens/onboarding/school_registration_wizard.dart
- lib/screens/marketing/landing_screen.dart (REMOVE RadialGradient)
- lib/screens/teacher/allocation_screen.dart (largest screen - do last)

Work on these screens in order. Make individual commits after each screen. Do NOT update MIGRATION_STATUS.md.
```

### Phase 2: Monitor Progress (Ongoing)

Each agent will work independently and report when complete. You'll see:

```
✅ Agent 1 completed: splash_screen.dart (commit: abc123)
✅ Agent 2 completed: class_report_screen.dart (commit: def456)
✅ Agent 3 completed: register_screen.dart (commit: ghi789)
...
```

### Phase 3: Handle Conflicts (If any)

**Git Conflict Resolution:**
If two agents commit at the same time, you may see a merge conflict. Handle it:

```bash
git pull --rebase
# Resolve any conflicts (unlikely since different files)
git rebase --continue
git push
```

**Tip:** Conflicts are unlikely since each agent works on different files.

### Phase 4: Compile Progress Reports

Once all 3 agents report completion:

1. **Review individual progress files:**
   - Read `AGENT_1_PROGRESS.md` - verify all 7 screens completed
   - Read `AGENT_2_PROGRESS.md` - verify all 8 screens completed
   - Read `AGENT_3_PROGRESS.md` - verify all 9 screens completed

2. **Check for issues:**
   - Look for any "Issues Encountered" notes
   - Verify all commit hashes are present
   - Confirm all verification checklists are checked

3. **Compile into main documentation:**
   - Update `MIGRATION_STATUS.md` with all completed screens
   - Mark all checkboxes in `LUMI_UI_MIGRATION_PLAN.md`
   - Add summary of total screens migrated (should be 24)

### Phase 5: Final Verification

After compiling progress reports:

1. **Check all screens migrated:**
   ```bash
   # Verify no legacy colors
   grep -r "primaryBlue\|backgroundPrimary" lib/screens/

   # Verify no Theme.of(context).textTheme
   grep -r "Theme.of(context).textTheme" lib/screens/
   ```

2. **Run the app:**
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

3. **Test critical workflows:**
   - Auth flow (login, registration)
   - Parent dashboard
   - Teacher dashboard
   - Admin dashboard
   - Form submissions

---

## 📊 Expected Timeline

| Time | Agent 1 | Agent 2 | Agent 3 |
|------|---------|---------|---------|
| **Hour 1-2** | splash, forgot_password | class_report | register |
| **Hour 3-4** | web_not_available | class_detail | parent_registration |
| **Hour 5-6** | teacher_profile | teacher_home (glass removal) | class_management |
| **Hour 7-8** | database_migration | reading_groups | student_management |
| **Hour 9-10** | demo_request | teacher_home_minimal | csv_import_dialog |
| **Hour 11-12** | school_demo | analytics_dashboard | parent_linking |
| **Hour 13-14** | ✅ Done | admin_home | school_registration_wizard |
| **Hour 15-16** | - | admin_home_minimal | landing |
| **Hour 17-18** | - | ✅ Done | allocation |
| **Hour 19-20** | - | - | ✅ Done |

**Total Completion Time:** ~14-20 hours (2-3 work days) vs 12-15 days sequential

---

## ⚠️ Critical Rules for Parallel Execution

### ✅ DO:
- Work only on assigned files
- Commit after each screen individually
- Follow the migration process in MIGRATION_STATUS.md exactly
- Run grep verification checks before committing
- Keep business logic unchanged (UI only)
- **Update your own progress file** (AGENT_1/2/3_PROGRESS.md) after each screen

### ❌ DON'T:
- Update `MIGRATION_STATUS.md` or `LUMI_UI_MIGRATION_PLAN.md` (these will be compiled at the end)
- Modify shared design system files (`app_colors.dart`, etc.)
- Create new shared components without coordination
- Work on files not in your assignment
- Batch commits (one commit per screen)
- Update another agent's progress file

---

## 🔍 Conflict Prevention Checklist

Before launching agents:

- [ ] Verify no uncommitted changes in working directory
- [ ] Ensure on latest main/master branch (`git pull`)
- [ ] Confirm design system files are stable
- [ ] Review agent assignments (no file overlap)
- [ ] Confirm agents understand NOT to update docs

During execution:

- [ ] Monitor agent progress
- [ ] Watch for git conflicts
- [ ] Check commit history
- [ ] Verify each agent is on assigned files

After completion:

- [ ] Run full app test
- [ ] Verify all screens migrated
- [ ] Update documentation manually
- [ ] Create summary commit

---

## 🎁 Benefits of Parallel Execution

**Speed:**
- 2-3 days vs 12-15 days
- **83% time reduction**

**Consistency:**
- All agents follow same migration process
- No context-switching fatigue
- Fresh eyes on each screen

**Efficiency:**
- Maximize Claude Code capabilities
- Parallel workload distribution
- Optimal resource utilization

---

## 🚨 Emergency Procedures

### If an Agent Gets Stuck:

1. **Stop the agent** (if possible)
2. **Note which screen** it was working on
3. **Manually complete** that screen, or
4. **Reassign** to another agent

### If Git Conflicts Occur:

1. **Pause all agents** (wait for current commits to finish)
2. **Resolve conflicts manually:**
   ```bash
   git status
   git pull --rebase
   # Fix conflicts
   git add .
   git rebase --continue
   ```
3. **Resume agents** after conflict resolved

### If Agents Overlap:

This shouldn't happen if assignments are followed, but if it does:
1. **Identify which agent** committed first
2. **Use that agent's version** (it committed first = winner)
3. **Discard other agent's work** on that file
4. **Reassign** the second agent to a different screen

---

## 📝 Post-Migration Checklist

After all agents complete:

### Code Quality
- [ ] All 24 screens migrated
- [ ] No hardcoded colors (`Color(0x...)`)
- [ ] No `Theme.of(context).textTheme`
- [ ] No hardcoded spacing values
- [ ] All `.withOpacity()` → `.withValues(alpha:)`
- [ ] All buttons use Lumi components
- [ ] All cards use LumiCard

### Testing
- [ ] App compiles without errors
- [ ] All screens render correctly
- [ ] Navigation works
- [ ] Forms submit correctly
- [ ] Charts display data
- [ ] No console warnings

### Documentation
- [ ] `MIGRATION_STATUS.md` updated to 100%
- [ ] All checkboxes marked in migration plan
- [ ] Commit history is clean
- [ ] Summary commit created

### Cleanup
- [ ] Remove unused glass_widgets imports
- [ ] Remove unused minimal_theme imports
- [ ] Run `flutter clean && flutter pub get`
- [ ] Run `flutter analyze` (zero issues)

---

## 🎯 Success Metrics

**Target:**
- 24 screens migrated
- 2-3 days completion time
- Zero merge conflicts
- 100% test pass rate

**Reality Check:**
- Expect minor conflicts (easily resolved)
- Some screens may need manual review
- Total time may vary based on screen complexity

---

## 🚀 Ready to Launch?

Copy and paste the launch command from Phase 1 to start all 3 agents in parallel!

**Remember:** The key to success is clear file boundaries and no documentation updates from agents.

**Let's migrate 24 screens in parallel! 🎨⚡**
