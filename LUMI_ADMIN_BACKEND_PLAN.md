# Lumi Admin Backend — Full Implementation Plan

> **Purpose:** Self-contained blueprint for building the Lumi internal admin dashboard. Designed to be picked up by any fresh Claude Code session without needing prior context. Contains all Firestore schemas, data relationships, and implementation details embedded directly.
>
> **Flutter codebase location:** `/Users/nicplev/lumi_reading_tracker` — Claude can read files from this path regardless of working directory. Reference specific model files when you need exact field names or validation logic.
>
> **Target directory:** `/Users/nicplev/lumi-admin`

---

## Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Framework | **Next.js 15 (App Router)** | SSR for heavy operations, API routes for admin SDK, React ecosystem |
| UI | **shadcn/ui + Tailwind CSS** | Production-grade components, consistent design, fast to build |
| Charts | **Tremor** | Built for dashboards, works with shadcn/Tailwind |
| Auth | **Firebase Auth** (company domain restriction) | Same Firebase project, Admin SDK for user management |
| Backend | **Firebase Admin SDK** (Node.js) | Full Firestore access bypassing security rules, Auth admin ops |
| Types | **TypeScript** throughout | Type safety, mirrors Dart models |
| State | **TanStack Query (React Query)** | Caching, pagination, real-time invalidation |
| Forms | **React Hook Form + Zod** | Validation, complex CRUD forms |
| Tables | **TanStack Table** | Sorting, filtering, pagination for data-heavy views |
| Package Manager | **pnpm** | Fast, disk efficient |

---

## Firestore Schema (Complete)

This is the source of truth. All TypeScript types must mirror this structure.

### Collection: `/schools/{schoolId}`

```typescript
interface School {
  id: string;
  name: string;
  logoUrl?: string;
  colors?: { primary: string; secondary: string };
  levelSchema: 'aToZ' | 'pmBenchmark' | 'lexile' | 'custom';
  customLevels?: string[]; // only if levelSchema === 'custom'
  termDates?: { term: number; start: Timestamp; end: Timestamp }[];
  quietHours?: { start: string; end: string }; // "HH:mm" format
  timezone?: string;
  address?: string;
  contactEmail?: string;
  contactPhone?: string;
  isActive: boolean;
  createdAt: Timestamp;
  createdBy: string; // userId
  settings?: Record<string, any>;
  studentCount?: number;
  teacherCount?: number;
  subscriptionPlan?: string;
  subscriptionExpiry?: Timestamp;
}
```

### Collection: `/schools/{schoolId}/users/{userId}`

```typescript
interface SchoolUser {
  id: string;
  email: string;
  fullName: string;
  role: 'teacher' | 'schoolAdmin';
  schoolId: string;
  classIds?: string[];
  profileImageUrl?: string;
  isActive: boolean;
  createdAt: Timestamp;
  lastLoginAt?: Timestamp;
  preferences?: Record<string, any>;
  fcmToken?: string;
}
```

### Collection: `/schools/{schoolId}/parents/{parentId}`

```typescript
interface Parent {
  id: string;
  email: string;
  fullName: string;
  role: 'parent'; // always 'parent'
  schoolId: string;
  linkedChildren: string[]; // studentIds
  profileImageUrl?: string;
  isActive: boolean;
  createdAt: Timestamp;
  lastLoginAt?: Timestamp;
  preferences?: Record<string, any>;
  fcmToken?: string;
}
```

### Collection: `/schools/{schoolId}/students/{studentId}`

```typescript
interface Student {
  id: string;
  firstName: string;
  lastName: string;
  studentId?: string; // school's internal ID
  schoolId: string;
  classId: string;
  currentReadingLevel?: string;
  currentReadingLevelIndex?: number;
  readingLevelUpdatedAt?: Timestamp;
  readingLevelUpdatedBy?: string;
  readingLevelSource?: 'teacher' | 'schoolAdmin' | 'bulkTeacher';
  parentIds: string[];
  dateOfBirth?: Timestamp;
  profileImageUrl?: string;
  isActive: boolean;
  createdAt: Timestamp;
  enrolledAt?: Timestamp;
  additionalInfo?: Record<string, any>;
  levelHistory?: ReadingLevelHistoryEntry[];
  stats?: StudentStats;
}

interface StudentStats {
  totalMinutesRead: number;
  totalBooksRead: number;
  currentStreak: number;
  longestStreak: number;
  lastReadingDate?: Timestamp;
  averageMinutesPerDay: number;
  totalReadingDays: number;
}

// Subcollection: /schools/{schoolId}/students/{studentId}/readingLevelEvents/{eventId}
interface ReadingLevelEvent {
  id: string;
  studentId: string;
  schoolId: string;
  classId?: string;
  fromLevel?: string;
  toLevel: string;
  fromLevelIndex?: number;
  toLevelIndex?: number;
  reason?: string;
  source: 'teacher' | 'schoolAdmin' | 'bulkTeacher';
  changedByUserId: string;
  changedByRole: string;
  changedByName?: string;
  createdAt: Timestamp;
}
```

