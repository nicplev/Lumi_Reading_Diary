import { z } from "zod";

export const bulkStudentRowSchema = z.object({
  firstName: z.string().min(1, "First name is required").max(100, "First name too long"),
  lastName: z.string().min(1, "Last name is required").max(100, "Last name too long"),
  studentId: z.string().max(50, "Student ID too long").optional(),
  className: z.string().min(1, "Class name is required").max(100, "Class name too long"),
  currentReadingLevel: z.string().max(50, "Reading level too long").optional(),
});

export const MAX_BULK_ROWS = 1000;

export type BulkStudentRow = z.infer<typeof bulkStudentRowSchema>;
