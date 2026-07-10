import { redirect } from 'next/navigation';

// Preserve old bookmarks while keeping roster changes and access grants in the
// single guided School Year Transition workflow.
export default function RenewalsRoute() {
  redirect('/students/rollover');
}