### Collection: `/schools/{schoolId}/classes/{classId}`

```typescript
interface Class {
  id: string;
  schoolId: string;
  name: string;
  yearLevel?: string;
  room?: string;
  teacherId: string; // primary teacher
  assistantTeacherId?: string;
  teacherIds: string[]; // all teachers
  studentIds: string[];
  defaultMinutesTarget?: number;
  description?: string;
  isActive: boolean;
  createdAt: Timestamp;
  createdBy: string;
  settings?: Record<string, any>;
}
```

### Collection: `/schools/{schoolId}/allocations/{allocationId}`

```typescript
interface Allocation {
  id: string;
  schoolId: string;
  classId: string;
  teacherId: string;
  studentIds: string[];
  type: 'byLevel' | 'byTitle' | 'freeChoice';
  cadence: 'daily' | 'weekly' | 'fortnightly' | 'custom';
  targetMinutes: number;
  startDate: Timestamp;
  endDate?: Timestamp;
  levelStart?: string;
  levelEnd?: string;
  assignmentItems?: AllocationBookItem[];
  studentOverrides?: Record<string, StudentAllocationOverride>;
  schemaVersion?: number;
  isRecurring: boolean;
  templateName?: string;
  isActive: boolean;
  createdAt: Timestamp;
  createdBy: string;
  metadata?: Record<string, any>;
}

interface AllocationBookItem {
  id: string;
  title: string;
  bookId?: string;
  isbn?: string;
  isDeleted: boolean;
  addedAt: Timestamp;
  addedBy: string;
  metadata?: Record<string, any>;
}

interface StudentAllocationOverride {
  studentId: string;
  removedItemIds: string[];
  addedItems: AllocationBookItem[];
  updatedAt: Timestamp;
  updatedBy: string;
  metadata?: Record<string, any>;
}
```

### Collection: `/schools/{schoolId}/books/{bookId}`

```typescript
interface Book {
  id: string;
  title: string;
  author?: string;
  isbn?: string;
  coverImageUrl?: string;
  description?: string;
  genres?: string[];
  readingLevel?: string;
  pageCount?: number;
  publisher?: string;
  publishedDate?: string;
  tags?: string[];
  averageRating?: number;
  ratingCount?: number;
  isPopular: boolean;
  timesRead: number;
  createdAt: Timestamp;
  addedBy?: string;
  metadata?: Record<string, any>;
  scannedByTeacherIds?: string[];
  timesAssignedSchoolWide?: number;
}
```

### Collection: `/schools/{schoolId}/readingLogs/{logId}`

```typescript
interface ReadingLog {
  id: string;
  studentId: string;
  parentId?: string;
  schoolId: string;
  classId?: string;
  date: Timestamp;
  minutesRead: number;
  targetMinutes?: number;
  status: 'completed' | 'partial' | 'skipped' | 'pending';
  bookTitles?: string[];
  notes?: string;
  photoUrls?: string[];
  isOfflineCreated: boolean;
  createdAt: Timestamp;
  syncedAt?: Timestamp;
  allocationId?: string;
  metadata?: Record<string, any>;
  // Parent feedback
  parentComment?: string;
  parentCommentSelections?: string[];
  parentCommentFreeText?: string;
  // Teacher feedback
  teacherComment?: string;
  commentedAt?: Timestamp;
  commentedBy?: string;
  // Child feeling
  readingFeeling?: 'hard' | 'tricky' | 'okay' | 'good' | 'great';
}
```

### Collection: `/schoolOnboarding/{id}`

```typescript
interface SchoolOnboarding {
  id: string;
  schoolName: string;
  contactEmail: string;
  contactPhone?: string;
  contactPerson: string;
  status: 'demo' | 'interested' | 'registered' | 'setupInProgress' | 'active' | 'suspended';
  currentStep: 'schoolInfo' | 'adminAccount' | 'readingLevels' | 'importData' | 'inviteTeachers' | 'completed';
  completedSteps: string[];
  createdAt: Timestamp;
  lastUpdatedAt: Timestamp;
  schoolId?: string; // set once school is created
  adminUserId?: string;
  metadata?: Record<string, any>;
  demoScheduledAt?: Timestamp;
  registrationCompletedAt?: Timestamp;
  referralSource?: string;
  estimatedStudentCount?: number;
  estimatedTeacherCount?: number;
}
```

