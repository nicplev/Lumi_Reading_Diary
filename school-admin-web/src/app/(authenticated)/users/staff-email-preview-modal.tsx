'use client';

import { useEffect } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { usePreviewStaffOnboardingEmail } from '@/lib/hooks/use-staff-onboarding-emails';

/**
 * Previews the real staff onboarding email — renders the same template staff
 * receive (via /api/staff-onboarding-emails/preview) in a sandboxed iframe.
 */
export function StaffEmailPreviewModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { mutate, data, isPending, error, reset } = usePreviewStaffOnboardingEmail();

  useEffect(() => {
    if (open) mutate({});
    else reset();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Email Preview"
      description="A live preview of what staff will receive."
      size="lg"
      footer={
        <Button variant="outline" onClick={onClose}>
          Close
        </Button>
      }
    >
      <div className="rounded-[var(--radius-md)] overflow-hidden border border-rule bg-cream">
        {isPending && (
          <div className="h-[60vh] flex items-center justify-center text-sm text-muted">
            Generating preview…
          </div>
        )}
        {error && !isPending && (
          <div className="h-[40vh] flex items-center justify-center px-6 text-center text-sm text-error">
            Couldn&apos;t generate the preview. {error.message}
          </div>
        )}
        {data?.html && !isPending && (
          <iframe
            title="Staff onboarding email preview"
            srcDoc={data.html}
            sandbox=""
            className="block w-full h-[70vh] border-0 bg-cream"
          />
        )}
      </div>
    </Modal>
  );
}
