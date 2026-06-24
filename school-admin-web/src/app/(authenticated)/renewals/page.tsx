import { redirect } from 'next/navigation';

// Renewals now lives as an admin-only tab inside Settings (it's a once-a-year
// tool, so it no longer warrants a primary sidebar item). This route forwards
// there so any old links/bookmarks keep working.
export default function RenewalsRoute() {
  redirect('/settings?tab=renewals');
}