### Collection: `/studentLinkCodes/{id}`

```typescript
interface StudentLinkCode {
  id: string;
  studentId: string;
  schoolId: string;
  code: string; // 8-char uppercase alphanumeric (excludes I, O, 0, 1)
  status: 'active' | 'used' | 'expired' | 'revoked';
  createdAt: Timestamp;
  expiresAt: Timestamp;
  createdBy: string;
  usedBy?: string;
  usedAt?: Timestamp;
  revokedBy?: string;
  revokedAt?: Timestamp;
  revokeReason?: string;
  metadata?: Record<string, any>;
}
```

### Collection: `/schoolCodes/{id}`

```typescript
interface SchoolCode {
  id: string;
  code: string;
  schoolId: string;
  schoolName: string;
  isActive: boolean;
  createdAt: Timestamp;
  expiresAt?: Timestamp;
  createdBy: string;
  usageCount: number;
  maxUsages?: number;
}
```

### Collection: `/readingGoals/{id}`

```typescript
interface ReadingGoal {
  id: string;
  studentId: string;
  schoolId: string;
  type: 'dailyMinutes' | 'weeklyMinutes' | 'monthlyMinutes' | 'dailyStreak' | 'booksToRead' | 'pagesPerDay' | 'custom';
  title: string;
  description?: string;
  targetValue: number;
  currentValue: number;
  startDate: Timestamp;
  endDate?: Timestamp;
  status: 'active' | 'completed' | 'failed' | 'paused';
  completedAt?: Timestamp;
  rewardMessage?: string;
  parentMessage?: string;
  createdAt: Timestamp;
  metadata?: Record<string, any>;
}
```

### Collection: `/schools/{schoolId}/readingGroups/{id}`

```typescript
interface ReadingGroup {
  id: string;
  classId: string;
  schoolId: string;
  name: string;
  description?: string;
  readingLevel?: string;
  studentIds: string[];
  color?: string;
  targetMinutes?: number;
  createdAt: Timestamp;
  createdBy: string;
  updatedAt?: Timestamp;
  isActive: boolean;
  settings?: Record<string, any>;
}
```

### Collection: `/notifications/{id}`

```typescript
interface Notification {
  id: string;
  userId: string;
  schoolId: string;
  title: string;
  body: string;
  type: string;
  isRead: boolean;
  createdAt: Timestamp;
  metadata?: Record<string, any>;
}
```

### Collection: `/userSchoolIndex/{emailHash}`

```typescript
// Used for email-to-school lookup during auth
interface UserSchoolIndex {
  email: string;
  schoolId: string;
  userId: string;
  role: string;
}
```

---

## Data Relationships Map

```
School
├── Users (teachers, schoolAdmins)
├── Parents (linked to students via parentIds/linkedChildren)
├── Classes
│   ├── Students
│   │   ├── ReadingLevelEvents (audit trail)
│   │   ├── Stats (embedded)
│   │   └── LevelHistory (embedded)
│   └── ReadingGroups
├── Allocations (book assignments)
│   ├── AssignmentItems (embedded)
│   └── StudentOverrides (embedded map)
├── Books (school library)
└── ReadingLogs (daily reading sessions)

Cross-collection links:
- Student.parentIds ↔ Parent.linkedChildren (bidirectional)
- Student.classId → Class.id
- Class.teacherIds → User.id[]
- Allocation.classId → Class.id
- Allocation.studentIds → Student.id[]
- ReadingLog.studentId → Student.id
- ReadingLog.allocationId → Allocation.id
- StudentLinkCode.studentId → Student.id
- SchoolOnboarding.schoolId → School.id (set after creation)
- SchoolCode.schoolId → School.id
- ReadingGoal.studentId → Student.id
- UserSchoolIndex.schoolId → School.id
```

---

## Project Structure

