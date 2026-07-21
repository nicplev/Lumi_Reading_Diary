import assert from "node:assert/strict";
import test from "node:test";
import { ATTENTION_ROUTES } from "./attention-routes.ts";

test("every dashboard attention signal has a focused action route", () => {
  assert.deepEqual(ATTENTION_ROUTES, {
    failedCampaigns: "/operations/delivery?kind=notification&status=open",
    failedOnboardingEmails: "/operations/delivery?kind=onboarding&status=open",
    invalidReadingLogs: "/reading-logs?validation=invalid&review=open",
    pendingDeletionRequests: "/community-books?tab=deletion-requests",
    newFeedback: "/feedback?status=new",
    newLeads: "/onboarding?view=leads",
    pendingUserDeletions: "/operations/deletions?status=cooling-off",
    failedDeletionJobs: "/operations/deletions?status=manual-review",
  });
});

test("attention routes are internal and never point at broad school listing", () => {
  for (const route of Object.values(ATTENTION_ROUTES)) {
    assert.match(route, /^\/(?!\/)/);
    assert.notEqual(route, "/schools");
  }
});
