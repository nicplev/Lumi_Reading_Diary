import { z } from "zod";

export const subscriptionStatusSchema = z.enum([
  "paid",
  "unpaid",
  "comp",
  "trial",
  "grace",
  "cancelled",
]);

export const subscriptionTierSchema = z.enum(["S", "M", "L", "XL"]);

export const upsertSubscriptionSchema = z.object({
  schoolId: z.string().min(1),
  academicYear: z.number().int().min(2020).max(2100),
  status: subscriptionStatusSchema,
  tier: subscriptionTierSchema.optional(),
  amount: z.number().nonnegative().optional(),
  currency: z.string().length(3).optional(),
  invoiceRef: z.string().max(200).optional(),
  paidAt: z.string().datetime().nullable().optional(),
  notes: z.string().max(2000).optional(),
});

export type UpsertSubscriptionBody = z.infer<typeof upsertSubscriptionSchema>;