```
lumi-admin/
├── .env.local                    # Firebase service account key path, project config
├── next.config.ts
├── tailwind.config.ts
├── tsconfig.json
├── package.json
│
├── src/
│   ├── app/
│   │   ├── layout.tsx            # Root layout with sidebar nav
│   │   ├── page.tsx              # Dashboard home (system overview)
│   │   ├── login/
│   │   │   └── page.tsx          # Company domain login
│   │   │
│   │   ├── schools/
│   │   │   ├── page.tsx          # School list + search + filters
│   │   │   ├── [schoolId]/
│   │   │   │   ├── page.tsx      # School detail/edit
│   │   │   │   ├── users/
│   │   │   │   │   └── page.tsx  # Teachers & admins for this school
│   │   │   │   ├── parents/
│   │   │   │   │   └── page.tsx  # Parents for this school
│   │   │   │   ├── classes/
│   │   │   │   │   ├── page.tsx  # Classes list
│   │   │   │   │   └── [classId]/
│   │   │   │   │       └── page.tsx  # Class detail with students
│   │   │   │   ├── students/
│   │   │   │   │   ├── page.tsx  # All students in school
│   │   │   │   │   └── [studentId]/
│   │   │   │   │       └── page.tsx  # Student detail + level history + stats
│   │   │   │   ├── library/
│   │   │   │   │   └── page.tsx  # School's book library
│   │   │   │   ├── allocations/
│   │   │   │   │   └── page.tsx  # Allocations for this school
│   │   │   │   ├── reading-logs/
│   │   │   │   │   └── page.tsx  # Reading logs for this school
│   │   │   │   ├── analytics/
│   │   │   │   │   └── page.tsx  # School-specific analytics
│   │   │   │   └── settings/
│   │   │   │       └── page.tsx  # School config (levels, terms, etc.)
│   │   │   └── new/
│   │   │       └── page.tsx      # Create new school
│   │   │
│   │   ├── onboarding/
│   │   │   ├── page.tsx          # Pipeline view (kanban)
│   │   │   └── [id]/
│   │   │       └── page.tsx      # Onboarding detail/progress
│   │   │
│   │   ├── users/
│   │   │   └── page.tsx          # Global user search (across schools)
│   │   │
│   │   ├── link-codes/
│   │   │   └── page.tsx          # All student link codes
│   │   │
│   │   ├── analytics/
│   │   │   └── page.tsx          # Cross-school analytics
│   │   │
│   │   ├── operations/
│   │   │   ├── page.tsx          # Operations hub
│   │   │   ├── offboard/
│   │   │   │   └── page.tsx      # School teardown wizard
│   │   │   ├── export/
│   │   │   │   └── page.tsx      # Data export tool
│   │   │   └── audit-log/
│   │   │       └── page.tsx      # Admin action audit trail
│   │   │
│   │   └── api/
│   │       ├── auth/
│   │       │   └── route.ts      # Auth verification
│   │       ├── schools/
│   │       │   └── route.ts      # School CRUD
│   │       ├── users/
│   │       │   └── route.ts      # User management + Auth admin
│   │       ├── export/
│   │       │   └── route.ts      # CSV/PDF export generation
│   │       ├── offboard/
│   │       │   └── route.ts      # Cascade deactivation
│   │       └── bulk/
│   │           └── route.ts      # Bulk operations (import CSV, etc.)
│   │
│   ├── lib/
│   │   ├── firebase-admin.ts     # Firebase Admin SDK singleton
│   │   ├── auth.ts               # Session management, domain check
│   │   ├── types/
│   │   │   ├── school.ts
│   │   │   ├── user.ts
│   │   │   ├── student.ts
│   │   │   ├── class.ts
│   │   │   ├── allocation.ts
│   │   │   ├── book.ts
│   │   │   ├── reading-log.ts
│   │   │   ├── reading-goal.ts
│   │   │   ├── reading-group.ts
│   │   │   ├── onboarding.ts
│   │   │   ├── link-code.ts
│   │   │   ├── school-code.ts
│   │   │   ├── notification.ts
│   │   │   └── index.ts          # Re-exports
│   │   ├── firestore/
│   │   │   ├── schools.ts        # School CRUD helpers
│   │   │   ├── users.ts          # User CRUD + Auth admin helpers
│   │   │   ├── students.ts       # Student CRUD + level management
│   │   │   ├── classes.ts        # Class CRUD
│   │   │   ├── allocations.ts    # Allocation CRUD
│   │   │   ├── books.ts          # Book CRUD
│   │   │   ├── reading-logs.ts   # Reading log queries
│   │   │   ├── onboarding.ts     # Onboarding pipeline ops
│   │   │   ├── link-codes.ts     # Link code management
│   │   │   └── analytics.ts      # Aggregation queries
│   │   ├── hooks/
│   │   │   ├── use-schools.ts    # React Query hooks for schools
│   │   │   ├── use-students.ts
│   │   │   ├── use-classes.ts
│   │   │   ├── use-users.ts
│   │   │   ├── use-allocations.ts
│   │   │   ├── use-reading-logs.ts
│   │   │   ├── use-analytics.ts
│   │   │   └── use-auth.ts
│   │   └── utils/
│   │       ├── formatters.ts     # Date, reading level, stats formatting
│   │       ├── validators.ts     # Zod schemas
│   │       ├── isbn.ts           # ISBN normalization (10→13)
│   │       └── export.ts         # CSV/PDF generation helpers
│   │
│   └── components/
│       ├── layout/
│       │   ├── sidebar.tsx       # Main navigation sidebar
│       │   ├── header.tsx        # Top bar with breadcrumbs + user menu
│       │   └── page-header.tsx   # Page title + actions
│       ├── ui/                   # shadcn/ui components (auto-generated)
│       ├── data-table/
│       │   ├── data-table.tsx    # Reusable TanStack Table wrapper
│       │   ├── columns.tsx       # Column definitions
│       │   └── toolbar.tsx       # Search + filters
│       ├── forms/
│       │   ├── school-form.tsx
│       │   ├── user-form.tsx
│       │   ├── student-form.tsx
│       │   ├── class-form.tsx
│       │   └── allocation-form.tsx
│       ├── cards/
│       │   ├── stat-card.tsx
│       │   ├── school-card.tsx
│       │   └── student-card.tsx
│       ├── charts/
│       │   ├── reading-trend.tsx
│       │   ├── level-distribution.tsx
│       │   └── engagement-chart.tsx
│       ├── onboarding/
│       │   ├── pipeline-board.tsx  # Kanban board
│       │   └── step-progress.tsx
│       └── shared/
│           ├── confirm-dialog.tsx  # Destructive action confirmation
│           ├── status-badge.tsx
│           ├── search-input.tsx
│           └── empty-state.tsx
```

