import { notFound } from "next/navigation";
import { PageHeader } from "@/components/layout/page-header";
import { getSchool } from "@/lib/firestore/schools";
import { listBooks } from "@/lib/firestore/books";
import { SchoolLibrary } from "./school-library";

export default async function LibraryPage({
  params,
}: {
  params: Promise<{ schoolId: string }>;
}) {
  const { schoolId } = await params;

  const [school, books] = await Promise.all([
    getSchool(schoolId),
    listBooks(schoolId),
  ]);

  if (!school) notFound();

  return (
    <>
      <PageHeader
        title={`${school.name} - Library`}
        description={`${books.length} books`}
      />
      <SchoolLibrary schoolId={schoolId} books={books} />
    </>
  );
}
