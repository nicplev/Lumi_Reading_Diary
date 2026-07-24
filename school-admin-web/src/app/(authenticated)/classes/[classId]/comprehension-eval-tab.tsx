'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { toCsv } from '@/lib/csv-export';
import { Badge } from '@/components/lumi/badge';
import { Button } from '@/components/lumi/button';
import { Card } from '@/components/lumi/card';
import { FilterChip } from '@/components/lumi/filter-chip';
import { Icon } from '@/components/lumi/icon';
import { EmptyState } from '@/components/lumi/empty-state';
import { useStudents } from '@/lib/hooks/use-students';

// Class-wide AI comprehension evaluations. Read-only decision support:
// levels + confidence + flags only (the internal numeric key is never
// returned by the API, so it cannot leak into the UI or the CSV export).

interface EvalRecord {
  logId: string;
  studentId: string;
  logDate: string | null;
  status: string;
  overallLevel: string | null;
  confidence: string | null;
  summary: string | null;
  flags: string[];
  assessable: boolean;
  questionTextUsed: string | null;
  questionSource: string | null;
  transcript: string | null;
  transcriptRemovedAt: string | null;
  criterionScores: Array<{ criterionId: string; score: number; evidence: string }>;
  audioUploadedAt: string | null;
  evaluatedAt: string | null;
}

const LEVEL_LABELS: Record<string, string> = {
  not_evident: 'Not evident',
  emerging: 'Emerging',
  developing: 'Developing',
  secure: 'Secure',
};

const FLAG_LABELS: Record<string, string> = {
  too_short: 'Recording too short',
  inaudible: 'Inaudible',
  off_topic: 'Off topic',
  non_english: 'Non-English',
  low_stt_confidence: 'Unclear audio',
  question_mismatch: 'Question mismatch',
  concerning_content: 'Needs review',
  audio_unavailable: 'Recording unavailable',
  system_error: "Couldn't evaluate",
  prompt_injection: 'Unusual content',
  adult_prompting: 'Adult prompting',
  recitation_blocked: 'Read aloud verbatim',
  empty_response: 'No answer detected',
  unsupported_self_assessment: 'Self-grading detected',
  incidental_personal_info: 'Personal info mentioned',
};

function levelLabel(level: string | null, status: string): string {
  if (status === 'failed') return "Couldn't evaluate";
  if (status === 'skipped') return 'Not evaluated';
  return level ? LEVEL_LABELS[level] ?? level : 'Needs review';
}

function flagLabel(flag: string): string {
  return FLAG_LABELS[flag] ?? flag.replace(/_/g, ' ');
}

type DatePreset = 'all' | '7d' | '30d';

