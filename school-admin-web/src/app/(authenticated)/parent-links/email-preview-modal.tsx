'use client';

import { useEffect } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { usePreviewOnboardingEmail } from '@/lib/hooks/use-onboarding-emails';

interface EmailPreviewModalProps {
  open: boolean;
  onClose: () => void;
}

/**
 * Previews the REAL onboarding email — renders the same template parents
 * receive (via /api/onboarding-emails/preview → buildOnboardingEmailPreview)
 * inside a sandboxed iframe, so the portal preview never drifts from the
 * actual email.
 */
export function EmailPreviewModal({ open, onClose }: EmailPreviewModalProps) {
  const { mutate, data, isPending, error, reset } = usePreviewOnboardingEmail();

  // Render the email fresh each time the modal opens (uses example data +
  // the school's real name, server-side).
  useEffect(() => {
    if (open) {
      mutate({});
    } else {
      reset();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Email Preview"
      description="A live preview of what parents will receive."
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
            title="Onboarding email preview"
            srcDoc={data.html}
            sandbox=""
            className="block w-full h-[70vh] border-0 bg-cream"
          />
        )}
      </div>
    </Modal>
  );
}