---

## Session Management Rules

> **IMPORTANT: Claude MUST follow these rules for session boundaries.**

### When to end a session
- **After completing a phase's deliverable checklist** — commit all work, report what was done, and tell the user: "Phase X is complete. Start a new session and ask me to read the plan file and begin Phase Y."
- **When context feels heavy** — if responses are slowing down, code suggestions are getting inconsistent, or you're losing track of what's been built, proactively tell the user: "We're hitting context limits. Let's commit, end this session, and pick up in a fresh one."
- **Never start a new phase in the same session** — each phase should begin fresh so Claude has maximum context for the work ahead.

### Before ending any session
1. `git add` and `git commit` all work with a descriptive message
2. Update the **Phase Progress Tracker** section below with what was completed
3. Note any deviations from the plan or decisions made during the session
4. Tell the user exactly what to say in the next session to continue

### Phase Progress Tracker

Update this section as phases are completed. This is how future sessions know where to pick up.

```
Phase 1: Foundation        [ ] Not started
Phase 2: Schools           [ ] Not started
Phase 3: Users & Students  [ ] Not started
Phase 4: Books & Logs      [ ] Not started
Phase 5: Analytics         [ ] Not started
Phase 6: Operations        [ ] Not started
```

**Session notes** (append after each session):
- _(none yet)_

---

## Implementation Phases

### Phase 1: Foundation (Session 1)

**Goal:** Working app shell with auth, navigation, Firebase connection, and type system.

**Tasks:**
1. Initialize Next.js 15 project with App Router, TypeScript, Tailwind, pnpm
2. Install and configure: shadcn/ui, firebase-admin, tanstack/react-query, tanstack/react-table, react-hook-form, zod, tremor
3. Set up Firebase Admin SDK singleton (`src/lib/firebase-admin.ts`)
   - Service account key via env var
   - Firestore and Auth admin instances
4. Create all TypeScript types (`src/lib/types/`) — copy from schema above
5. Build auth system:
   - Login page (Firebase Auth, restrict to company email domain)
   - Session cookie management via API route
   - Auth middleware (Next.js middleware.ts)
   - Protect all routes except `/login`
6. Build shared layout:
   - Sidebar with navigation groups (Schools, Onboarding, Users, Analytics, Operations)
   - Header with breadcrumbs and user menu
   - Responsive (collapsible sidebar)
7. Build reusable data table component (TanStack Table wrapper)
8. Build shared components: stat-card, confirm-dialog, status-badge, empty-state, search-input
9. Dashboard home page with system-wide stats:
   - Total schools (active/inactive)
   - Total students, teachers, parents
   - Total reading logs this week/month
   - Recent onboarding requests

**Deliverable:** Navigable app shell, authenticated, connected to Firebase, showing real aggregate data on the dashboard.

**Completion checklist — do NOT end session until all are done:**
- [ ] `pnpm dev` runs without errors
- [ ] Login page restricts to company domain
- [ ] Authenticated routes redirect to login when not signed in
- [ ] Sidebar navigation renders with all section links
- [ ] Dashboard page loads and shows real Firestore aggregate data
- [ ] DataTable component works with sample data
- [ ] All TypeScript types created in `src/lib/types/`
- [ ] All code committed to git

**Key files to reference from Flutter project:**
- `/Users/nicplev/lumi_reading_tracker/lib/data/models/` — all model files for field verification
- `/Users/nicplev/lumi_reading_tracker/firestore.rules` — collection paths and structure

