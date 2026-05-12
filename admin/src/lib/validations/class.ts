import { z } from "zod";

export const createClassSchema = z.object({
  name: z.string().min(1, "Class name is required"),
  yearLevel: z.string().optional(),
  room: z.string().optional(),
  teacherId: z.string().min(1, "Teacher is required"),
  defaultMinutesTarget: z.number().int().min(1).optional(),
  description: z.string().optional(),
});

export const updateClassSchema = createClassSchema.partial();

export type CreateClassInput = z.infer<typeof createClassSchema>;
export type UpdateClassInput = z.infer<typeof updateClassSchema>;
