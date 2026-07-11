"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge } from "@/components/shared/status-badge";
import { ProgressStepper } from "@/components/shared/progress-stepper";
import { formatDate } from "@/lib/utils";
import type {
  OnboardingDetail as OnboardingDetailType,
  OnboardingReadiness,
} from "@/lib/firestore/onboarding";
import type { DemoAccessView } from "@/lib/firestore/demo-access";
import { OnboardingActions } from "./onboarding-actions";
import { ProvisionPanel } from "./provision-panel";
import { ReadinessPanel } from "./readiness-panel";
import { FollowUpPanel } from "./follow-up-panel";
import { DemoAccessPanel } from "./demo-access-panel";

const ONBOARDING_STEPS = [
  { key: "schoolInfo", label: "School Info" },
  { key: "adminAccount", label: "Admin Account" },
  { key: "readingLevels", label: "Reading Levels" },
  { key: "importData", label: "Import Data" },
  { key: "inviteTeachers", label: "Invite Teachers" },
  { key: "completed", label: "Completed" },
];

interface OnboardingDetailProps {
  onboarding: OnboardingDetailType;
  readiness: OnboardingReadiness | null;
  demoAccessView: DemoAccessView | null;
}

export function OnboardingDetail({
  onboarding,
  readiness,
  demoAccessView,
}: OnboardingDetailProps) {
  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Progress</CardTitle>
        </CardHeader>
        <CardContent>
          <ProgressStepper
            steps={ONBOARDING_STEPS}
            currentStep={onboarding.currentStep}
            completedSteps={onboarding.completedSteps}
          />
        </CardContent>
      </Card>

      {onboarding.status === "demo" && demoAccessView && (
        <DemoAccessPanel
          onboardingId={onboarding.id}
          contactEmail={onboarding.contactEmail}
          view={demoAccessView}
        />
      )}

      <div className="grid gap-6 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Contact Information</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div>
              <p className="text-sm text-muted-foreground">Contact Person</p>
              <p className="font-medium">{onboarding.contactPerson || "—"}</p>
            </div>
            <div>
              <p className="text-sm text-muted-foreground">Email</p>
              <p className="font-medium">{onboarding.contactEmail}</p>
            </div>
            <div>
              <p className="text-sm text-muted-foreground">Phone</p>
              <p className="font-medium">{onboarding.contactPhone || "—"}</p>
            </div>
            <div>
              <p className="text-sm text-muted-foreground">Referral Source</p>
              <p className="font-medium">
                {onboarding.referralSource || "—"}
              </p>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Details</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div>
              <p className="text-sm text-muted-foreground">Status</p>
              <StatusBadge status={onboarding.status} />
            </div>
            <div>
              <p className="text-sm text-muted-foreground">Estimated Students</p>
              <p className="font-medium">{onboarding.estimatedStudentCount}</p>
            </div>
            <div>
              <p className="text-sm text-muted-foreground">Estimated Teachers</p>
              <p className="font-medium">{onboarding.estimatedTeacherCount}</p>
            </div>
            <div>
              <p className="text-sm text-muted-foreground">Created</p>
              <p className="font-medium">{formatDate(onboarding.createdAt)}</p>
            </div>
            {onboarding.schoolId && (
              <div>
                <p className="text-sm text-muted-foreground">Linked School</p>
                <p className="font-mono text-xs">{onboarding.schoolId}</p>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Provisioning: create the school, or show live setup readiness. */}
      {!onboarding.schoolId ? (
        <ProvisionPanel
          onboardingId={onboarding.id}
          defaultAdminEmail={onboarding.contactEmail}
          defaultAdminName={onboarding.contactPerson}
        />
      ) : (
        readiness && (
          <ReadinessPanel
            onboardingId={onboarding.id}
            schoolId={onboarding.schoolId}
            readiness={readiness}
            isActive={onboarding.status === "active"}
          />
        )
      )}

      <FollowUpPanel onboarding={onboarding} />

      <OnboardingActions onboarding={onboarding} />
    </div>
  );
}