**End of phase instruction:** Commit all work, update the Phase Progress Tracker, then tell the user: _"Phase 1 is complete. Start a new session and say: Read /Users/nicplev/lumi_reading_tracker/LUMI_ADMIN_BACKEND_PLAN.md and start Phase 2."_

---

### Phase 2: School Management + Onboarding (Session 2)

**Goal:** Full school CRUD and onboarding pipeline.

**Tasks:**
1. Firestore helpers for schools (`src/lib/firestore/schools.ts`):
   - listSchools (with search, filter by status, pagination)
   - getSchool, createSchool, updateSchool, deactivateSchool
2. Schools list page:
   - Data table with columns: name, status, student count, teacher count, subscription, created date
   - Search by name/email
   - Filter by status (active/inactive/suspended)
   - Click through to detail
3. School detail page:
   - Editable form for all school fields
   - Reading level schema configuration
   - Term dates management
   - Quick stats (students, teachers, active readers)
   - Tabs or links to: Users, Classes, Students, Library, Allocations, Logs, Analytics
4. Create school page:
   - Form with validation
   - Auto-creates school document + generates school code
5. Onboarding pipeline page:
   - Kanban board view: Demo → Interested → Registered → Setup → Active → Suspended
   - Drag to change status
   - Cards show: school name, contact, date, estimated size
   - Click through to detail
6. Onboarding detail page:
   - Progress stepper showing completed/current/remaining steps
   - Contact info, notes, metadata
   - Actions: advance step, change status, link to school (once created), generate school code
7. School code management:
   - Generate new codes, view existing, revoke
   - Show usage count

**Parallelizable:** Schools list/detail can be built in parallel with onboarding pipeline (independent pages).

**Completion checklist — do NOT end session until all are done:**
- [ ] Schools list page with search, filter, pagination
- [ ] School detail page with editable form
- [ ] Create school page working end-to-end (creates Firestore doc + school code)
- [ ] Onboarding pipeline page with kanban board
- [ ] Onboarding detail page with step progress and actions
- [ ] School codes can be generated, viewed, and revoked
- [ ] All code committed to git

**End of phase instruction:** Commit all work, update the Phase Progress Tracker, then tell the user: _"Phase 2 is complete. Start a new session and say: Read /Users/nicplev/lumi_reading_tracker/LUMI_ADMIN_BACKEND_PLAN.md and start Phase 3."_

---

### Phase 3: User & Student Management (Session 3)

**Goal:** Full user, parent, and student CRUD with Firebase Auth integration.

**Tasks:**
1. Firestore + Auth helpers for users (`src/lib/firestore/users.ts`):
   - listUsers (school-scoped), getUser, createUser, updateUser, deactivateUser
   - Firebase Auth admin: disableUser, enableUser, resetPassword, deleteUser
   - listParents (school-scoped), getParent
2. School users page (`/schools/[schoolId]/users`):
   - Data table: name, email, role, classes, last login, status
   - Actions: edit, disable/enable Auth account, reset password, change role
   - Create new teacher/admin with Auth account
3. School parents page (`/schools/[schoolId]/parents`):
   - Data table: name, email, linked children, last login, status
   - View linked students
   - Manage link codes for each parent-student connection
4. Global user search (`/users`):
   - Search across all schools by email or name
   - Shows school, role, status
   - Quick link to school-scoped view
5. Firestore helpers for students (`src/lib/firestore/students.ts`):
   - listStudents (school/class-scoped), getStudent, createStudent, updateStudent, deactivateStudent
   - getReadingLevelEvents, updateReadingLevel
6. School students page (`/schools/[schoolId]/students`):
   - Data table: name, class, reading level, parent linked, stats summary, status
   - Filter by class, reading level, has parent
   - Bulk actions: move class, update level, export
7. Student detail page (`/schools/[schoolId]/students/[studentId]`):
   - Student info form
   - Reading level history (timeline of ReadingLevelEvents)
   - Stats display (minutes, books, streak)
   - Linked parents with link code status
   - Recent reading logs
   - Actions: change level, regenerate link code, move class
8. Class management pages:
   - Classes list with student counts
   - Class detail: edit info, manage student roster, view reading groups
9. Link codes page (`/link-codes`):
   - Global view of all link codes across schools
   - Filter by status (active/used/expired/revoked)
   - Search by code or student name
   - Regenerate, revoke actions

**Parallelizable:** User management, student management, and link codes are independent modules.

