import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getSchool, updateSchool } from '@/lib/firestore/school';
import { z } from 'zod';

function serializeSchool(s: Record<string, unknown>) {
  return {
    ...s,
    createdAt: s.createdAt instanceof Date ? s.createdAt.toISOString() : s.createdAt,
    subscriptionExpiry: s.subscriptionExpiry instanceof Date ? s.subscriptionExpiry.toISOString() : s.subscriptionExpiry ?? null,
    termDates: s.termDates
      ? Object.fromEntries(
          Object.entries(s.termDates as Record<string, unknown>).map(([k, v]) => [
            k,
            v instanceof Date ? v.toISOString() : v,
          ])
        )
      : {},
  };
}

export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const school = await getSchool(session.schoolId);
    if (!school) return NextResponse.json({ error: 'School not found' }, { status: 404 });
    return NextResponse.json(serializeSchool(school as unknown as Record<string, unknown>));
  } catch {
    return NextResponse.json({ error: 'Failed to fetch school settings' }, { status: 500 });
  }
}

const updateSchema = z.object({
  name: z.string().min(1).optional(),
  displayName: z.string().optional(),
  logoUrl: z.string().optional(),
  primaryColor: z.string().optional(),
  secondaryColor: z.string().optional(),
  levelSchema: z.enum(['none', 'aToZ', 'pmBenchmark', 'lexile', 'numbered', 'namedLevels', 'colouredLevels', 'custom']).optional(),
  customLevels: z.array(z.string()).optional(),
  levelColors: z.record(z.string()).optional(),
  timezone: z.string().optional(),
  address: z.string().optional(),
  contactEmail: z.string().email().optional().or(z.literal('')),
  contactPhone: z.string().optional(),
  quietHours: z.record(z.string()).optional(),
  termDates: z.record(z.string()).optional(),
  parentCommentSettings: z.object({
    enabled: z.boolean(),
    freeTextEnabled: z.boolean(),
    customPresets: z.array(z.object({
      id: z.string().min(1),
      name: z.string().min(1).max(50),
      chips: z.array(z.string().min(1).max(100)).max(20),
    })).max(10),
  }).optional(),
  achievementCustomization: z.object({
    streak: z.tuple([
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
    ]).optional(),
    books: z.tuple([
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
    ]).optional(),
    minutes: z.tuple([
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
    ]).optional(),
    readingDays: z.tuple([
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
      z.object({ name: z.string().max(40).optional(), color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional() }),
    ]).optional(),
  }).optional(),
  achievementThresholds: z.object({
    streak:      z.tuple([z.number().int().min(1), z.number().int().min(1), z.number().int().min(1), z.number().int().min(1), z.number().int().min(1)]),
    books:       z.tuple([z.number().int().min(1), z.number().int().min(1), z.number().int().min(1), z.number().int().min(1), z.number().int().min(1)]),
    minutes:     z.tuple([z.number().int().min(1), z.number().int().min(1), z.number().int().min(1), z.number().int().min(1), z.number().int().min(1)]),
    readingDays: z.tuple([z.number().int().min(1), z.number().int().min(1), z.number().int().min(1), z.number().int().min(1)]),
  }).optional().superRefine((thresholds, ctx) => {
    if (!thresholds) return;
    const categories: Array<{ key: keyof typeof thresholds; label: string }> = [
      { key: 'streak', label: 'Streak' },
      { key: 'books', label: 'Books' },
      { key: 'minutes', label: 'Minutes' },
      { key: 'readingDays', label: 'Reading Days' },
    ];
    for (const { key, label } of categories) {
      const values = thresholds[key] as number[];
      for (let i = 1; i < values.length; i++) {
        if (values[i] <= values[i - 1]) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: `${label} tier ${i + 1} must be greater than tier ${i}`,
            path: [key, i],
          });
        }
      }
    }
  }),
});

export async function PATCH(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can update settings' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const data = updateSchema.parse(body);
    await updateSchool(session.schoolId, data);
    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    return NextResponse.json({ error: 'Failed to update settings' }, { status: 500 });
  }
}
