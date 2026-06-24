'use client';

import { useEffect, useMemo, useState } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Input } from '@/components/lumi/input';
import { Select } from '@/components/lumi/select';
import { useToast } from '@/components/lumi/toast';
import { useAuth } from '@/lib/auth/auth-context';
import { useClasses } from '@/lib/hooks/use-classes';
import { useStudents } from '@/lib/hooks/use-students';
import { useCreateCampaign, type CreateCampaignInput } from '@/lib/hooks/use-notifications';
import type { NotificationAudienceType } from '@/lib/types';

const TITLE_MAX = 120;
const BODY_MAX = 1000;

const MESSAGE_TYPE_OPTIONS = [
  { value: 'general', label: 'General' },
  { value: 'announcement', label: 'Announcement' },
  { value: 'reading_reminder', label: 'Reading reminder' },
];

interface SelectedStudent {
  id: string;
  name: string;
}

interface CreateCampaignModalProps {
  open: boolean;
  onClose: () => void;
  onSent: (scheduled: boolean) => void;
}

export function CreateCampaignModal({ open, onClose, onSent }: CreateCampaignModalProps) {
  const { user } = useAuth();
  const { toast } = useToast();
  const isAdmin = user?.role === 'schoolAdmin';

  const createCampaign = useCreateCampaign();
  const { data: classes } = useClasses();

  const [messageType, setMessageType] = useState('general');
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [audienceType, setAudienceType] = useState<NotificationAudienceType>('classes');
  const [selectedClassIds, setSelectedClassIds] = useState<string[]>([]);
  const [studentPickerClassId, setStudentPickerClassId] = useState('');
  const [selectedStudents, setSelectedStudents] = useState<SelectedStudent[]>([]);
  const [scheduleEnabled, setScheduleEnabled] = useState(false);
  const [scheduledLocal, setScheduledLocal] = useState('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setMessageType('general');
      setTitle('');
      setBody('');
      setAudienceType('classes');
      setSelectedClassIds([]);
      setStudentPickerClassId('');
      setSelectedStudents([]);
      setScheduleEnabled(false);
      setScheduledLocal('');
      setError(null);
    }
  }, [open]);

  const audienceOptions = useMemo(() => {
    const opts = [
      { value: 'classes', label: 'Specific classes' },
      { value: 'students', label: 'Specific students' },
    ];
    // Only school admins may broadcast to the whole school (wholeSchool
    // permission is false for teachers — enforced server-side too).
    if (isAdmin) opts.unshift({ value: 'school', label: 'Whole school' });
    return opts;
  }, [isAdmin]);

  const toggleClass = (id: string) =>
    setSelectedClassIds((prev) => (prev.includes(id) ? prev.filter((c) => c !== id) : [...prev, id]));

  const toggleStudent = (student: SelectedStudent) =>
    setSelectedStudents((prev) =>
      prev.some((s) => s.id === student.id)
        ? prev.filter((s) => s.id !== student.id)
        : [...prev, student]
    );

  const handleSubmit = async () => {
    setError(null);
    const trimmedTitle = title.trim();
    const trimmedBody = body.trim();
    if (!trimmedTitle) return setError('Add a title.');
    if (trimmedTitle.length > TITLE_MAX) return setError(`Title must be ${TITLE_MAX} characters or fewer.`);
    if (!trimmedBody) return setError('Add a message.');
    if (trimmedBody.length > BODY_MAX) return setError(`Message must be ${BODY_MAX} characters or fewer.`);
    if (audienceType === 'classes' && selectedClassIds.length === 0) return setError('Select at least one class.');
    if (audienceType === 'students' && selectedStudents.length === 0) return setError('Select at least one student.');

    let scheduledFor: number | null = null;
    if (scheduleEnabled) {
      if (!scheduledLocal) return setError('Pick a date and time to schedule.');
      const ms = new Date(scheduledLocal).getTime();
      if (Number.isNaN(ms)) return setError('Invalid schedule time.');
      if (ms <= Date.now()) return setError('Scheduled time must be in the future.');
      scheduledFor = ms;
    }

    if (!user?.schoolId) return setError('Missing school context. Try reloading.');

    const input: CreateCampaignInput = {
      schoolId: user.schoolId,
      title: trimmedTitle,
      body: trimmedBody,
      messageType,
      audienceType,
      classIds: audienceType === 'classes' ? selectedClassIds : [],
      studentIds: audienceType === 'students' ? selectedStudents.map((s) => s.id) : [],
      scheduledFor,
    };

    try {
      await createCampaign.mutateAsync(input);
      onSent(scheduledFor !== null);
    } catch (e) {
      const message = e instanceof Error ? e.message : 'Failed to send notification.';
      setError(message);
      toast(message, 'error');
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="New Message"
      description="Parents linked to the selected children get a push notification and an in-app message."
      size="lg"
      footer={
        <>
          <Button variant="outline" onClick={onClose} disabled={createCampaign.isPending}>
            Cancel
          </Button>
          <Button onClick={handleSubmit} loading={createCampaign.isPending}>
            {scheduleEnabled ? 'Schedule' : 'Send Now'}
          </Button>
        </>
      }
    >
      <form className="space-y-4" onSubmit={(e) => e.preventDefault()}>
        <Select
          label="Message type"
          options={MESSAGE_TYPE_OPTIONS}
          value={messageType}
          onChange={setMessageType}
        />

        <div>
          <Input
            label="Title"
            placeholder="e.g. Reading week starts Monday"
            value={title}
            maxLength={TITLE_MAX}
            onChange={(e) => setTitle(e.target.value)}
          />
          <p className="mt-1 text-xs text-text-secondary text-right">
            {title.length}/{TITLE_MAX}
          </p>
        </div>

        <div>
          <label className="block text-sm font-semibold text-charcoal mb-1.5">Message</label>
          <textarea
            value={body}
            maxLength={BODY_MAX}
            onChange={(e) => setBody(e.target.value)}
            rows={4}
            placeholder="Write your message to parents…"
            className="w-full px-4 py-3 rounded-[var(--radius-md)] border border-divider bg-surface text-charcoal placeholder:text-text-secondary/50 focus:outline-none focus:ring-2 focus:ring-rose-pink/30 focus:border-rose-pink transition-colors text-[15px] resize-y"
          />
          <p className="mt-1 text-xs text-text-secondary text-right">
            {body.length}/{BODY_MAX}
          </p>
        </div>

        <Select
          label="Send to"
          options={audienceOptions}
          value={audienceType}
          onChange={(v) => setAudienceType(v as NotificationAudienceType)}
        />

        {audienceType === 'school' && (
          <p className="text-sm text-text-secondary px-1">
            Every parent in the school with a linked child will receive this message.
          </p>
        )}

        {audienceType === 'classes' && (
          <div>
            <label className="block text-sm font-semibold text-charcoal mb-1.5">Classes</label>
            <div className="space-y-1 max-h-48 overflow-y-auto rounded-[var(--radius-md)] border border-divider p-2">
              {(classes ?? []).map((c) => (
                <label
                  key={c.id}
                  className="flex items-center gap-2 cursor-pointer px-1 py-1 rounded-[var(--radius-sm)] hover:bg-background"
                >
                  <input
                    type="checkbox"
                    checked={selectedClassIds.includes(c.id)}
                    onChange={() => toggleClass(c.id)}
                    className="w-4 h-4 rounded border-divider text-rose-pink focus:ring-rose-pink/30"
                  />
                  <span className="text-sm text-charcoal">{c.name}</span>
                  <span className="text-xs text-text-secondary">
                    {c.studentIds.length} student{c.studentIds.length === 1 ? '' : 's'}
                  </span>
                </label>
              ))}
              {(classes ?? []).length === 0 && (
                <p className="text-xs text-text-secondary py-2 text-center">No classes available.</p>
              )}
            </div>
          </div>
        )}

        {audienceType === 'students' && (
          <div className="space-y-2">
            {selectedStudents.length > 0 && (
              <div className="flex flex-wrap gap-1.5">
                {selectedStudents.map((s) => (
                  <span
                    key={s.id}
                    className="inline-flex items-center gap-1 px-2 py-0.5 rounded-[var(--radius-pill)] bg-brand-primary/10 text-xs font-semibold text-charcoal"
                  >
                    {s.name}
                    <button
                      type="button"
                      onClick={() => toggleStudent(s)}
                      className="text-text-secondary hover:text-error ml-0.5"
                    >
                      &times;
                    </button>
                  </span>
                ))}
              </div>
            )}
            <Select
              label="Pick a class to choose students from"
              options={(classes ?? []).map((c) => ({ value: c.id, label: c.name }))}
              value={studentPickerClassId}
              onChange={setStudentPickerClassId}
              placeholder="Select a class"
            />
            {studentPickerClassId && (
              <StudentPicker
                classId={studentPickerClassId}
                selectedIds={selectedStudents.map((s) => s.id)}
                onToggle={toggleStudent}
              />
            )}
          </div>
        )}

        <div className="pt-1">
          <label className="flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              checked={scheduleEnabled}
              onChange={(e) => setScheduleEnabled(e.target.checked)}
              className="w-4 h-4 rounded border-divider text-rose-pink focus:ring-rose-pink/30"
            />
            <span className="text-sm font-semibold text-charcoal">Schedule for later</span>
          </label>
          {scheduleEnabled && (
            <input
              type="datetime-local"
              value={scheduledLocal}
              onChange={(e) => setScheduledLocal(e.target.value)}
              className="mt-2 w-full px-4 py-3 rounded-[var(--radius-md)] border border-divider bg-surface text-charcoal focus:outline-none focus:ring-2 focus:ring-rose-pink/30 focus:border-rose-pink transition-colors text-[15px]"
            />
          )}
        </div>

        {error && <p className="text-sm text-error">{error}</p>}
      </form>
    </Modal>
  );
}

