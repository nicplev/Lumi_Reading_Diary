import { Sidebar } from '@/components/layout/sidebar';
import { Header } from '@/components/layout/header';
import { MobileNav } from '@/components/layout/mobile-nav';
import { ImpersonationBanner } from '@/components/layout/impersonation-banner';
import { ImpersonationWatermark } from '@/components/layout/impersonation-watermark';
import { SchoolThemeProvider } from '@/components/providers/school-theme-provider';
import { RouteSectionScope } from '@/components/lumi/section-scope';
import { BreadcrumbProvider } from '@/components/layout/breadcrumb-context';
import { getSession } from '@/lib/auth/session';
import { hasDevAccess } from '@/lib/auth/dev-access';
import { getSchool } from '@/lib/firestore/school';

export default async function AuthenticatedLayout({ children }: { children: React.ReactNode }) {
  const session = await getSession();
  let initialColors: { primary: string; secondary: string } | undefined;
  if (session) {
    const school = await getSchool(session.schoolId);
    if (school?.primaryColor && school?.secondaryColor) {
      initialColors = { primary: school.primaryColor, secondary: school.secondaryColor };
    }
  }

  const impersonation = session?.impersonation;
  // Dev-access is an allowlist lookup; skip it when impersonating since the
  // dev is already inside a session.
  const showDevTools = session && !impersonation
    ? await hasDevAccess(session.email)
    : false;

  return (
    <SchoolThemeProvider initialColors={initialColors}>
    <BreadcrumbProvider>
      {impersonation && (
        <ImpersonationBanner
          sessionId={impersonation.sessionId}
          schoolName={impersonation.schoolName}
          role={session!.role}
          expiresAt={impersonation.expiresAt}
        />
      )}
      <div className="min-h-screen bg-cream">
        {/* Desktop sidebar */}
        <div className="hidden lg:block">
          <Sidebar hasDevAccess={showDevTools} />
        </div>

        {/* Main content — RouteSectionScope themes everything by the current
            route, so each page's accent (and the design-system widgets within)
            follows the section colour automatically. */}
        <div className="lg:ml-[240px]">
          <Header />
          <RouteSectionScope>
            <main className="p-4 pb-[calc(5.5rem+env(safe-area-inset-bottom))] sm:p-6 sm:pb-24 lg:pb-6">
              {children}
            </main>
          </RouteSectionScope>
        </div>

        {/* Mobile bottom nav */}
        <MobileNav />
      </div>
      {impersonation && session && (
        <ImpersonationWatermark
          devEmail={session.email}
          schoolName={impersonation.schoolName}
          startedAt={impersonation.startedAt}
        />
      )}
    </BreadcrumbProvider>
    </SchoolThemeProvider>
  );
}
