import { z } from "zod";

export const createBookSchema = z.object({
  title: z.string().min(1, "Title is required"),
  author: z.string().optional(),
  isbn: z.string().optional(),
  coverImageUrl: z
    .string()
    .url("Must be a valid URL")
    .or(z.literal(""))
    .optional(),
  description: z.string().optional(),
  genres: z.array(z.string()).optional(),
  readingLevel: z.string().optional(),
  pageCount: z.number().int().min(1).optional(),
  publisher: z.string().optional(),
  tags: z.array(z.string()).optional(),
});

export const updateBookSchema = createBookSchema.partial();

export type CreateBookInput = z.infer<typeof createBookSchema>;
export type UpdateBookInput = z.infer<typeof updateBookSchema>;
