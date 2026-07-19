'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useBreadcrumbs } from '@/components/layout/breadcrumb-context';
import { PageHeader } from '@/components/lumi/page-header';
import { Select } from '@/components/lumi/select';
import { Tabs } from '@/components/lumi/tabs';
import { Icon } from '@/components/lumi/icon';
import { StudentRoster } from './student-roster';
import { ReadingGroupsTab } from './reading-groups-tab';
import { AllocationsTab } from './allocations-tab';
import { ClassReportTab } from './class-report-tab';
import { ComprehensionEvalTab } from './comprehension-eval-tab';
import { ComprehensionQuestionCard } from './comprehension-question-card';
import type { SchoolClass, ReadingLevelOption } from '@/lib/types';

type SerializedClass = Omit<SchoolClass, 'createdAt'> & { createdAt: string };

interface ClassDetailProps {
  schoolClass: SerializedClass;
  levelOptions: ReadingLevelOption[];
  /** The teacher's classes for the switcher; >1 renders a dropdown. Empty for admins. */
  classOptions?: { id: string; name: string }[];
  /** False when the school has reading levels turned off — hides level-setting UI. */
  levelsEnabled?: boolean;
}

export function ClassDetail({ schoolClass, levelOptions, classOptions = [], levelsEnabled = true }: ClassDetailProps) {
  const router = useRouter();
  const [activeTab, setActiveTab] = useState('roster');
  const { setOverride } = useBreadcrumbs();

  useEffect(() => {
    setOverride(schoolClass.id, schoolClass.name || schoolClass.yearLevel || 'Unnamed Class');
  }, [schoolClass.id, schoolClass.name, schoolClass.yearLevel, setOverride]);

  const tabs = [
    { id: 'roster', label: 'Class', count: schoolClass.studentIds.length, icon: <Icon name="group" size={18} /> },
    { id: 'groups', label: 'Reading Groups', icon: <Icon name="library_books" size={18} /> },
    { id: 'allocations', label: 'Allocations', icon: <Icon name="inventory_2" size={18} /> },
    { id: 'report', label: 'Report', icon: <Icon name="assessment" size={18} /> },
    { id: 'comprehension', label: 'Comprehension', icon: <Icon name="graphic_eq" size={18} /> },
  ];

  return (
    <div>
      <PageHeader
        eyebrow="Class"
        title={schoolClass.name}
        description={[schoolClass.yearLevel, `${schoolClass.studentIds.length} students`].filter(Boolean).join(' · ')}
        action={
          classOptions.length > 1 ? (
            <div className="flex items-center gap-2">
              <span className="text-sm text-muted whitespace-nowrap">Class</span>
              <Select
                options={classOptions.map((c) => ({ value: c.id, label: c.name }))}
                value={schoolClass.id}
                onChange={(id) => router.push(`/classes/${id}`)}
              />
            </div>
          ) : undefined
        }
      />

      <Tabs tabs={tabs} activeTab={activeTab} onChange={setActiveTab} />

      {activeTab === 'roster' && (
        <>
          <ComprehensionQuestionCard classId={schoolClass.id} />
          <StudentRoster classId={schoolClass.id} levelOptions={levelOptions} levelsEnabled={levelsEnabled} />
        </>
      )}
      {activeTab === 'groups' && (
        <ReadingGroupsTab classId={schoolClass.id} levelOptions={levelOptions} />
      )}
      {activeTab === 'allocations' && <AllocationsTab classId={schoolClass.id} levelOptions={levelOptions} />}
      {activeTab === 'report' && (
        <ClassReportTab classId={schoolClass.id} className={schoolClass.name} yearLevel={schoolClass.yearLevel} defaultMinutesTarget={schoolClass.defaultMinutesTarget} levelsEnabled={levelsEnabled} />
      )}
      {activeTab === 'comprehension' && (
        <ComprehensionEvalTab classId={schoolClass.id} className={schoolClass.name} />
      )}
    </div>
  );
}
