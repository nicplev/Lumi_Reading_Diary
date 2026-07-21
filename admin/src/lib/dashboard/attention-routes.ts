export const ATTENTION_ROUTES = {
  failedCampaigns: "/operations/delivery?kind=notification&status=open",
  failedOnboardingEmails: "/operations/delivery?kind=onboarding&status=open",
  invalidReadingLogs: "/reading-logs?validation=invalid&review=open",
  pendingDeletionRequests: "/community-books?tab=deletion-requests",
  newFeedback: "/feedback?status=new",
  newLeads: "/onboarding?view=leads",
  pendingUserDeletions: "/operations/deletions?status=cooling-off",
  failedDeletionJobs: "/operations/deletions?status=manual-review",
} as const;
