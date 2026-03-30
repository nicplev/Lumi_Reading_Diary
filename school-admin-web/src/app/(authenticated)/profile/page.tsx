'use client';

import { useAuth } from '@/lib/auth/auth-context';
import { Card } from '@/components/lumi/card';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { Avatar } from '@/components/lumi/avatar';
import { Badge } from '@/components/lumi/badge';

export default function ProfilePage() {
  const { user, logout } = useAuth();

  if (!user) return null;

  return (
    <div className="max-w-2xl">
      <PageHeader title="Profile" />
      <Card>
        <div className="flex items-center gap-4 mb-6">
          <Avatar name={user.fullName} size="lg" />
          <div>
            <h2 className="text-[22px] font-bold text-charcoal">{user.fullName}</h2>
            <p className="text-sm text-text-secondary">{user.email}</p>
            <Badge variant={user.role === 'schoolAdmin' ? 'info' : 'success'} className="mt-1">
              {user.role === 'schoolAdmin' ? 'School Admin' : 'Teacher'}
            </Badge>
          </div>
        </div>
        <div className="border-t border-divider pt-4">
          <Button variant="outline" onClick={logout}>
            Sign Out
          </Button>
        </div>
      </Card>
    </div>
  );
}
