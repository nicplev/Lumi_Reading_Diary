'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { httpsCallable } from 'firebase/functions';
import { functions } from '@/lib/firebase/client';
import { Button } from '@/components/lumi/button';
import { Select } from '@/components/lumi/select';

interface School {
  schoolId: string;
  name: string;
  teacherCount: number;
}

interface User {
  userId: string;
  email: string;
  fullName: string;
  role: string;
}

type Role = 'teacher' | 'schoolAdmin';

export function ImpersonationPicker() {
  const router = useRouter();

  const [schools, setSchools] = useState<School[]>([]);
  const [users, setUsers] = useState<User[]>([]);
  const [schoolId, setSchoolId] = useState('');
  const [role, setRole] = useState<Role>('teacher');
  const [userId, setUserId] = useState('');
  const [reason, setReason] = useState('');
  const [loadingSchools, setLoadingSchools] = useState(true);
  const [loadingUsers, setLoadingUsers] = useState(false);
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const callable = httpsCallable<
          Record<string, never>,
          { schools: School[] }
        >(functions, 'listImpersonableSchools');
        const result = await callable({});
        setSchools(result.data.schools ?? []);
      } catch (e) {
        setError(
          e instanceof Error ? `Could not load schools: ${e.message}` : 'Could not load schools.',
        );
      } finally {
        setLoadingSchools(false);
      }
    })();
  }, []);

  useEffect(() => {
    if (!schoolId) {
      setUsers([]);
      setUserId('');
      return;
    }
    setLoadingUsers(true);
    setUsers([]);
    setUserId('');
    (async () => {
      try {
        const callable = httpsCallable<
          { schoolId: string; role: Role },
          { users: User[] }
        >(functions, 'listImpersonableUsers');
        const result = await callable({ schoolId, role });
        setUsers(result.data.users ?? []);
      } catch (e) {
        setError(
          e instanceof Error ? `Could not load users: ${e.message}` : 'Could not load users.',
        );
      } finally {
        setLoadingUsers(false);
      }
    })();
  }, [schoolId, role]);

  const canStart =
    schoolId.length > 0 &&
    userId.length > 0 &&
    reason.trim().length >= 20 &&
    !starting;

  const handleStart = async () => {
    setStarting(true);
    setError(null);
    try {
      const callable = httpsCallable<
        {
          targetSchoolId: string;
          targetUserId: string;
          targetRole: Role;
          reason: string;
          clientInfo: { platform: string; appVersion: null };
        },
        { sessionId: string; customToken: string; expiresAt: number }
      >(functions, 'startImpersonationSession');

      const { data } = await callable({
        targetSchoolId: schoolId,
        targetUserId: userId,
        targetRole: role,
        reason: reason.trim(),
        clientInfo: { platform: 'web', appVersion: null },
      });

      // Hand the freshly created session ID to the server so it can rewrite
      // the JWT cookie with the impersonation block.
      const response = await fetch('/api/dev/impersonate/start', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ sessionId: data.sessionId }),
      });
      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        throw new Error(body.error ?? `Server rejected session (${response.status})`);
      }

      // Force a full-navigation refresh so the authenticated layout re-reads
      // the cookie and mounts the impersonation banner.
      window.location.href = '/dashboard';
    } catch (e) {
      setError(
        e instanceof Error ? e.message : 'Failed to start impersonation session.',
      );
      setStarting(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-charcoal mb-2">
          Impersonate a school (read-only)
        </h1>
        <p className="text-sm text-charcoal/70">
          Every session and action is recorded to the super-admin audit trail.
          Writes are blocked server-side and by Firestore rules. Sessions expire
          after 30 minutes.
        </p>
      </div>

      <div className="space-y-5 bg-white border border-divider rounded-[var(--radius-md)] p-6 shadow-card">
        <Select
          label="School"
          value={schoolId}
          onChange={(v) => setSchoolId(v)}
          placeholder={loadingSchools ? 'Loading schools…' : 'Select a school'}
          disabled={loadingSchools}
          options={schools.map((s) => ({
            value: s.schoolId,
            label: `${s.name} (${s.teacherCount} teachers)`,
          }))}
        />

        <div>
          <label className="block text-sm font-semibold text-charcoal mb-1.5">
            Role
          </label>
          <div className="inline-flex rounded-[var(--radius-md)] border border-divider overflow-hidden">
            {(['teacher', 'schoolAdmin'] as const).map((r) => (
              <button
                key={r}
                type="button"
                onClick={() => setRole(r)}
                className={`px-4 py-2 text-sm ${
                  role === r
                    ? 'bg-brand-primary text-white'
                    : 'bg-white text-charcoal hover:bg-background'
                }`}
              >
                {r === 'teacher' ? 'Teacher' : 'School admin'}
              </button>
            ))}
          </div>
        </div>

        <Select
          label="User"
          value={userId}
          onChange={(v) => setUserId(v)}
          placeholder={
            !schoolId
              ? 'Pick a school first'
              : loadingUsers
                ? 'Loading users…'
                : users.length === 0
                  ? `No ${role === 'teacher' ? 'teachers' : 'school admins'} found`
                  : 'Select a user'
          }
          disabled={loadingUsers || !schoolId || users.length === 0}
          options={users.map((u) => ({
            value: u.userId,
            label: u.fullName ? `${u.fullName} <${u.email}>` : u.email,
          }))}
        />

        <div>
          <label className="block text-sm font-semibold text-charcoal mb-1.5">
            Reason{' '}
            <span className="text-xs font-normal text-charcoal/60">
              (min 20 characters)
            </span>
          </label>
          <textarea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            rows={3}
            maxLength={500}
            placeholder="e.g. Reproducing reading log bug reported in ticket #123"
            className="w-full rounded-[var(--radius-sm)] border border-divider px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
          />
          <p className="text-xs text-charcoal/60 mt-1">
            {reason.trim().length}/500 — stored verbatim in the audit log.
          </p>
        </div>

        {error && (
          <div className="rounded-[var(--radius-sm)] border border-error/40 bg-error/5 p-3 text-sm text-error">
            {error}
          </div>
        )}

        <div className="flex items-center justify-end gap-3 pt-2">
          <Button
            variant="outline"
            onClick={() => router.push('/dashboard')}
            disabled={starting}
          >
            Cancel
          </Button>
          <Button
            variant="danger"
            onClick={handleStart}
            disabled={!canStart}
            loading={starting}
          >
            Start read-only session (30 min)
          </Button>
        </div>
      </div>
    </div>
  );
}
