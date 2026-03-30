'use client';

import { useState } from 'react';
import { Avatar } from '@/components/lumi/avatar';
import { Badge } from '@/components/lumi/badge';
import { Button } from '@/components/lumi/button';
import { Card } from '@/components/lumi/card';
import { StatCard } from '@/components/lumi/stat-card';
import { ReadingLevelPill } from '@/components/lumi/reading-level-pill';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { useToast } from '@/components/lumi/toast';
import { ReadingLevelPicker } from '@/components/features/reading-level-picker';
import { useStudent, useUpdateStudentLevel, useReadingLevelHistory } from '@/lib/hooks/use-students';
import { useStudentAllocations } from '@/lib/hooks/use-allocations';
import { BookCard } from '@/components/lumi/book-card';
import type { ReadingLevelOption } from '@/lib/types';

interface StudentDetailProps {
  studentId: string;
  classId: string;
  levelOptions: ReadingLevelOption[];
  className?: string;
}

export function StudentDetail({ studentId, classId, levelOptions, className }: StudentDetailProps) {
  const { toast } = useToast();
  const { data: student, isLoading } = useStudent(studentId);
  const { data: levelHistory } = useReadingLevelHistory(studentId);
  const updateLevel = useUpdateStudentLevel(studentId);

  const { data: studentAllocations } = useStudentAllocations(studentId, classId);
  const [showLevelPicker, setShowLevelPicker] = useState(false);
  const [showHistory, setShowHistory] = useState(false);
  const [expandedAllocation, setExpandedAllocation] = useState<string | null>(null);

  if (isLoading || !student) {
    return (
      <div className="animate-pulse space-y-6">
        <div className="flex items-center gap-4">
          <div className="w-14 h-14 bg-divider/60 rounded-full" />
          <div className="space-y-2">
            <div className="h-6 bg-divider/60 rounded w-40" />
            <div className="h-4 bg-divider/60 rounded w-24" />
          </div>
        </div>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="bg-surface rounded-[var(--radius-lg)] shadow-card p-5">
              <div className="h-4 bg-divider/60 rounded w-24 mb-3" />
              <div className="h-8 bg-divider/60 rounded w-16" />
            </div>
          ))}
        </div>
      </div>
    );
  }

  const handleLevelChange = async (level: string, reason?: string) => {
    try {
      await updateLevel.mutateAsync({
        toLevel: level,
        reason,
        fromLevel: student.currentReadingLevel,
      });
      setShowLevelPicker(false);
      toast('Reading level updated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to update level', 'error');
    }
  };

  const fullName = `${student.firstName} ${student.lastName}`;

  return (
    <div>
      {/* Header */}
      <div className="flex items-start gap-4 mb-6">
        <Avatar name={fullName} size="lg" />
        <div className="flex-1">
          <h1 className="text-[28px] font-bold text-charcoal">{fullName}</h1>
          <div className="flex items-center gap-3 mt-1">
            {student.studentId && <span className="text-sm text-text-secondary">ID: {student.studentId}</span>}
            {className && <Badge>{className}</Badge>}
            <ReadingLevelPill
              level={student.currentReadingLevel}
              onClick={() => setShowLevelPicker(true)}
            />
          </div>
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard
          title="Current Streak"
          value={student.stats?.currentStreak ?? 0}
          icon={<Icon name="local_fire_department" />}
          color="orange"
        />
        <StatCard
          title="Total Nights Read"
          value={student.stats?.totalReadingDays ?? 0}
          icon={<Icon name="auto_stories" />}
          color="pink"
        />
        <StatCard
          title="Books Read"
          value={student.stats?.totalBooksRead ?? 0}
          icon={<Icon name="library_books" />}
          color="green"
        />
        <StatCard
          title="Avg Min/Day"
          value={student.stats?.averageMinutesPerDay ?? 0}
          icon={<Icon name="timer" />}
          color="blue"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Reading Level Card */}
        <Card>
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-bold text-charcoal">Reading Level</h2>
            <Button variant="outline" size="sm" onClick={() => setShowLevelPicker(true)}>
              Change Level
            </Button>
          </div>
          <div className="flex items-center gap-3 mb-4">
            <ReadingLevelPill level={student.currentReadingLevel} />
            {student.readingLevelUpdatedAt && (
              <span className="text-xs text-text-secondary">
                Updated {new Date(student.readingLevelUpdatedAt).toLocaleDateString()}
              </span>
            )}
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setShowHistory(!showHistory)}
          >
            {showHistory ? 'Hide History' : 'View History'}
          </Button>

          {showHistory && (
            <div className="mt-4 space-y-3">
              {!levelHistory || levelHistory.length === 0 ? (
                <p className="text-sm text-text-secondary">No level changes recorded.</p>
              ) : (
                levelHistory.map((event) => (
                  <div
                    key={event.id}
                    className="flex items-start gap-3 p-3 bg-background rounded-[var(--radius-md)]"
                  >
                    <div className="flex-shrink-0 mt-1">
                      <div className="w-2 h-2 rounded-full bg-rose-pink" />
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        {event.fromLevel && (
                          <>
                            <ReadingLevelPill level={event.fromLevel} size="sm" />
                            <span className="text-xs text-text-secondary">→</span>
                          </>
                        )}
                        <ReadingLevelPill level={event.toLevel} size="sm" />
                      </div>
                      {event.reason && (
                        <p className="text-xs text-text-secondary">{event.reason}</p>
                      )}
                      <p className="text-xs text-text-secondary/60 mt-1">
                        {new Date(event.createdAt).toLocaleDateString()} by {event.changedByName}
                      </p>
                    </div>
                  </div>
                ))
              )}
            </div>
          )}
        </Card>

        {/* Parent Info */}
        <Card>
          <h2 className="text-lg font-bold text-charcoal mb-4">Parent Information</h2>
          {student.parentIds.length === 0 ? (
            <div className="flex items-center gap-2">
              <Badge variant="default">No parent linked</Badge>
            </div>
          ) : (
            <div>
              <Badge variant="success">{student.parentIds.length} parent{student.parentIds.length !== 1 ? 's' : ''} linked</Badge>
            </div>
          )}
        </Card>
      </div>

      {/* Assigned Books */}
      <div className="mt-6">
        <Card>
          <h2 className="text-lg font-bold text-charcoal mb-4">Assigned Books</h2>
          {!studentAllocations || studentAllocations.length === 0 ? (
            <EmptyState
              icon={<Icon name="auto_stories" size={40} />}
              title="No books assigned"
              description="This student has no active book allocations."
            />
          ) : (
            <div className="space-y-4">
              {studentAllocations.map((allocation) => {
                const override = allocation.studentOverrides?.[studentId];
                const baseItems = (allocation.assignmentItems ?? []).filter((i) => !i.isDeleted);
                const afterRemoval = override
                  ? baseItems.filter((i) => !override.removedItemIds.includes(i.id))
                  : baseItems;
                const addedItems = override
                  ? override.addedItems.filter((i) => !i.isDeleted)
                  : [];
                const effectiveItems = [...afterRemoval, ...addedItems];
                const isExpanded = expandedAllocation === allocation.id;

                const typeLabel = allocation.type === 'byTitle' ? 'By Title' : allocation.type === 'byLevel' ? 'By Level' : 'Free Choice';
                const cadenceLabel = allocation.cadence === 'daily' ? 'Daily' : allocation.cadence === 'weekly' ? 'Weekly' : allocation.cadence === 'fortnightly' ? 'Fortnightly' : allocation.cadence;

                return (
                  <div key={allocation.id} className="border border-divider rounded-[var(--radius-md)]">
                    <button
                      onClick={() => setExpandedAllocation(isExpanded ? null : allocation.id)}
                      className="w-full flex items-center justify-between p-3 text-left hover:bg-background/50 transition-colors rounded-[var(--radius-md)]"
                    >
                      <div className="flex items-center gap-2">
                        <Badge variant="info">{typeLabel}</Badge>
                        <span className="text-sm text-charcoal font-semibold">{cadenceLabel}</span>
                        <span className="text-xs text-text-secondary">{allocation.targetMinutes}min</span>
                        <Badge variant="default">{effectiveItems.length} books</Badge>
                      </div>
                      <svg
                        className={`w-4 h-4 text-text-secondary transition-transform ${isExpanded ? 'rotate-180' : ''}`}
                        viewBox="0 0 16 16"
                        fill="none"
                      >
                        <path d="M4 6l4 4 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                      </svg>
                    </button>
                    {isExpanded && (
                      <div className="px-3 pb-3 space-y-2">
                        <p className="text-xs text-text-secondary">
                          {new Date(allocation.startDate).toLocaleDateString()} - {new Date(allocation.endDate).toLocaleDateString()}
                        </p>
                        {effectiveItems.length === 0 ? (
                          <p className="text-sm text-text-secondary">No specific books assigned.</p>
                        ) : (
                          effectiveItems.map((item) => (
                            <BookCard
                              key={item.id}
                              compact
                              book={{ title: item.title, isbn: item.isbn }}
                            />
                          ))
                        )}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </Card>
      </div>

      <ReadingLevelPicker
        open={showLevelPicker}
        onClose={() => setShowLevelPicker(false)}
        currentLevel={student.currentReadingLevel}
        levelOptions={levelOptions}
        onSelect={handleLevelChange}
        loading={updateLevel.isPending}
      />
    </div>
  );
}
