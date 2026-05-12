import { z } from "zod";

export const createAllocationSchema = z
  .object({
    classId: z.string().min(1, "Class is required"),
    teacherId: z.string().min(1, "Teacher is required"),
    studentIds: z.array(z.string()).min(1, "At least one student is required"),
    type: z.enum(["byLevel", "byTitle", "freeChoice"]),
    cadence: z.enum(["daily", "weekly", "fortnightly", "custom"]),
    targetMinutes: z.number().int().min(1, "Target minutes must be at least 1"),
    startDate: z.string().min(1, "Start date is required"),
    endDate: z.string().min(1, "End date is required"),
    levelStart: z.string().optional(),
    levelEnd: z.string().optional(),
    bookIds: z.array(z.string()).optional(),
    bookTitles: z.array(z.string()).optional(),
    isRecurring: z.boolean().optional(),
    templateName: z.string().optional(),
  })
  .refine((data) => new Date(data.endDate) > new Date(data.startDate), {
    message: "End date must be after start date",
    path: ["endDate"],
  });

export const updateAllocationSchema = z.object({
  targetMinutes: z.number().int().min(1).optional(),
  endDate: z.string().optional(),
  isActive: z.boolean().optional(),
  bookIds: z.array(z.string()).optional(),
  bookTitles: z.array(z.string()).optional(),
  templateName: z.string().optional(),
});

export type CreateAllocationInput = z.infer<typeof createAllocationSchema>;
export type UpdateAllocationInput = z.infer<typeof updateAllocationSchema>;
