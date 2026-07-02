'use client';

import { useState, useEffect } from 'react';
import { PageHeader } from '@/components/lumi/page-header';
import { Tabs } from '@/components/lumi/tabs';
import { ParentConnectionsTab } from './parent-connections-tab';
import { LinkCodesTab } from './link-codes-tab';
import { ParentOnboardingTab } from './parent-onboarding-tab';

const tabs = [
  { id: 'connections', label: 'Parent Connections' },
  { id: 'codes', label: 'Link Codes' },
  { id: 'onboarding', label: 'Parent Onboarding' },
];

export function ParentLinksPage() {
  const [activeTab, setActiveTab] = useState('connections');
  // Dashboard's "parent invitations awaiting acceptance" deep-links to ?tab=codes.
  useEffect(() => {
    const tab = new URLSearchParams(window.location.search).get('tab');
    if (tab && tabs.some((t) => t.id === tab)) setActiveTab(tab);
  }, []);

  return (
    <div>
      <PageHeader
        eyebrow="Parents/Guardians"
        title="Parents/Guardians"
        description="Manage parent & guardian connections, link codes, and onboarding"
      />

      <Tabs tabs={tabs} activeTab={activeTab} onChange={setActiveTab} />

      {activeTab === 'connections' ? (
        <ParentConnectionsTab />
      ) : activeTab === 'codes' ? (
        <LinkCodesTab />
      ) : (
        <ParentOnboardingTab />
      )}
    </div>
  );
}
