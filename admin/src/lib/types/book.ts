import type { FirestoreTimestamp } from "./common";

export interface Book {
  id: string;
  title: string;
  author?: string;
  isbn?: string;
  coverImageUrl?: string;
  description?: string;
  genres: string[];
  readingLevel?: string;
  pageCount?: number;
  publisher?: string;
  publishedDate?: FirestoreTimestamp;
  tags: string[];
  averageRating?: number;
  ratingCount: number;
  isPopular: boolean;
  timesRead: number;
  createdAt: FirestoreTimestamp;
  addedBy?: string;
  metadata?: Record<string, unknown>;
  scannedByTeacherIds: string[];
  timesAssignedSchoolWide: number;
}
