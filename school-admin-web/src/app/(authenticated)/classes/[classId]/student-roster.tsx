'use client';

import { useState, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import { Avatar } from '@/components/lumi/avatar';
import { Button } from '@/components/lumi/button';
import { SearchInput } from '@/components/lumi/search-input';
import { ReadingLevelPill } from '@/components/lumi/reading-level-pill';
import { Select } from '@/components/lumi/select';
import { useToast } from '@/components/lumi/toast';
import { ReadingLevelPicker } from '@/components/features/reading-level-picker';
import { useStudents, useUpdateStudentLevel, useBulkUpdateLevel } from '@/lib/hooks/use-students';
import type { ReadingLevelOption } from '@/lib/types';

interface StudentRosterProps {
  classId: string;
  levelOptions: ReadingLevelOption[];
  /** When false (school has reading levels off), the level column and all
   *  level-setting UI are hidden — the roster still lists students. */
  levelsEnabled?: boolean;
}

type SortKey = 'name' | 'level' | 'streak';

export function StudentRoster({ classId, levelOptions, levelsEnabled = true }: StudentRosterProps) {
  const router = useRouter();
  const showLevels = levelsEnabled;
  const { toast } = useToast();
  const { data: students, isLoading } = useStudents({ classId });
  const bulkUpdate = useBulkUpdateLevel();

  const [search, setSearch] = useState('');
  const [sortBy, setSortBy] = useState<SortKey>('name');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [levelPickerStudentId, setLevelPickerStudentId] = useState<string | null>(null);
  const [showBulkPicker, setShowBulkPicker] = useState(false);

  const filtered = useMemo(() => {
    if (!students) return [];
    let list = [...students];

    if (search) {
      const q = search.toLowerCase();
      list = list.filter(
        (s) =>
          `${s.firstName} ${s.lastName}`.toLowerCase().includes(q) ||
          s.studentId?.toLowerCase().includes(q)
      );
    }

    list.sort((a, b) => {
      switch (sortBy) {
        case 'name':
          return `${a.firstName} ${a.lastName}`.localeCompare(`${b.firstName} ${b.lastName}`);
        case 'level':
          return (a.currentReadingLevelIndex ?? -1) - (b.currentReadingLevelIndex ?? -1);
        case 'streak':
          return (b.stats?.currentStreak ?? 0) - (a.stats?.currentStreak ?? 0);
        default:
          return 0;
      }
    });

    return list;
  }, [students, search, sortBy]);

  const toggleSelect = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleAll = () => {
    if (selectedIds.size === filtered.length) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(filtered.map((s) => s.id)));
    }
  };

  const handleBulkLevel = async (level: string, reason?: string) => {
    try {
      await bulkUpdate.mutateAsync({
        studentIds: Array.from(selectedIds),
        toLevel: level,
        reason,
      });
      setSelectedIds(new Set());
      setShowBulkPicker(false);
      toast(`Updated level for ${selectedIds.size} students`, 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to update levels', 'error');
    }
  };

  const pickerStudent = students?.find((s) => s.id === levelPickerStudentId);

  return (
    <div>
      <div className="flex flex-col sm:flex-row gap-3 mb-4">
        <div className="flex-1">
          <SearchInput value={search} onChange={setSearch} placeholder="Search students..." />
        </div>
        <Select
          options={[
            { value: 'name', label: 'Name A-Z' },
            ...(showLevels ? [{ value: 'level', label: 'Reading Level' }] : []),
            { value: 'streak', label: 'Streak' },
          ]}
          value={sortBy}
          onChange={(v) => setSortBy(v as SortKey)}
        />
      </div>

      {showLevels && selectedIds.size > 0 && (
        <div className="flex items-center gap-3 mb-4 p-3 bg-section/5 rounded-[var(--radius-md)] border border-section/20">
          <span className="text-sm font-semibold text-ink">{selectedIds.size} selected</span>
          <Button size="sm" onClick={() => setShowBulkPicker(true)}>Set Level</Button>
          <Button variant="ghost" size="sm" onClick={() => setSelectedIds(new Set())}>Clear</Button>
        </div>
      )}

      {isLoading ? (
        <div className="space-y-2">
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="bg-paper rounded-[var(--radius-md)] shadow-card p-4 animate-pulse">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-rule/60 rounded-full" />
                <div className="flex-1 space-y-2">
                  <div className="h-4 bg-rule/60 rounded w-32" />
                  <div className="h-3 bg-rule/60 rounded w-20" />
                </div>
              </div>
            </div>
          ))}
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-8 text-muted text-sm">
          {search ? 'No students match your search.' : 'No students in this class.'}
        </div>
      ) : (
        <div className="bg-paper rounded-[var(--radius-lg)] shadow-card overflow-hidden">
          <table className="w-full">
            <thead>
              <tr className="border-b border-rule">
                {showLevels && (
                  <th className="px-4 py-3 w-10">
                    <input
                      type="checkbox"
                      checked={selectedIds.size === filtered.length && filtered.length > 0}
                      onChange={toggleAll}
                      className="w-4 h-4 rounded border-rule text-section focus:ring-section/30"
                    />
                  </th>
                )}
                <th className="px-4 py-3 text-left text-xs font-semibold text-muted uppercase tracking-wider">Student</th>
                <th className="px-4 py-3 text-left text-xs font-semibold text-muted uppercase tracking-wider">ID</th>
                {showLevels && (
                  <th className="px-4 py-3 text-left text-xs font-semibold text-muted uppercase tracking-wider">Level</th>
                )}
                <th className="px-4 py-3 text-left text-xs font-semibold text-muted uppercase tracking-wider">Streak</th>
                <th className="px-4 py-3 text-left text-xs font-semibold text-muted uppercase tracking-wider">Last Read</th>
                <th className="px-4 py-3 w-20"></th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((student) => (
                <tr
                  key={student.id}
                  className="border-b border-rule/50 last:border-b-0 hover:bg-cream/50 transition-colors cursor-pointer"
                  onClick={() => router.push(`/students/${student.id}`)}
                >
                  {showLevels && (
                    <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                      <input
                        type="checkbox"
                        checked={selectedIds.has(student.id)}
                        onChange={() => toggleSelect(student.id)}
                        className="w-4 h-4 rounded border-rule text-section focus:ring-section/30"
                      />
                    </td>
                  )}
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-3">
                      <Avatar
                        name={`${student.firstName} ${student.lastName}`}
                        characterId={student.characterId}
                        size="sm"
                      />
                      <span className="font-semibold text-sm text-ink">
                        {student.firstName} {student.lastName}
                      </span>
                    </div>
                  </td>
                  <td className="px-4 py-3 text-sm text-muted">{student.studentId || '-'}</td>
                  {showLevels && (
                    <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                      <ReadingLevelPill
                        level={student.currentReadingLevel}
                        onClick={() => setLevelPickerStudentId(student.id)}
                        size="sm"
                      />
                    </td>
                  )}
                  <td className="px-4 py-3 text-sm text-ink">
                    {student.stats?.currentStreak ? `${student.stats.currentStreak} days` : '-'}
                  </td>
                  <td className="px-4 py-3 text-sm text-muted">
                    {student.stats?.lastReadingDate
                      ? new Date(student.stats.lastReadingDate).toLocaleDateString()
                      : '-'}
                  </td>
                  <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => router.push(`/students/${student.id}`)}
                    >
                      View
                    </Button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showLevels && levelPickerStudentId && (
        <SingleLevelPicker
          studentId={levelPickerStudentId}
          currentLevel={pickerStudent?.currentReadingLevel}
          levelOptions={levelOptions}
          onClose={() => setLevelPickerStudentId(null)}
        />
      )}

      {showLevels && (
        <ReadingLevelPicker
          open={showBulkPicker}
          onClose={() => setShowBulkPicker(false)}
          levelOptions={levelOptions}
          onSelect={handleBulkLevel}
          loading={bulkUpdate.isPending}
        />
      )}
    </div>
  );
}

function SingleLevelPicker({
  studentId,
  currentLevel,
  levelOptions,
  onClose,
}: {
  studentId: string;
  currentLevel?: string;
  levelOptions: ReadingLevelOption[];
  onClose: () => void;
}) {
  const { toast } = useToast();
  const updateLevel = useUpdateStudentLevel(studentId);

  const handleSelect = async (level: string, reason?: string) => {
    try {
      await updateLevel.mutateAsync({ toLevel: level, reason, fromLevel: currentLevel });
      onClose();
      toast('Reading level updated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to update level', 'error');
    }
  };

  return (
    <ReadingLevelPicker
      open
      onClose={onClose}
      currentLevel={currentLevel}
      levelOptions={levelOptions}
      onSelect={handleSelect}
      loading={updateLevel.isPending}
    />
  );
}
