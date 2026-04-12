import { Sidebar } from '@/components/layout/sidebar';
import { Header } from '@/components/layout/header';
import { MobileNav } from '@/components/layout/mobile-nav';
import { SchoolThemeProvider } from '@/components/providers/school-theme-provider';
import { BreadcrumbProvider } from '@/components/layout/breadcrumb-context';
import { getSession } from '@/lib/auth/session';
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

  return (
    <SchoolThemeProvider initialColors={initialColors}>
    <BreadcrumbProvider>
      <div className="min-h-screen bg-background">
        {/* Desktop sidebar */}
        <div className="hidden lg:block">
          <Sidebar />
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
    </BreadcrumbProvider>
    </SchoolThemeProvider>
  );
}
