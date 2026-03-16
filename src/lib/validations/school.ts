import { z } from "zod";

export const createSchoolSchema = z.object({
  name: z.string().min(1, "School name is required"),
  contactEmail: z.string().optional(),
  contactPhone: z.string().optional(),
  address: z.string().optional(),
  timezone: z.string().min(1, "Timezone is required"),
  levelSchema: z.enum(["aToZ", "pmBenchmark", "lexile", "custom"]),
  customLevels: z.array(z.string()).optional(),
  subscriptionPlan: z.string().optional(),
});

export const updateSchoolSchema = createSchoolSchema.partial();

export type CreateSchoolInput = z.infer<typeof createSchoolSchema>;
export type UpdateSchoolInput = z.infer<typeof updateSchoolSchema>;
