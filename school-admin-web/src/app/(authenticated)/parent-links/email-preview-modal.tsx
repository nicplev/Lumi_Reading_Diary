'use client';

import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';

interface EmailPreviewModalProps {
  open: boolean;
  onClose: () => void;
  schoolName?: string;
}

export function EmailPreviewModal({ open, onClose, schoolName }: EmailPreviewModalProps) {
  const displaySchoolName = schoolName || 'Your School';

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Email Preview"
      description="This is a sample of what parents will receive."
      size="lg"
      footer={
        <Button variant="outline" onClick={onClose}>
          Close
        </Button>
      }
    >
      <div className="border border-divider rounded-[var(--radius-md)] overflow-hidden">
        {/* Email preview */}
        <div className="bg-[#f5f5f5] p-6">
          <div className="max-w-md mx-auto bg-white rounded-lg shadow-sm overflow-hidden">
            {/* Header */}
            <div className="bg-[#E91E63] px-6 py-5 text-center">
              <h2 className="text-white text-xl font-bold tracking-tight">
                Lumi Reading Tracker
              </h2>
              <p className="text-white/80 text-sm mt-1">{displaySchoolName}</p>
            </div>

            {/* Body */}
            <div className="px-6 py-6">
              <h3 className="text-[#2C2C2C] text-lg font-bold mb-3">
                Welcome to Lumi Reading Tracker!
              </h3>
              <p className="text-[#666] text-sm leading-relaxed mb-4">
                Your child&apos;s school uses Lumi to track reading progress. You&apos;re invited
                to connect your account so you can log reading sessions, track achievements, and
                stay in touch with your child&apos;s reading journey.
              </p>

              <p className="text-[#666] text-sm leading-relaxed mb-4">
                <span className="italic text-[#999]">
                  [Your custom message will appear here]
                </span>
              </p>

              {/* Link code */}
              <div className="bg-[#FFF3E0] border border-[#FFE0B2] rounded-lg p-4 text-center mb-5">
                <p className="text-xs text-[#999] uppercase tracking-wider font-semibold mb-2">
                  Your Link Code
                </p>
                <p className="text-2xl font-mono font-bold text-[#2C2C2C] tracking-[0.2em]">
                  ABC12345
                </p>
              </div>

              {/* Steps */}
              <h4 className="text-[#2C2C2C] text-sm font-bold mb-3">
                Getting Started
              </h4>
              <div className="space-y-3 mb-5">
                {[
                  { step: '1', text: 'Download the Lumi Reading Tracker app from the App Store' },
                  { step: '2', text: 'Create your parent account using your email address' },
                  { step: '3', text: 'Enter the link code above to connect to your child' },
                  { step: '4', text: 'Start logging reading sessions together!' },
                ].map((item) => (
                  <div key={item.step} className="flex items-start gap-3">
                    <span className="flex-shrink-0 w-6 h-6 rounded-full bg-[#E91E63] text-white text-xs font-bold flex items-center justify-center">
                      {item.step}
                    </span>
                    <p className="text-[#666] text-sm leading-relaxed pt-0.5">
                      {item.text}
                    </p>
                  </div>
                ))}
              </div>

              <p className="text-[#999] text-xs leading-relaxed">
                This code is valid for 1 year. If you have any questions, please contact your
                child&apos;s teacher or school admin.
              </p>
            </div>

            {/* Footer */}
            <div className="border-t border-[#eee] px-6 py-4 text-center">
              <p className="text-[#999] text-xs">
                Sent by {displaySchoolName} via Lumi Reading Tracker
              </p>
            </div>
          </div>
        </div>
      </div>
    </Modal>
  );
}