**Completion checklist — do NOT end session until all are done:**
- [ ] School users page with CRUD and Auth admin actions (disable, reset password)
- [ ] School parents page with linked children view
- [ ] Global user search works across all schools
- [ ] School students page with filters and bulk actions
- [ ] Student detail page with level history timeline, stats, parent links
- [ ] Class management pages (list + detail)
- [ ] Link codes page with global view, search, revoke/regenerate
- [ ] All code committed to git

**End of phase instruction:** Commit all work, update the Phase Progress Tracker, then tell the user: _"Phase 3 is complete. Start a new session and say: Read /Users/nicplev/lumi_reading_tracker/LUMI_ADMIN_BACKEND_PLAN.md and start Phase 4."_

---

### Phase 4: Books, Allocations & Reading Logs (Session 4)

**Goal:** Library management, allocation viewing/editing, and reading log access.

**Tasks:**
1. Firestore helpers for books (`src/lib/firestore/books.ts`):
   - listBooks (school-scoped), getBook, createBook, updateBook, deleteBook
   - searchBooks (by title, author, ISBN)
2. School library page (`/schools/[schoolId]/library`):
   - Data table: title, author, ISBN, reading level, times read, times assigned
   - Search and filter by level, genre, popularity
   - Add book manually or by ISBN lookup
   - Edit/delete books
   - Distinguish LLLL decodable books vs general library
3. Firestore helpers for allocations (`src/lib/firestore/allocations.ts`):
   - listAllocations (school/class-scoped), getAllocation, createAllocation, updateAllocation
   - getStudentOverrides, updateStudentOverride
4. School allocations page (`/schools/[schoolId]/allocations`):
   - Data table: class, type, cadence, date range, status, student count
   - Filter by class, type, active/inactive
   - Detail view showing assigned books, student overrides
   - Edit allocation items and overrides
5. Firestore helpers for reading logs (`src/lib/firestore/reading-logs.ts`):
   - listReadingLogs (school/class/student-scoped), getReadingLog
   - Aggregation queries: total minutes by date range, completion rates
