'use client';

import { Joyride, STATUS, type EventData, type Step } from 'react-joyride';

const STEPS: Step[] = [
  {
    target: 'body',
    placement: 'center',
    title: 'Onboard parents in 3 steps',
    content:
      "Mark who's paying, send the invite, then track who's connected — all from this page. Here's how it works.",
  },
  {
    target: '[data-tour="status-chips"]',
    title: 'Where each parent stands',
    content:
      'Every student moves Not Subscribed → Subscribed → Linked. "To onboard" (the default) is everyone not yet linked. Tap a chip to filter the list.',
  },
  {
    target: '[data-tour="student-table"]',
    placement: 'top',
    title: 'Step 1 — mark paying students Subscribed',
    content:
      "When a parent has paid, tap that student's status and choose Subscribed. They're then ready to invite — no need to visit the Students page.",
  },
  {
    target: '[data-tour="student-table"]',
    placement: 'top',
    title: 'Step 2 — select, then send',
    content:
      'Tick the students you want, then use Send Onboarding Emails. Each parent receives a private link to connect to their child in the app.',
  },
  {
    target: '[data-tour="preview-email"]',
    title: 'Preview the email',
    content: 'See exactly what parents will receive before you send anything.',
  },
  {
    target: '[data-tour="take-tour"]',
    title: 'Replay anytime',
    content: 'Need a refresher later? Reopen this tour from here whenever you like.',
  },
];

interface OnboardingTourProps {
  /** Whether the tour is playing. */
  run: boolean;
  /** Called when the tour is finished or skipped, so the parent can stop it and persist "seen". */
  onClose: () => void;
}

/**
 * Guided product tour for the Parent Onboarding page (react-joyride v3).
 *
 * Auto-launches on a user's first visit and can be replayed via the
 * "Take a tour" button — the run/persistence wiring lives in ParentOnboardingTab.
 * Steps target elements by their `data-tour="…"` attribute.
 */
export function OnboardingTour({ run, onClose }: OnboardingTourProps) {
  return (
    <Joyride
      steps={STEPS}
      run={run}
      continuous
      scrollToFirstStep
      onEvent={(data: EventData) => {
        if (data.status === STATUS.FINISHED || data.status === STATUS.SKIPPED) {
          onClose();
        }
      }}
      options={{
        primaryColor: '#EC4544', // Lumi section accent
        zIndex: 10_000,
        showProgress: true,
        spotlightPadding: 6,
        buttons: ['back', 'skip', 'primary'],
      }}
    />
  );
}
