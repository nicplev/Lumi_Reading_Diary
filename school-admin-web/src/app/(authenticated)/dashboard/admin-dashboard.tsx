import { StatCard } from '@/components/lumi/stat-card';
import { Card } from '@/components/lumi/card';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Icon } from '@/components/lumi/icon';
import { sectionForPath } from '@/lib/theme/sections';
import Link from 'next/link';
import type { DashboardStats, WeeklyReadingSummary, OperationalSummary } from '@/lib/firestore/dashboard';

interface AdminDashboardProps {
  schoolName: string;
  stats: DashboardStats;
  weekly: WeeklyReadingSummary;
  operational: OperationalSummary;
}

const plural = (n: number) => (n === 1 ? '' : 's');

// Verb-first quick actions — each jumps to the page where the action lives and
// is tinted by that destination's section colour (palette doubles as wayfinding).
const quickActions = [
  { label: 'Add student',       href: '/students',     icon: 'person_add' },
  { label: 'Invite parents',    href: '/parent-links', icon: 'family_restroom' },
  { label: 'Send announcement', href: '/communication', icon: 'campaign' },
  { label: 'Create class',      href: '/classes',      icon: 'add' },
];

export function AdminDashboard({ schoolName, stats, weekly, operational }: AdminDashboardProps) {
  // ── Attention Required — one row per non-zero operational signal, deep-linked
  // to where it gets resolved. Order = rough priority (blockers first). ───────
  const attentionItems = [
    operational.unassignedStudents > 0 && {
      icon: 'person_off',
      label: `${operational.unassignedStudents} student${plural(operational.unassignedStudents)} not assigned to a class`,
      cta: 'Assign students',
      href: '/students?filter=unassigned',
    },
    operational.classesWithoutTeacher > 0 && {
      icon: 'school',
      label: `${operational.classesWithoutTeacher} class${operational.classesWithoutTeacher === 1 ? '' : 'es'} without an assigned teacher`,
      cta: 'Review classes',
      href: '/classes?filter=no-teacher',
    },
    operational.studentsWithoutGuardian > 0 && {
      icon: 'family_restroom',
      label: `${operational.studentsWithoutGuardian} student${plural(operational.studentsWithoutGuardian)} with no linked guardian`,
      cta: 'Review students',
      href: '/students?filter=no-guardian',
    },
    operational.pendingParentInvites > 0 && {
      icon: 'link',
      label: `${operational.pendingParentInvites} parent invitation${plural(operational.pendingParentInvites)} awaiting acceptance`,
      cta: 'View invitations',
      href: '/parent-links?tab=codes',
    },
    operational.pendingStaffInvites > 0 && {
      icon: 'badge',
      label: `${operational.pendingStaffInvites} staff member${plural(operational.pendingStaffInvites)} hasn't signed in yet`,
      cta: 'View staff',
      href: '/users?filter=pending',
    },
  ].filter(Boolean) as Array<{ icon: string; label: string; cta: string; href: string }>;

  const attentionCount = attentionItems.length;

  const participation = stats.totalStudents > 0
    ? Math.round((weekly.uniqueReaders / stats.totalStudents) * 100)
    : 0;

  // ── Setup checklist — onboarding guidance that disappears once a school is
  // fully set up (its "data-health" half would just duplicate Attention). ─────
  const setupSteps = [
    { label: 'Create your first class', done: operational.totalClasses > 0, href: '/classes' },
    { label: 'Add teachers', done: operational.activeTeachers > 0, href: '/users' },
    { label: 'Add students', done: stats.totalStudents > 0, href: '/students' },
    { label: 'Connect guardians', done: operational.guardiansLinked > 0, href: '/parent-links' },
    { label: 'Set up your library', done: operational.libraryBooks > 0, href: '/library' },
  ];
  const setupDone = setupSteps.filter((s) => s.done).length;
  const setupComplete = setupDone === setupSteps.length;
  const showSetup = !setupComplete;
  const showLibraryCard = operational.incompleteBooks > 0;

  return (
    <div>
      <PageHeader
        eyebrow="Dashboard"
        title={schoolName}
        description="What's happening today and what needs your attention"
        action={
          <Link href="/analytics">
            <Button variant="outline" size="sm">
              <Icon name="insights" size={18} />
              <span className="ml-2">View Analytics</span>
            </Button>
          </Link>
        }
      />

      {/* Overview — structural counts with an operational note in the subtitle */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard
          title="Students"
          value={stats.totalStudents}
          icon={<Icon name="person" />}
          color="blue"
          href="/students"
          subtitle={operational.unassignedStudents > 0 ? `${operational.unassignedStudents} unassigned` : 'all assigned'}
        />
        <StatCard
          title="Staff"
          value={operational.activeStaff}
          icon={<Icon name="badge" />}
          color="blue"
          href="/users"
          subtitle={operational.pendingStaffInvites > 0 ? `${operational.pendingStaffInvites} invite${plural(operational.pendingStaffInvites)} pending` : 'active'}
        />
        <StatCard
          title="Classes"
          value={stats.totalClasses}
          icon={<Icon name="school" />}
          color="blue"
          href="/classes"
          subtitle={operational.classesWithoutTeacher > 0 ? `${operational.classesWithoutTeacher} without staff` : 'all staffed'}
        />
        <StatCard
          title="Needs attention"
          value={attentionCount}
          icon={<Icon name={attentionCount > 0 ? 'notification_important' : 'task_alt'} />}
          color={attentionCount > 0 ? 'orange' : 'green'}
          href="#attention"
          subtitle={attentionCount > 0 ? `item${plural(attentionCount)} to review` : 'all clear'}
        />
      </div>

      {/* Row 1 — the operational core (hero) beside the shortcuts rail. */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start mb-6">
        {/* Attention Required */}
        <Card id="attention" className="lg:col-span-2 scroll-mt-24">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-bold text-ink">Attention required</h2>
            {attentionCount > 0 && <Badge variant="warning">{attentionCount}</Badge>}
          </div>

          {attentionCount === 0 ? (
            <div className="flex flex-col items-center justify-center text-center py-12">
              <span className="inline-flex items-center justify-center w-12 h-12 rounded-full bg-success/10 text-success mb-3">
                <Icon name="task_alt" size={26} />
              </span>
              <p className="text-sm font-bold text-ink">You&apos;re all caught up</p>
              <p className="text-xs text-muted mt-1">No students, classes or invitations need attention.</p>
            </div>
          ) : (
            <div className="space-y-2">
              {attentionItems.map((item) => {
                const section = sectionForPath(item.href.split('?')[0]);
                return (
                  <Link
                    key={`${item.href}-${item.label}`}
                    href={item.href}
                    className="flex items-center gap-3 p-3 rounded-[var(--radius-md)] bg-cream hover:brightness-[0.97] transition"
                  >
                    <span
                      className="inline-flex items-center justify-center w-9 h-9 rounded-[var(--radius-md)] flex-shrink-0"
                      style={{ backgroundColor: `${section.accent}1F`, color: section.accent }}
                    >
                      <Icon name={item.icon} size={20} />
                    </span>
                    <span className="flex-1 min-w-0 text-sm font-semibold text-ink">{item.label}</span>
                    <span
                      className="hidden sm:flex items-center gap-1 text-xs font-bold whitespace-nowrap flex-shrink-0"
                      style={{ color: section.accentStrong }}
                    >
                      {item.cta}
                      <Icon name="arrow_forward" size={14} />
                    </span>
                  </Link>
                );
              })}
            </div>
          )}
        </Card>

        {/* Quick actions — verb-first shortcuts, tinted by destination section */}
        <Card>
          <h2 className="text-lg font-bold text-ink mb-3">Quick actions</h2>
          <div className="grid grid-cols-1 gap-2">
            {quickActions.map((action) => {
              const accent = sectionForPath(action.href).accent;
              return (
                <Link
                  key={action.href + action.label}
                  href={action.href}
                  className="flex items-center gap-3 p-3 rounded-[var(--radius-md)] bg-cream hover:brightness-[0.97] transition"
                >
                  <span
                    className="inline-flex items-center justify-center w-9 h-9 rounded-[var(--radius-md)] flex-shrink-0"
                    style={{ backgroundColor: `${accent}1F`, color: accent }}
                  >
                    <Icon name={action.icon} size={20} />
                  </span>
                  <span className="flex-1 min-w-0 text-sm font-semibold text-ink truncate">{action.label}</span>
                  <Icon name="arrow_forward" size={15} className="text-muted flex-shrink-0" />
                </Link>
              );
            })}
          </div>
        </Card>
      </div>

      {/* Row 2 — reading engagement, widened; Library health tucks alongside so
          neither card is ever stranded in a lonely column. */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start mb-6">
        <Card className={showLibraryCard ? 'lg:col-span-2' : 'lg:col-span-3'}>
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-bold text-ink">Reading this week</h2>
            <Link
              href="/analytics"
              className="inline-flex items-center gap-1 text-sm font-bold text-section-strong hover:underline"
            >
              View full analytics
              <Icon name="arrow_forward" size={15} />
            </Link>
          </div>
          <div className="flex flex-col sm:flex-row sm:items-end gap-6">
            <div className="shrink-0">
              <div className="font-display text-[32px] font-extrabold text-ink leading-none">
                {weekly.minutes.toLocaleString()} <span className="text-base font-bold text-muted">min</span>
              </div>
              <p className="text-xs text-muted mt-2">logged across the school this week</p>
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center justify-between text-sm mb-1.5">
                <span className="font-semibold text-ink">{participation}% participation</span>
                <span className="text-muted">{weekly.uniqueReaders}/{stats.totalStudents} students read</span>
              </div>
              <div className="h-2.5 rounded-full bg-cream overflow-hidden">
                <div
                  className="h-full rounded-full bg-section transition-all"
                  style={{ width: `${Math.min(100, participation)}%` }}
                />
              </div>
            </div>
          </div>
        </Card>

        {showLibraryCard && (
          <Card>
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-lg font-bold text-ink">Library</h2>
              <span className="text-section"><Icon name="menu_book" size={20} /></span>
            </div>
            <div className="font-display text-[28px] font-extrabold text-ink leading-tight">
              {operational.incompleteBooks}
            </div>
            <p className="text-sm text-muted mt-1">
              book{plural(operational.incompleteBooks)} need details — no title or cover yet
            </p>
            <Link
              href="/library?filter=incomplete"
              className="inline-flex items-center gap-1 text-sm font-bold text-section-strong mt-4 hover:underline"
            >
              Review incomplete books
              <Icon name="arrow_forward" size={15} />
            </Link>
          </Card>
        )}
      </div>

      {/* Onboarding setup — full width with a two-column checklist so it fills
          the row instead of leaving a stranded half. Hidden once fully set up. */}
      {showSetup && (
        <Card>
          <div className="flex items-start justify-between mb-3">
            <div>
              <h2 className="text-lg font-bold text-ink">Finish setting up</h2>
              <p className="text-xs text-muted mt-0.5">A few steps to get your school ready</p>
            </div>
            <span className="text-sm font-bold text-section-strong shrink-0">{setupDone}/{setupSteps.length}</span>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1.5">
            {setupSteps.map((step) =>
              step.done ? (
                <div key={step.label} className="flex items-center gap-3 p-2.5">
                  <span className="inline-flex items-center justify-center w-7 h-7 rounded-full bg-success/10 text-success flex-shrink-0">
                    <Icon name="check" size={18} />
                  </span>
                  <span className="flex-1 text-sm font-semibold text-muted line-through">{step.label}</span>
                </div>
              ) : (
                <Link
                  key={step.label}
                  href={step.href}
                  className="flex items-center gap-3 p-2.5 rounded-[var(--radius-md)] bg-cream hover:brightness-[0.97] transition"
                >
                  <span className="inline-flex w-7 h-7 rounded-full border-2 border-rule flex-shrink-0" />
                  <span className="flex-1 text-sm font-semibold text-ink">{step.label}</span>
                  <Icon name="arrow_forward" size={15} className="text-muted" />
                </Link>
              ),
            )}
          </div>
        </Card>
      )}
    </div>
  );
}
