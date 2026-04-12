'use client';

import { useState, useMemo, useCallback, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import {
  DndContext,
  PointerSensor,
  KeyboardSensor,
  useSensor,
  useSensors,
  closestCenter,
  type DragStartEvent,
  type DragEndEvent,
  type DragOverEvent,
} from '@dnd-kit/core';
import { SearchInput } from '@/components/lumi/search-input';
import { useToast } from '@/components/lumi/toast';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { useStudents } from '@/lib/hooks/use-students';
import { useClasses, useMoveStudent } from '@/lib/hooks/use-classes';
import { useSchool } from '@/lib/hooks/use-school';
import { KanbanColumn } from './kanban-column';
import { StudentCardDraggable } from './student-card-draggable';
import { KanbanDragOverlay } from './kanban-drag-overlay';
import { AddStudentToClassModal } from './add-student-to-class-modal';
import { UnsavedChangesBar } from './unsaved-changes-bar';
import { ClassFormModal } from './class-form-modal';
import { useUpdateClass } from '@/lib/hooks/use-classes';

interface StudentData {
  id: string;
  firstName: string;
  lastName: string;
  classId: string;
  currentReadingLevel?: string;
  effectiveClassId: string | null;
}

type PendingChange = {
  studentId: string;
  fromClassId: string | null;
  toClassId: string | null;
  studentName: string;
};

interface KanbanBoardProps {
  teachers?: { id: string; fullName: string }[];
}

export function KanbanBoard({ teachers = [] }: KanbanBoardProps) {
  const { toast } = useToast();
  const router = useRouter();
  const { data: students = [] } = useStudents();
  const { data: classes = [] } = useClasses();
  const { data: school } = useSchool();
  const moveStudent = useMoveStudent();
  const updateClass = useUpdateClass();

  const [editingClass, setEditingClass] = useState<typeof classes[number] | null>(null);

  const showReadingLevels = !!school && school.levelSchema !== 'none';

  const [search, setSearch] = useState('');
  const [activeStudentId, setActiveStudentId] = useState<string | null>(null);
  const [overColumnId, setOverColumnId] = useState<string | null>(null);
  const [addModalTarget, setAddModalTarget] = useState<string | null | false>(false);
  const [pendingChanges, setPendingChanges] = useState<Map<string, PendingChange>>(new Map());
  const [pendingNavHref, setPendingNavHref] = useState<string | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(KeyboardSensor),
  );

  const activeClassIds = useMemo(() => new Set(classes.map((c) => c.id)), [classes]);

  const sortedClasses = useMemo(
    () => [...classes].sort((a, b) => a.name.localeCompare(b.name)),
    [classes],
  );

  const classMap = useMemo(
    () => new Map(classes.map((c) => [c.id, c.name])),
    [classes],
  );

  const pendingStudentIds = useMemo(() => new Set(pendingChanges.keys()), [pendingChanges]);
  const hasPendingChanges = pendingStudentIds.size > 0;

  const { grouped, unassigned } = useMemo(() => {
    const grouped = new Map<string, StudentData[]>();
    const unassigned: StudentData[] = [];

    for (const cls of classes) {
      grouped.set(cls.id, []);
    }

    for (const s of students) {
      const pending = pendingChanges.get(s.id);
      const effectiveClassId = pending !== undefined ? pending.toClassId : (s.classId || null);

      const data: StudentData = {
        id: s.id,
        firstName: s.firstName,
        lastName: s.lastName,
        classId: s.classId,
        currentReadingLevel: s.currentReadingLevel,
        effectiveClassId,
      };

      if (!effectiveClassId || !activeClassIds.has(effectiveClassId)) {
        unassigned.push(data);
      } else {
        const list = grouped.get(effectiveClassId);
        if (list) {
          list.push(data);
        } else {
          grouped.set(effectiveClassId, [data]);
        }
      }
    }

    return { grouped, unassigned };
  }, [students, classes, activeClassIds, pendingChanges]);

  const activeStudent = useMemo(() => {
    if (!activeStudentId) return null;
    return students.find((s) => s.id === activeStudentId) ?? null;
  }, [activeStudentId, students]);

  const matchesSearch = useCallback(
    (student: StudentData) => {
      if (!search) return true;
      const term = search.toLowerCase();
      return (
        student.firstName.toLowerCase().includes(term) ||
        student.lastName.toLowerCase().includes(term)
      );
    },
    [search],
  );

  const queueChange = useCallback(
    (studentId: string, fromClassId: string | null, toClassId: string | null, studentName: string) => {
      setPendingChanges((prev) => {
        const next = new Map(prev);
        const serverStudent = students.find((s) => s.id === studentId);
        const serverClassId = serverStudent?.classId || null;
        // Preserve original fromClassId if student was already pending
        const originalFrom = prev.get(studentId)?.fromClassId ?? fromClassId;

        if (toClassId === serverClassId) {
          // Moving back to server state — cancel the pending change
          next.delete(studentId);
        } else {
          next.set(studentId, { studentId, fromClassId: originalFrom, toClassId, studentName });
        }
        return next;
      });
    },
    [students],
  );

  const handleSave = useCallback(async () => {
    const changes = Array.from(pendingChanges.values());
    try {
      await Promise.all(
        changes.map((c) =>
          moveStudent.mutateAsync({
            studentId: c.studentId,
            fromClassId: c.fromClassId,
            toClassId: c.toClassId,
          }),
        ),
      );
      setPendingChanges(new Map());
      toast(`${changes.length} change${changes.length !== 1 ? 's' : ''} saved`, 'success');
    } catch {
      toast('Some changes failed to save. Please try again.', 'error');
    }
  }, [pendingChanges, moveStudent, toast]);

  const handleDiscard = useCallback(() => {
    setPendingChanges(new Map());
  }, []);

  // Browser refresh / tab close guard
  useEffect(() => {
    if (!hasPendingChanges) return;
    const handler = (e: BeforeUnloadEvent) => {
      e.preventDefault();
      e.returnValue = '';
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [hasPendingChanges]);

  // Next.js App Router link click guard
  useEffect(() => {
    if (!hasPendingChanges) return;
    const handler = (e: MouseEvent) => {
      const anchor = (e.target as Element).closest('a[href]');
      if (!anchor) return;
      const href = anchor.getAttribute('href');
      if (!href || href.startsWith('#')) return;
      e.preventDefault();
      setPendingNavHref(href);
    };
    document.addEventListener('click', handler, true);
    return () => document.removeEventListener('click', handler, true);
  }, [hasPendingChanges]);

  const handleNavConfirm = useCallback(() => {
    if (!pendingNavHref) return;
    const href = pendingNavHref;
    setPendingChanges(new Map());
    setPendingNavHref(null);
    router.push(href);
  }, [pendingNavHref, router]);

  const handleNavCancel = useCallback(() => {
    setPendingNavHref(null);
  }, []);

  const handleDragStart = useCallback((event: DragStartEvent) => {
    setActiveStudentId(event.active.id as string);
  }, []);

  const handleDragOver = useCallback((event: DragOverEvent) => {
    setOverColumnId((event.over?.id as string) ?? null);
  }, []);

  const handleDragEnd = useCallback(
    (event: DragEndEvent) => {
      const { active, over } = event;

      setActiveStudentId(null);
      setOverColumnId(null);

      if (!over) return;

      const sourceClassId = (active.data.current as { classId: string | null })?.classId ?? null;
      const destinationId = over.id as string;
      const destinationClassId = destinationId === 'unassigned' ? null : destinationId;

      if (sourceClassId === destinationClassId) return;

      const student = students.find((s) => s.id === active.id);
      if (!student) return;

      queueChange(
        active.id as string,
        sourceClassId,
        destinationClassId,
        `${student.firstName} ${student.lastName}`,
      );
    },
    [students, queueChange],
  );

  const handleDragCancel = useCallback(() => {
    setActiveStudentId(null);
    setOverColumnId(null);
  }, []);

  const handleRemoveFromClass = useCallback(
    (studentId: string, fromClassId: string) => {
      const student = students.find((s) => s.id === studentId);
      if (!student) return;
      queueChange(studentId, fromClassId, null, `${student.firstName} ${student.lastName}`);
    },
    [students, queueChange],
  );

  const handleModalMove = useCallback(
    (studentId: string) => {
      if (addModalTarget === false) return;
      const student = students.find((s) => s.id === studentId);
      if (!student) return;

      const effectiveFrom = pendingChanges.get(studentId)?.toClassId ?? (student.classId || null);
      queueChange(studentId, effectiveFrom, addModalTarget, `${student.firstName} ${student.lastName}`);
      setAddModalTarget(false);
    },
    [addModalTarget, students, pendingChanges, queueChange],
  );

  const modalTargetName = useMemo(() => {
    if (addModalTarget === false) return '';
    if (addModalTarget === null) return 'Unassigned';
    return classMap.get(addModalTarget) ?? '';
  }, [addModalTarget, classMap]);

  const modalStudents = useMemo(() => {
    return students.map((s) => {
      const pending = pendingChanges.get(s.id);
      return {
        id: s.id,
        firstName: s.firstName,
        lastName: s.lastName,
        classId: pending ? (pending.toClassId ?? '') : s.classId,
        currentReadingLevel: s.currentReadingLevel,
      };
    });
  }, [students, pendingChanges]);

  return (
    <div>
      <div className="mb-4 max-w-sm">
        <SearchInput value={search} onChange={setSearch} placeholder="Search students..." />
      </div>

      <DndContext
        sensors={sensors}
        collisionDetection={closestCenter}
        onDragStart={handleDragStart}
        onDragOver={handleDragOver}
        onDragEnd={handleDragEnd}
        onDragCancel={handleDragCancel}
      >
        <div
          className={`flex gap-4 overflow-x-auto ${hasPendingChanges ? 'pb-20' : 'pb-4'}`}
          style={{ height: 'calc(100vh - 240px)' }}
        >
          {/* Unassigned column */}
          <KanbanColumn
            classId={null}
            className="Unassigned"
            studentCount={unassigned.length}
            isOver={overColumnId === 'unassigned'}
            onAddStudent={() => setAddModalTarget(null)}
          >
            {unassigned.map((student) => (
              <StudentCardDraggable
                key={student.id}
                student={student}
                classId={student.effectiveClassId}
                isPending={pendingStudentIds.has(student.id)}
                dimmed={!!search && !matchesSearch(student)}
                showReadingLevel={showReadingLevels}
              />
            ))}
          </KanbanColumn>

          {/* Class columns */}
          {sortedClasses.map((cls) => {
            const studentsInClass = grouped.get(cls.id) ?? [];
            return (
              <KanbanColumn
                key={cls.id}
                classId={cls.id}
                className={cls.name}
                yearLevel={cls.yearLevel}
                studentCount={studentsInClass.length}
                isOver={overColumnId === cls.id}
                onAddStudent={() => setAddModalTarget(cls.id)}
                onEditClass={() => setEditingClass(cls)}
              >
                {studentsInClass.map((student) => (
                  <StudentCardDraggable
                    key={student.id}
                    student={student}
                    classId={student.effectiveClassId}
                    isPending={pendingStudentIds.has(student.id)}
                    dimmed={!!search && !matchesSearch(student)}
                    showReadingLevel={showReadingLevels}
                    onRemove={() => handleRemoveFromClass(student.id, cls.id)}
                  />
                ))}
              </KanbanColumn>
            );
          })}
        </div>

        <KanbanDragOverlay activeStudent={activeStudent} />
      </DndContext>

      <UnsavedChangesBar
        changeCount={pendingChanges.size}
        onSave={handleSave}
        onDiscard={handleDiscard}
        isSaving={moveStudent.isPending}
      />

      <ClassFormModal
        open={!!editingClass}
        onClose={() => setEditingClass(null)}
        onSubmit={async (data) => {
          if (!editingClass) return;
          try {
            await updateClass.mutateAsync({ classId: editingClass.id, ...data });
            setEditingClass(null);
            toast('Class updated', 'success');
          } catch {
            toast('Failed to update class', 'error');
          }
        }}
        loading={updateClass.isPending}
        initialData={editingClass ?? undefined}
        teachers={teachers}
      />

      <Modal
        open={pendingNavHref !== null}
        onClose={handleNavCancel}
        title="Unsaved changes"
        description="You have unsaved class assignments. If you leave now your changes will be lost."
        size="sm"
        footer={
          <>
            <Button variant="outline" size="sm" onClick={handleNavCancel}>Stay</Button>
            <Button variant="danger" size="sm" onClick={handleNavConfirm}>Leave anyway</Button>
          </>
        }
      >
        <></>
      </Modal>

      <AddStudentToClassModal
        open={addModalTarget !== false}
        onClose={() => setAddModalTarget(false)}
        targetClassId={addModalTarget === false ? null : addModalTarget}
        targetClassName={modalTargetName}
        students={modalStudents}
        classMap={classMap}
        onMove={handleModalMove}
        loading={false}
      />
    </div>
  );
}