export function ComprehensionEvalTab({
  classId,
  className,
}: {
  classId: string;
  className: string;
}) {
  const { data: students } = useStudents({ classId });
  const studentNames = useMemo(() => {
    const names: Record<string, string> = {};
    for (const s of students ?? []) {
      names[s.id] = `${s.firstName} ${s.lastName}`.trim();
    }
    return names;
  }, [students]);
  const [loading, setLoading] = useState(true);
  const [enabled, setEnabled] = useState(false);
  const [evals, setEvals] = useState<EvalRecord[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [datePreset, setDatePreset] = useState<DatePreset>('all');
  const [levelFilter, setLevelFilter] = useState<Set<string>>(new Set());
  const [needsReviewOnly, setNeedsReviewOnly] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(
        `/api/comprehension-evals?classId=${encodeURIComponent(classId)}`
      );
      if (!res.ok) throw new Error('Failed to load evaluations');
      const data = await res.json();
      setEnabled(data.enabled === true);
      setEvals(Array.isArray(data.evals) ? data.evals : []);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load');
    } finally {
      setLoading(false);
    }
  }, [classId]);

  useEffect(() => {
    void load();
  }, [load]);

  const filtered = useMemo(() => {
    const now = Date.now();
    return evals.filter((e) => {
      if (needsReviewOnly && !(e.status === 'flagged' || e.status === 'failed')) {
        return false;
      }
      if (levelFilter.size > 0 && !(e.overallLevel && levelFilter.has(e.overallLevel))) {
        return false;
      }
      const dateStr = e.logDate ?? e.evaluatedAt;
      if (datePreset !== 'all' && dateStr) {
        const ageDays = (now - new Date(dateStr).getTime()) / 86_400_000;
        if (datePreset === '7d' && ageDays > 7) return false;
        if (datePreset === '30d' && ageDays > 30) return false;
      }
      return true;
    });
  }, [evals, needsReviewOnly, levelFilter, datePreset]);

  function downloadCsv() {
    // Levels + flags only — never any numeric score.
    const rows: Array<Array<string | null>> = [
      ['Student', 'Date', 'Level', 'Confidence', 'Flags', 'Summary'],
      ...filtered.map((e) => [
        studentNames[e.studentId] ?? e.studentId,
        e.logDate ? new Date(e.logDate).toLocaleDateString() : '',
        levelLabel(e.overallLevel, e.status),
        e.confidence ?? '',
        e.flags.map(flagLabel).join('; '),
        e.summary ?? '',
      ]),
    ];
    const csv = toCsv(rows);
    const blob = new Blob([`﻿${csv}`], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `comprehension-${className.replace(/[^a-z0-9]+/gi, '-')}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  if (loading) {
    return <Card className="p-6 text-sm text-muted">Loading evaluations…</Card>;
  }
  if (error) {
    return (
      <Card className="p-6">
        <p className="text-sm text-muted">{error}</p>
        <Button variant="outline" size="sm" onClick={load} className="mt-3">
          Retry
        </Button>
      </Card>
    );
  }
  if (!enabled) {
    return (
      <EmptyState
        icon={<Icon name="graphic_eq" size={40} />}
        title="AI comprehension evaluation isn't enabled"
        description="This add-on transcribes and reviews children's spoken comprehension answers for teachers. Contact Lumi to enable it for your school."
      />
    );
  }

  return (
    <div className="space-y-4">
      <Card className="p-4 bg-section-tint/20 border-section/30">
        <p className="text-sm">
          AI-generated assessments — may be inaccurate. Listen to the
          recording and use your professional judgement before acting. Never
          use these as formal assessment.
        </p>
      </Card>

      <div className="flex flex-wrap items-center gap-2">
        <FilterChip label="All" selected={datePreset === 'all'} onClick={() => setDatePreset('all')} />
        <FilterChip label="Last 7 days" selected={datePreset === '7d'} onClick={() => setDatePreset('7d')} />
        <FilterChip label="Last 30 days" selected={datePreset === '30d'} onClick={() => setDatePreset('30d')} />
        <span className="mx-1 h-5 w-px bg-rule" />
        {Object.entries(LEVEL_LABELS).map(([level, label]) => (
          <FilterChip
            key={level}
            label={label}
            selected={levelFilter.has(level)}
            onClick={() =>
              setLevelFilter((prev) => {
                const next = new Set(prev);
                if (!next.delete(level)) next.add(level);
                return next;
              })
            }
          />
        ))}
        <span className="mx-1 h-5 w-px bg-rule" />
        <FilterChip
          label="Needs review"
          selected={needsReviewOnly}
          onClick={() => setNeedsReviewOnly((v) => !v)}
        />
        <div className="ml-auto">
          <Button variant="outline" size="sm" onClick={downloadCsv}>
            Export CSV
          </Button>
        </div>
      </div>

      {filtered.length === 0 ? (
        <EmptyState
          icon={<Icon name="graphic_eq" size={40} />}
          title={evals.length === 0 ? 'No evaluations yet' : 'Nothing matches these filters'}
          description={
            evals.length === 0
              ? "Evaluations appear here after children record comprehension answers in the parent app."
              : 'Try widening the date or level filters.'
          }
        />
      ) : (
        <Card className="divide-y divide-rule p-0">
          {filtered.map((evalRecord) => {
            const isOpen = expanded === evalRecord.logId;
            const name = studentNames[evalRecord.studentId] ?? 'Student';
            return (
              <div key={evalRecord.logId}>
                <button
                  type="button"
                  className="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-cream/60"
                  onClick={() => setExpanded(isOpen ? null : evalRecord.logId)}
                >
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">{name}</p>
                    <p className="text-xs text-muted">
                      {evalRecord.logDate
                        ? new Date(evalRecord.logDate).toLocaleDateString()
                        : ''}
                      {evalRecord.flags.length > 0
                        ? ` · ${evalRecord.flags.length} flag${evalRecord.flags.length > 1 ? 's' : ''}`
                        : ''}
                    </p>
                  </div>
                  <Badge>{levelLabel(evalRecord.overallLevel, evalRecord.status)}</Badge>
                  {evalRecord.confidence && (
                    <span className="text-xs text-muted">{evalRecord.confidence}</span>
                  )}
                  <Icon name={isOpen ? 'expand_less' : 'expand_more'} size={18} />
                </button>
                {isOpen && (
                  <div className="space-y-3 px-4 pb-4">
                    {evalRecord.questionTextUsed && (
                      <div>
                        <p className="text-xs font-semibold text-muted">Question asked</p>
                        <p className="text-sm">{evalRecord.questionTextUsed}</p>
                        {evalRecord.questionSource && evalRecord.questionSource !== 'log' && (
                          <p className="text-xs text-muted">
                            The class question may have changed since this recording.
                          </p>
                        )}
                      </div>
                    )}
                    {evalRecord.audioUploadedAt && (
                      <div>
                        <p className="text-xs font-semibold text-muted">Recording</p>
                        <audio
                          controls
                          preload="none"
                          src={`/api/reading-logs/${evalRecord.logId}/audio`}
                          className="h-9 w-full max-w-md"
                        />
                      </div>
                    )}
                    <div>
                      <p className="text-xs font-semibold text-muted">Transcript</p>
                      {evalRecord.transcript ? (
                        <p className="rounded-md bg-cream p-3 text-sm">{evalRecord.transcript}</p>
                      ) : (
                        <p className="text-xs text-muted">
                          {evalRecord.transcriptRemovedAt
                            ? 'Transcript removed after the retention period.'
                            : 'No transcript available.'}
                        </p>
                      )}
                    </div>
                    {evalRecord.summary && (
                      <div>
                        <p className="text-xs font-semibold text-muted">AI summary</p>
                        <p className="text-sm">{evalRecord.summary}</p>
                      </div>
                    )}
                    {evalRecord.criterionScores.length > 0 && (
                      <div>
                        <p className="text-xs font-semibold text-muted">What the response showed</p>
                        <ul className="space-y-1">
                          {evalRecord.criterionScores.map((c) => (
                            <li key={c.criterionId} className="text-sm">
                              <span className="font-medium">
                                {c.criterionId.replace(/_/g, ' ')}
                              </span>
                              {': '}
                              <span aria-label={`${c.score} of 3`}>
                                {'●'.repeat(c.score)}
                                {'○'.repeat(Math.max(0, 3 - c.score))}
                              </span>
                              {c.evidence && (
                                <span className="text-muted"> — “{c.evidence}”</span>
                              )}
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                    {evalRecord.flags.length > 0 && (
                      <div className="flex flex-wrap gap-1.5">
                        {evalRecord.flags.map((flag) => (
                          <Badge key={flag}>{flagLabel(flag)}</Badge>
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </Card>
      )}
    </div>
  );
}
