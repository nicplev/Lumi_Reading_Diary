import { Sidebar } from '@/components/layout/sidebar';
import { Header } from '@/components/layout/header';
import { MobileNav } from '@/components/layout/mobile-nav';
import { SchoolThemeProvider } from '@/components/providers/school-theme-provider';

export default function AuthenticatedLayout({ children }: { children: React.ReactNode }) {
  return (
    <SchoolThemeProvider>
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
    </SchoolThemeProvider>
  );
}