6. School reading logs page (`/schools/[schoolId]/reading-logs`):
   - Data table: student, date, minutes, target, status, book titles, feeling
   - Filter by class, student, date range, status
   - Expandable rows showing parent/teacher feedback, photos
   - View-only (reading logs shouldn't be admin-editable in most cases)

**Parallelizable:** Books, allocations, and reading logs are independent modules.

**Completion checklist — do NOT end session until all are done:**
- [ ] School library page with search, filter, add/edit/delete books
- [ ] School allocations page with detail view showing items and overrides
- [ ] School reading logs page with filters and expandable rows
- [ ] All Firestore helpers created for books, allocations, reading-logs
- [ ] All code committed to git

**End of phase instruction:** Commit all work, update the Phase Progress Tracker, then tell the user: _"Phase 4 is complete. Start a new session and say: Read /Users/nicplev/lumi_reading_tracker/LUMI_ADMIN_BACKEND_PLAN.md and start Phase 5."_

---

### Phase 5: Analytics & Reporting (Session 5)

**Goal:** School-level and cross-school analytics dashboards.

**Tasks:**
1. Analytics helpers (`src/lib/firestore/analytics.ts`):
   - Aggregation functions for reading data
   - Date range queries
   - Cross-school comparison helpers
2. School analytics page (`/schools/[schoolId]/analytics`):
   - **Engagement metrics:** active readers, total minutes, avg minutes/student, completion rate
   - **Reading trend chart:** minutes per day/week over time (Tremor AreaChart)
   - **Level distribution:** bar chart of students per reading level
   - **Class comparison:** table ranking classes by engagement
   - **Top performers & needs support:** student lists
   - Date range picker (this week, this month, this term, custom)
3. Cross-school analytics page (`/analytics`):
   - **System overview:** total active schools, students, minutes read
   - **School comparison table:** ranked by engagement, growth
   - **Onboarding funnel:** conversion through pipeline stages
   - **Growth trends:** new schools, students, parents over time
   - **Usage patterns:** peak reading times, day-of-week patterns
4. Data export tool (`/operations/export`):
   - Select school + date range
   - Choose data types (students, reading logs, levels, allocations)
   - Generate CSV download
   - PDF report option with charts (school report card)

**Parallelizable:** School analytics and cross-school analytics are independent.

**Completion checklist — do NOT end session until all are done:**
- [ ] School analytics page with engagement metrics and charts
- [ ] Cross-school analytics page with comparison table and trends
- [ ] Data export tool generating CSV downloads
- [ ] Date range picker working across analytics pages
- [ ] All code committed to git

**End of phase instruction:** Commit all work, update the Phase Progress Tracker, then tell the user: _"Phase 5 is complete. Start a new session and say: Read /Users/nicplev/lumi_reading_tracker/LUMI_ADMIN_BACKEND_PLAN.md and start Phase 6."_

---

### Phase 6: Operations & Hardening (Session 6)

**Goal:** Admin operations tooling, audit logging, and polish.

**Tasks:**
1. Audit logging system:
   - Create `/adminAuditLog/{id}` Firestore collection
   - Log all write operations from admin backend: who, what, when, before/after
   - Middleware/wrapper for all mutation functions
   - Audit log viewer page (`/operations/audit-log`) with search and filters
2. School offboarding wizard (`/operations/offboard`):
   - Select school
   - Preview cascade: show counts of users, students, parents, classes, allocations, books, logs that will be affected
   - Two modes:
     - **Soft deactivate:** Set isActive=false on school and all nested documents
     - **Hard delete:** Permanently remove all data (with 72hr delay/confirmation)
   - Step-by-step execution with progress indicator
   - Confirmation dialogs at every step
3. Bulk operations:
   - Import students via CSV (school-scoped)
   - Bulk update reading levels
   - Bulk generate link codes
4. Admin access tiers (stretch goal):
   - Support role: read-only + link code regeneration
   - Admin role: full CRUD + operations
   - Store admin roles in a separate `adminUsers` collection or custom claims
5. Error handling and edge cases:
   - Graceful handling of missing/corrupted data
   - Loading states, empty states throughout
   - Toast notifications for all mutations
   - Optimistic updates where appropriate
6. Polish:
   - Mobile-responsive sidebar
   - Keyboard shortcuts for common actions
   - Breadcrumb navigation everywhere
   - Consistent form validation messages

**Completion checklist — do NOT end session until all are done:**
- [ ] Audit log collection created, all mutations logging actions
- [ ] Audit log viewer page with search and filters
- [ ] School offboarding wizard with soft deactivate working end-to-end
- [ ] At least one bulk operation working (e.g. CSV student import)
- [ ] Loading states and empty states on all pages
- [ ] Toast notifications on all mutations
- [ ] All code committed to git

**End of phase instruction:** Commit all work, update the Phase Progress Tracker. Tell the user: _"Phase 6 is complete. The Lumi Admin Backend is fully built. Review and test across all sections."_

---

## Session Handoff Protocol

When starting a new Claude Code session for this project:

1. **Read this file first:**
   ```
   Read /Users/nicplev/lumi_reading_tracker/LUMI_ADMIN_BACKEND_PLAN.md
   ```

2. **Check what's been built:**
   ```
   ls /Users/nicplev/lumi-admin/src/
   git log --oneline -20  (in lumi-admin directory)
   ```

3. **Identify the current phase** by checking which pages/routes exist and which are still needed.

4. **For Firestore field verification**, read the relevant Flutter model file:
   ```
   Read /Users/nicplev/lumi_reading_tracker/lib/data/models/{model_name}.dart
   ```

5. **Conventions to maintain across sessions:**
   - All Firestore operations go through helpers in `src/lib/firestore/`
   - All data fetching in pages uses React Query hooks from `src/lib/hooks/`
   - All forms use React Hook Form + Zod validation
   - All tables use the shared DataTable component
   - All destructive actions require ConfirmDialog
   - All mutations show toast feedback
   - API routes handle server-side operations (Auth admin, bulk ops, exports)

---

## Environment Setup

```bash
# .env.local
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json
NEXT_PUBLIC_FIREBASE_PROJECT_ID=your-project-id
FIREBASE_PROJECT_ID=your-project-id
ADMIN_EMAIL_DOMAIN=yourcompany.com  # restrict login to this domain
NEXTAUTH_SECRET=random-secret-for-session-signing
```

**Firebase setup requirements:**
- Download service account key from Firebase Console → Project Settings → Service Accounts
- The service account has full Admin SDK access (no security rules apply)
- Same Firebase project as the Flutter app (shares Firestore, Auth)

---

## Key Design Decisions

1. **Server Components + API Routes** — Firestore reads happen server-side (React Server Components). Mutations go through API routes (which use Admin SDK). This means the service account key never reaches the client.

2. **No real-time listeners** — Unlike the Flutter app, the admin dashboard uses request/response patterns (React Query polling if needed). Real-time is unnecessary for admin operations.

3. **Soft delete by default** — All "delete" operations set `isActive: false`. Hard delete is only available through the offboarding wizard with explicit confirmation.

4. **School-scoped navigation** — Once you select a school, all sub-pages are scoped to that school. The sidebar shows school-specific nav items.

5. **Audit everything** — Every write operation logs to `/adminAuditLog`. This protects against mistakes and provides accountability.

6. **No direct Auth password access** — Admin can trigger password resets and disable accounts but never sees or sets passwords directly.