// Renders only when a class is chosen, so useStudents always has a real classId
// (the students API is not teacher-scoped — scoping by an owned class keeps the
// list correct and small, and matches the server-side audience validation).
function StudentPicker({
  classId,
  selectedIds,
  onToggle,
}: {
  classId: string;
  selectedIds: string[];
  onToggle: (student: SelectedStudent) => void;
}) {
  const { data: students, isLoading } = useStudents({ classId });

  if (isLoading) {
    return <p className="text-xs text-text-secondary py-2 px-1">Loading students…</p>;
  }

  const list = students ?? [];
  if (list.length === 0) {
    return <p className="text-xs text-text-secondary py-2 text-center">No students in this class.</p>;
  }

  return (
    <div className="space-y-1 max-h-44 overflow-y-auto rounded-[var(--radius-md)] border border-divider p-2">
      {list.map((s) => {
        const name = `${s.firstName} ${s.lastName}`.trim();
        return (
          <label
            key={s.id}
            className="flex items-center gap-2 cursor-pointer px-1 py-1 rounded-[var(--radius-sm)] hover:bg-background"
          >
            <input
              type="checkbox"
              checked={selectedIds.includes(s.id)}
              onChange={() => onToggle({ id: s.id, name })}
              className="w-4 h-4 rounded border-divider text-rose-pink focus:ring-rose-pink/30"
            />
            <span className="text-sm text-charcoal">{name}</span>
          </label>
        );
      })}
    </div>
  );
}
