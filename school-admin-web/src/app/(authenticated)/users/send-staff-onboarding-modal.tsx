'use client';

import { useState, useMemo } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { useToast } from '@/components/lumi/toast';
import { useSendStaffOnboardingEmails } from '@/lib/hooks/use-staff-onboarding-emails';

interface StaffRow {
  id: string;
  fullName: string;
  email: string;
  role: 'teacher' | 'schoolAdmin';
  lastLoginAt: string | null;
}

const DEFAULT_SUBJECT = 'Your Lumi staff account';

export function SendStaffOnboardingModal({
  open,
  onClose,
  selectedUserIds,
  staff,
  onSuccess,
}: {
  open: boolean;
  onClose: () => void;
  selectedUserIds: string[];
  staff: StaffRow[];
  onSuccess: () => void;
}) {
  const { toast } = useToast();
  const sendEmails = useSendStaffOnboardingEmails();

  const [customMessage, setCustomMessage] = useState('');
  const [emailSubject, setEmailSubject] = useState(DEFAULT_SUBJECT);

  const summary = useMemo(() => {
    const selected = staff.filter((s) => selectedUserIds.includes(s.id));
    const noEmail = selected.filter((s) => !s.email).length;
    const alreadyActive = selected.filter((s) => !!s.email && !!s.lastLoginAt).length;
    const willReceive = selected.filter((s) => !!s.email).length;
    return { total: selected.length, willReceive, noEmail, alreadyActive };
  }, [staff, selectedUserIds]);

  const handleSend = async () => {
    if (summary.willReceive === 0) {
      toast('No staff with an email address to send to', 'error');
      return;
    }
    try {
      await sendEmails.mutateAsync({
        targetUserIds: selectedUserIds,
        emailSubject: emailSubject.trim() || undefined,
        customMessage: customMessage.trim() || undefined,
      });
      toast(`Onboarding emails queued for ${summary.willReceive} staff member${summary.willReceive !== 1 ? 's' : ''}`, 'success');
      setCustomMessage('');
      setEmailSubject(DEFAULT_SUBJECT);
      onSuccess();
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to send emails', 'error');
    }
  };

  const handleClose = () => {
    if (!sendEmails.isPending) onClose();
  };

  return (
    <Modal
      open={open}
      onClose={handleClose}
      title="Send Onboarding Emails"
      description="Review the recipients and customise your email before sending."
      size="md"
      footer={
        <>
          <Button variant="outline" onClick={handleClose} disabled={sendEmails.isPending}>
            Cancel
          </Button>
          <Button onClick={handleSend} loading={sendEmails.isPending} disabled={summary.willReceive === 0}>
            Send {summary.willReceive > 0 ? `${summary.willReceive} ` : ''}Email{summary.willReceive !== 1 ? 's' : ''}
          </Button>
        </>
      }
    >
      <div className="space-y-5">
        {/* Summary */}
        <div className="space-y-2">
          <div className="flex items-center justify-between py-2 px-3 bg-cream rounded-[var(--radius-md)]">
            <span className="text-sm text-muted">Staff selected</span>
            <span className="text-sm font-bold text-ink">{summary.total}</span>
          </div>
          <div className="flex items-center justify-between py-2 px-3 bg-lumi-green/10 rounded-[var(--radius-md)]">
            <span className="text-sm text-muted">Will receive emails</span>
            <Badge variant="success">{summary.willReceive}</Badge>
          </div>
          {summary.noEmail > 0 && (
            <div className="flex items-center justify-between py-2 px-3 bg-cream rounded-[var(--radius-md)]">
              <span className="text-sm text-muted">Skipped — no email address</span>
              <Badge variant="warning">{summary.noEmail}</Badge>
            </div>
          )}
          {summary.alreadyActive > 0 && (
            <p className="text-xs text-muted px-1">
              {summary.alreadyActive} of these have already signed in — they&apos;ll get the school code and
              getting-started steps, without a password.
            </p>
          )}
        </div>

        {/* Subject */}
        <div>
          <label className="block text-sm font-semibold text-ink mb-1.5">Email Subject</label>
          <input
            type="text"
            value={emailSubject}
            onChange={(e) => setEmailSubject(e.target.value)}
            placeholder={DEFAULT_SUBJECT}
            className="w-full px-3 py-2.5 rounded-[var(--radius-md)] border border-rule bg-paper text-ink placeholder:text-muted/50 focus:outline-none focus:ring-2 focus:ring-section/30 focus:border-section transition-colors text-[15px]"
          />
        </div>

        {/* Custom message */}
        <div>
          <label className="block text-sm font-semibold text-ink mb-1.5">
            Custom Message <span className="text-muted font-normal">(optional)</span>
          </label>
          <textarea
            value={customMessage}
            onChange={(e) => setCustomMessage(e.target.value)}
            placeholder="Add a personal note to include in the email..."
            rows={3}
            className="w-full px-3 py-2.5 rounded-[var(--radius-md)] border border-rule bg-paper text-ink placeholder:text-muted/50 focus:outline-none focus:ring-2 focus:ring-section/30 focus:border-section transition-colors text-[15px] resize-none"
          />
        </div>
      </div>
    </Modal>
  );
}
