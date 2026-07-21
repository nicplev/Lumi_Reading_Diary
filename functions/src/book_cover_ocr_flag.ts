// Dependency-free cover-OCR flag resolution shared with parity tests. Keep
// Firebase imports out of this module so the root/admin CI can verify the
// contract without installing the separate Cloud Functions dependency tree.

export const COVER_OCR_FLAG_DOC = "platformConfig/coverOcr";

// Only a literal false disables this benign metadata feature. Missing or
// malformed data intentionally fails open; see book_cover_ocr.ts.
export function coverOcrEnabledFromDoc(data: unknown): boolean {
  if (!data || typeof data !== "object" || Array.isArray(data)) return true;
  return (data as Record<string, unknown>).enabled !== false;
}
