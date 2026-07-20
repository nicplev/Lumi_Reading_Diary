import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getClassReport } from '@/lib/firestore/reports';
import { teacherTeachesClass } from '@/lib/firestore/comprehensionEvals';
import {
  getSchoolTimezone,
  localDateString,
  shiftDateStr,
  zonedDayStart,
} from '@/lib/school-time';

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/** Resolve a `from`/`to` query param to a school-local "YYYY-MM-DD", or null on garbage. */
function toDateStr(param: string | null, tz: string): string | null | undefined {
  if (!param) return undefined; // absent — caller applies its default
  if (DATE_RE.test(param)) return param;
  const parsed = new Date(param);
  if (Number.isNaN(parsed.getTime())) return null; // present but invalid
  return localDateString(parsed, tz);
}

export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { searchParams } = new URL(request.url);
  const classId = searchParams.get('classId');
  if (!classId) return NextResponse.json({ error: 'classId is required' }, { status: 400 });

  // A teacher may only pull a report for a class they teach; schoolAdmin sees
  // any class in their school. Mirrors /api/comprehension-evals.
  if (session.role !== 'schoolAdmin') {
    const teaches = await teacherTeachesClass(session.schoolId, classId, session.uid);
    if (!teaches) return NextResponse.json({ error: 'Forbidden' }, { status: 403 });
  }

  // Day boundaries are the SCHOOL's calendar days, not the server's — the
  // portal runs in a non-AU region, so server-local setHours() started
  // "today" up to ~14h late for AU schools.
  const tz = await getSchoolTimezone(session.schoolId);

  const toRaw = toDateStr(searchParams.get('to'), tz);
  const fromRaw = toDateStr(searchParams.get('from'), tz);
  if (toRaw === null || fromRaw === null) {
    return NextResponse.json({ error: 'Invalid date range' }, { status: 400 });
  }
  const toStr = toRaw ?? localDateString(new Date(), tz);
  const fromStr = fromRaw ?? shiftDateStr(toStr, -30);
  if (fromStr > toStr) {
    return NextResponse.json({ error: 'Invalid date range' }, { status: 400 });
  }

  // Inclusive day boundaries in school-local time.
  const from = zonedDayStart(fromStr, tz);
  const to = new Date(zonedDayStart(shiftDateStr(toStr, 1), tz).getTime() - 1);

  try {
    const report = await getClassReport(session.schoolId, classId, from, to);
    return NextResponse.json(report);
  } catch {
    return NextResponse.json({ error: 'Failed to build report' }, { status: 500 });
  }
}
