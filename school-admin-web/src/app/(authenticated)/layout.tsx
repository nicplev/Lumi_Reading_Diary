import { Sidebar } from '@/components/layout/sidebar';
import { Header } from '@/components/layout/header';
import { MobileNav } from '@/components/layout/mobile-nav';
import { ImpersonationBanner } from '@/components/layout/impersonation-banner';
import { ImpersonationWatermark } from '@/components/layout/impersonation-watermark';
import { SchoolThemeProvider } from '@/components/providers/school-theme-provider';
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
      <div className="min-h-screen bg-background">
        {/* Desktop sidebar */}
        <div className="hidden lg:block">
          <Sidebar hasDevAccess={showDevTools} />
        </div>

        {/* Main content */}
        <div className="lg:ml-[240px]">
          <Header />
          <main className="p-6 pb-24 lg:pb-6">
            {children}
          </main>
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
