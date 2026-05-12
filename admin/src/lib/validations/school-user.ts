import { z } from "zod";

export const createSchoolUserSchema = z.object({
  email: z.string().email("Valid email is required"),
  fullName: z.string().min(1, "Full name is required"),
  role: z.enum(["teacher", "schoolAdmin"]),
  classIds: z.array(z.string()).optional(),
});

export const updateSchoolUserSchema = createSchoolUserSchema.partial();

export const userAuthActionSchema = z.discriminatedUnion("action", [
  z.object({ action: z.literal("disable") }),
  z.object({ action: z.literal("enable") }),
  z.object({ action: z.literal("resetPassword") }),
]);

export type CreateSchoolUserInput = z.infer<typeof createSchoolUserSchema>;
export type UpdateSchoolUserInput = z.infer<typeof updateSchoolUserSchema>;
export type UserAuthActionInput = z.infer<typeof userAuthActionSchema>;
