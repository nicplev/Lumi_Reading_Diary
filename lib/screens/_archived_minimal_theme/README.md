# Archived: Minimal Theme Screens

**Archived Date:** 2025-11-23
**Reason:** Unused experimental theme variants

## Contents

This folder contains experimental "minimal theme" screen variants that were created but never integrated into the app's navigation flow.

### Files Archived:

1. **parent_home_screen_minimal.dart** (631 lines)
   - Alternate minimal theme variant of parent home screen
   - Route: `/parent/home-minimal`
   - Status: Defined in routing but never navigated to

2. **teacher_home_screen_minimal.dart** (882 lines)
   - Alternate minimal theme variant of teacher home screen
   - Route: `/teacher/home-minimal`
   - Status: Defined in routing but never navigated to

3. **admin_home_screen_minimal.dart** (1,168 lines)
   - Alternate minimal theme variant of admin home screen
   - Route: `/admin/home-minimal`
   - Status: Defined in routing but never navigated to

## Why Archived?

- **No active usage:** Zero navigation calls to these routes found in the codebase
- **Experimental code:** Appear to be UI theme experiments that were never completed
- **Maintenance burden:** Use deprecated MinimalTheme instead of Lumi Design System
- **Dead code:** Routes defined but unreachable by users

## Dependencies Used:

These screens rely on:
- `lib/core/theme/minimal_theme.dart`
- `lib/core/widgets/minimal/minimal_widgets.dart`

## If You Need to Restore:

1. Move the file(s) back to their original location:
   - `lib/screens/parent/`
   - `lib/screens/teacher/`
   - `lib/screens/admin/`

2. Add the route back to `lib/core/routing/app_router.dart`

3. Add the import back to `app_router.dart`

4. Migrate the screen to Lumi Design System (remove MinimalTheme dependencies)

5. Add navigation calls to make the route accessible

## Related Commits:

- Original minimal theme screens: (check git history)
- Archived minimal screens: (this commit)
- Lumi Design System migration: See MIGRATION_STATUS.md

---

**Note:** These files are kept for reference only. They are not part of the active codebase and should not be imported or used.
