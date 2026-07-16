import { z } from "zod";

export const createSchoolCodeSchema = z.object({
  schoolId: z.string().min(1, "School is required"),
  maxUsages: z.number().int().min(1).max(500).optional(),
  expiresInDays: z.number().int().min(1).max(90).optional(),
});

export type CreateSchoolCodeInput = z.infer<typeof createSchoolCodeSchema>;
