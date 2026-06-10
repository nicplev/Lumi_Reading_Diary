'use client';

import { useEffect, useState } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { useFetchStaffCredential, useResendStaffEmail } from '@/lib/hooks/use-users';
import { useToast } from '@/components/lumi/toast';

interface ViewCredentialsModalProps {
  open: boolean;
  onClose: () => void;
  user: { id: string; fullName: string; email: string } | null;
}

export function ViewCredentialsModal({ open, onClose, user }: ViewCredentialsModalProps) {
  const { toast } = useToast();
  const fetchCredential = useFetchStaffCredential();
  const resendEmail = useResendStaffEmail();

  const [tempPassword, setTempPassword] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const { mutateAsync: fetchCred } = fetchCredential;

  useEffect(() => {
    if (!open || !user) return;
    setTempPassword(null);
    setError(null);
    fetchCred(user.id)
      .then((res) => setTempPassword(res.tempPassword))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load credentials'));
  }, [open, user, fetchCred]);

  const copy = async (text: string, label: string) => {
    try {
      await navigator.clipboard.writeText(text);
      toast(`${label} copied`, 'success');
    } catch {
      toast('Failed to copy', 'error');
    }
  };

  const handleResend = async () => {
    if (!user) return;
    try {
      await resendEmail.mutateAsync({ targetUserIds: [user.id] });
      toast('Login email re-sent', 'success');
    } catch (err) {
      toast(err instanceof Error ? err.message : 'Failed to send email', 'error');
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Login credentials"
      description={user ? `${user.fullName} · ${user.email}` : undefined}
      size="sm"
      footer={
        <>
          <Button variant="outline" onClick={onClose}>Close</Button>
          {tempPassword && (
            <Button onClick={handleResend} loading={resendEmail.isPending}>Resend login email</Button>
          )}
        </>
      }
    >
      {fetchCredential.isPending && (
        <p className="text-sm text-text-secondary py-6 text-center">Loading…</p>
      )}

      {!fetchCredential.isPending && error && (
        <div className="bg-background border border-divider rounded-[var(--radius-md)] px-4 py-3 text-sm text-text-secondary">
          {error}
        </div>
      )}

      {!fetchCredential.isPending && tempPassword && user && (
        <div className="space-y-3">
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wide text-text-secondary mb-1">Email</label>
            <div className="flex items-center gap-2">
              <code className="flex-1 bg-background border border-divider px-3 py-2 rounded-[var(--radius-md)] text-sm text-charcoal break-all">{user.email}</code>
              <Button variant="ghost" size="sm" onClick={() => copy(user.email, 'Email')}>Copy</Button>
            </div>
          </div>
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wide text-text-secondary mb-1">Temporary password</label>
            <div className="flex items-center gap-2">
              <code className="flex-1 bg-background border border-divider px-3 py-2 rounded-[var(--radius-md)] text-sm font-mono text-charcoal">{tempPassword}</code>
              <Button variant="ghost" size="sm" onClick={() => copy(tempPassword, 'Password')}>Copy</Button>
            </div>
          </div>
          <p className="text-xs text-text-secondary">
            This temporary password is hidden automatically once {user.fullName} logs in for the first time.
          </p>
        </div>
      )}
    </Modal>
  );
}
