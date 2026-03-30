export type ReadingLevelSchema =
  | 'none'
  | 'aToZ'
  | 'pmBenchmark'
  | 'lexile'
  | 'numbered'
  | 'namedLevels'
  | 'colouredLevels'
  | 'custom';

export interface School {
  id: string;
  name: string;
  displayName?: string;
  logoUrl?: string;
  primaryColor?: string;
  secondaryColor?: string;
  levelSchema: ReadingLevelSchema;
  customLevels?: string[];
  levelColors?: Record<string, string>;
  termDates: Record<string, Date>;
  quietHours: Record<string, string>;
  timezone: string;
  address?: string;
  contactEmail?: string;
  contactPhone?: string;
  isActive: boolean;
  createdAt: Date;
  createdBy: string;
  settings?: Record<string, unknown>;
  studentCount: number;
  teacherCount: number;
  subscriptionPlan?: string;
  subscriptionExpiry?: Date;
}

export function getReadingLevels(schema: ReadingLevelSchema, customLevels?: string[]): string[] {
  switch (schema) {
    case 'none':
      return [];
    case 'aToZ':
      return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
    case 'pmBenchmark':
      return Array.from({ length: 30 }, (_, i) => `${i + 1}`);
    case 'lexile':
      return ['BR', '100L', '200L', '300L', '400L', '500L', '600L', '700L', '800L', '900L', '1000L', '1100L', '1200L', '1300L', '1400L'];
    case 'numbered':
      return Array.from({ length: 100 }, (_, i) => `${i + 1}`);
    case 'namedLevels':
    case 'colouredLevels':
    case 'custom':
      return customLevels ?? [];
  }
}
