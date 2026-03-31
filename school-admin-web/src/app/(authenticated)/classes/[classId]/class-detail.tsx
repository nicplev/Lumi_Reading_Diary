'use client';

import { useState, useEffect } from 'react';
import { useBreadcrumbs } from '@/components/layout/breadcrumb-context';
import { PageHeader } from '@/components/lumi/page-header';
import { Tabs } from '@/components/lumi/tabs';
import { Badge } from '@/components/lumi/badge';
import { Icon } from '@/components/lumi/icon';
import { StudentRoster } from './student-roster';
import { ReadingGroupsTab } from './reading-groups-tab';
import { AllocationsTab } from './allocations-tab';
import type { SchoolClass, ReadingLevelOption } from '@/lib/types';

type SerializedClass = Omit<SchoolClass, 'createdAt'> & { createdAt: string };

interface ClassDetailProps {
  schoolClass: SerializedClass;
  levelOptions: ReadingLevelOption[];
}

export function ClassDetail({ schoolClass, levelOptions }: ClassDetailProps) {
  const [activeTab, setActiveTab] = useState('roster');
  const { setOverride } = useBreadcrumbs();

  useEffect(() => {
    setOverride(schoolClass.id, schoolClass.name || schoolClass.yearLevel || 'Unnamed Class');
  }, [schoolClass.id, schoolClass.name, schoolClass.yearLevel, setOverride]);

  const tabs = [
    { id: 'roster', label: 'Roster', count: schoolClass.studentIds.length, icon: <Icon name="group" size={18} /> },
    { id: 'groups', label: 'Reading Groups', icon: <Icon name="library_books" size={18} /> },
    { id: 'allocations', label: 'Allocations', icon: <Icon name="inventory_2" size={18} /> },
  ];

  return (
    <div>
      <PageHeader
        title={schoolClass.name}
        description={[schoolClass.yearLevel, `${schoolClass.studentIds.length} students`].filter(Boolean).join(' · ')}
      />

      <Tabs tabs={tabs} activeTab={activeTab} onChange={setActiveTab} />

      {activeTab === 'roster' && (
        <StudentRoster classId={schoolClass.id} levelOptions={levelOptions} />
      )}
      {activeTab === 'groups' && (
        <ReadingGroupsTab classId={schoolClass.id} levelOptions={levelOptions} />
      )}
      {activeTab === 'allocations' && <AllocationsTab classId={schoolClass.id} levelOptions={levelOptions} />}
    </div>
  );
}
