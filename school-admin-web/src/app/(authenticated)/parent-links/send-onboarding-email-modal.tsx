'use client';

import { useState, useMemo } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { useToast } from '@/components/lumi/toast';
import { useSendOnboardingEmails } from '@/lib/hooks/use-onboarding-emails';

interface SendOnboardingEmailModalProps {
  open: boolean;
  onClose: () => void;
  selectedStudentIds: string[];
  students: Array<{
    id: string;
    firstName: string;
    lastName: string;
    parentEmail?: string;
    enrollmentStatus?: string;
    parentIds: string[];
  }>;
  onSuccess: () => void;
}

export function SendOnboardingEmailModal({
  open,
  onClose,
  selectedStudentIds,
  students,
  onSuccess,
}: SendOnboardingEmailModalProps) {
  const { toast } = useToast();
  const sendEmails = useSendOnboardingEmails();

  const [customMessage, setCustomMessage] = useState('');
  const [emailSubject, setEmailSubject] = useState('Welcome to Lumi Reading Tracker');
  const [generateMissingCodes, setGenerateMissingCodes] = useState(true);

  const summary = useMemo(() => {
    const selected = students.filter((s) => selectedStudentIds.includes(s.id));
    const total = selected.length;

    const noEmail = selected.filter((s) => !s.parentEmail);
    const notEnrolled = selected.filter(
      (s) =>
        !!s.parentEmail &&
        s.enrollmentStatus !== 'book_pack' &&
        s.enrollmentStatus !== 'direct_purchase'
    );
    const alreadyLinked = selected.filter(
      (s) =>
        !!s.parentEmail &&
        (s.enrollmentStatus === 'book_pack' || s.enrollmentStatus === 'direct_purchase') &&
        s.parentIds.length > 0
    );

    const willReceive = selected.filter(
      (s) =>
        !!s.parentEmail &&
        (s.enrollmentStatus === 'book_pack' || s.enrollmentStatus === 'direct_purchase') &&
        s.parentIds.length === 0
    );

    const skipped = noEmail.length + notEnrolled.length + alreadyLinked.length;

    return { total, willReceive: willReceive.length, skipped, noEmail: noEmail.length, notEnrolled: notEnrolled.length, alreadyLinked: alreadyLinked.length };
  }, [students, selectedStudentIds]);

  const handleSend = async () => {
    if (summary.willReceive === 0) {
      toast('No eligible students to send emails to', 'error');
      return;
    }

    try {
      await sendEmails.mutateAsync({
        targetStudentIds: selectedStudentIds,
        emailSubject: emailSubject.trim() || undefined,
        customMessage: customMessage.trim() || undefined,
        generateMissingCodes,
      });
      toast(`Onboarding emails queued for ${summary.willReceive} student${summary.willReceive !== 1 ? 's' : ''}`, 'success');
      setCustomMessage('');
      setEmailSubject('Welcome to Lumi Reading Tracker');
      setGenerateMissingCodes(true);
      onSuccess();
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to send emails', 'error');
    }
  };

  const handleClose = () => {
    if (!sendEmails.isPending) {
      onClose();
    }
  };

  return (
    <Modal
      open={open}
      onClose={handleClose}
      title="Send Onboarding Emails"
      description="Review the recipients and customize your email before sending."
      size="md"
      footer={
        <>
          <Button variant="outline" onClick={handleClose} disabled={sendEmails.isPending}>
            Cancel
          </Button>
          <Button
            onClick={handleSend}
            loading={sendEmails.isPending}
            disabled={summary.willReceive === 0}
          >
            Send {summary.willReceive > 0 ? `${summary.willReceive} ` : ''}Email{summary.willReceive !== 1 ? 's' : ''}
          </Button>
        </>
      }
    >
      <div className="space-y-5">
        {/* Summary stats */}
        <div className="space-y-2">
          <div className="flex items-center justify-between py-2 px-3 bg-background rounded-[var(--radius-md)]">
            <span className="text-sm text-text-secondary">Students selected</span>
            <span className="text-sm font-bold text-charcoal">{summary.total}</span>
          </div>
          <div className="flex items-center justify-between py-2 px-3 bg-mint-green/10 rounded-[var(--radius-md)]">
            <span className="text-sm text-text-secondary">Will receive emails</span>
            <Badge variant="success">{summary.willReceive}</Badge>
          </div>
          {summary.skipped > 0 && (
            <div className="py-2 px-3 bg-background rounded-[var(--radius-md)]">
              <div className="flex items-center justify-between mb-1">
                <span className="text-sm text-text-secondary">Will be skipped</span>
                <Badge variant="warning">{summary.skipped}</Badge>
              </div>
              <div className="space-y-0.5 ml-2">
                {summary.noEmail > 0 && (
                  <p className="text-xs text-text-secondary">
                    {summary.noEmail} without parent email
                  </p>
                )}
                {summary.notEnrolled > 0 && (
                  <p className="text-xs text-text-secondary">
                    {summary.notEnrolled} not confirmed
                  </p>
                )}
                {summary.alreadyLinked > 0 && (
                  <p className="text-xs text-text-secondary">
                    {summary.alreadyLinked} already linked to a parent
                  </p>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Email subject */}
        <div>
          <label className="block text-sm font-semibold text-charcoal mb-1.5">
            Email Subject
          </label>
          <input
            type="text"
            value={emailSubject}
            onChange={(e) => setEmailSubject(e.target.value)}
            placeholder="Welcome to Lumi Reading Tracker"
            className="w-full px-3 py-2.5 rounded-[var(--radius-md)] border border-divider bg-surface text-charcoal placeholder:text-text-secondary/50 focus:outline-none focus:ring-2 focus:ring-rose-pink/30 focus:border-rose-pink transition-colors text-[15px]"
          />
        </div>

        {/* Custom message */}
        <div>
          <label className="block text-sm font-semibold text-charcoal mb-1.5">
            Custom Message <span className="text-text-secondary font-normal">(optional)</span>
          </label>
          <textarea
            value={customMessage}
            onChange={(e) => setCustomMessage(e.target.value)}
            placeholder="Add a personal note to include in the email..."
            rows={3}
            className="w-full px-3 py-2.5 rounded-[var(--radius-md)] border border-divider bg-surface text-charcoal placeholder:text-text-secondary/50 focus:outline-none focus:ring-2 focus:ring-rose-pink/30 focus:border-rose-pink transition-colors text-[15px] resize-none"
          />
        </div>

        {/* Generate missing codes checkbox */}
        <label className="flex items-start gap-3 cursor-pointer">
          <input
            type="checkbox"
            checked={generateMissingCodes}
            onChange={(e) => setGenerateMissingCodes(e.target.checked)}
            className="w-4 h-4 mt-0.5 rounded border-divider text-rose-pink focus:ring-rose-pink/30"
          />
          <div>
            <p className="text-sm font-semibold text-charcoal">
              Generate link codes for students without one
            </p>
            <p className="text-xs text-text-secondary mt-0.5">
              Students need a link code for parents to connect. New codes will be created automatically.
            </p>
          </div>
        </label>
      </div>
    </Modal>
  );
}
