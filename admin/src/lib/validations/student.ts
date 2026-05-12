import { z } from "zod";

export const createStudentSchema = z.object({
  firstName: z.string().min(1, "First name is required"),
  lastName: z.string().min(1, "Last name is required"),
  studentId: z.string().optional(),
  classId: z.string().min(1, "Class is required"),
  currentReadingLevel: z.string().optional(),
});

export const updateStudentSchema = createStudentSchema.partial();

export const updateReadingLevelSchema = z.object({
  level: z.string().min(1, "Reading level is required"),
  levelIndex: z.number().optional(),
  reason: z.string().optional(),
  source: z.string().optional(),
});

export type CreateStudentInput = z.infer<typeof createStudentSchema>;
export type UpdateStudentInput = z.infer<typeof updateStudentSchema>;
export type UpdateReadingLevelInput = z.infer<typeof updateReadingLevelSchema>;
