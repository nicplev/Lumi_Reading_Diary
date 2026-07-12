"use client";

import { useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { type ColumnDef } from "@tanstack/react-table";
import { toast } from "sonner";
import { ImageOff, Upload } from "lucide-react";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { formatDate } from "@/lib/utils";
import type { CommunityBookListItem } from "@/lib/firestore/community-books";

// Covers can live in Firebase Storage (teacher uploads / overrides) or on
// external hosts (Google Books, OpenLibrary — whatever the scan flow
// resolved). Plain lazy <img> keeps this free: the URL is already on the
// doc the page fetches, the browser only pulls bytes for visible rows,
// and caches them.
function CoverThumb({
  book,
  className,
}: {
  book: CommunityBookListItem;
  className: string;
}) {
  const [broken, setBroken] = useState(false);
  if (!book.coverImageUrl || broken) {
    return (
      <div
        className={`${className} flex items-center justify-center bg-muted text-muted-foreground`}
        title={broken ? "Cover URL is broken" : "No cover"}
      >
        <ImageOff className="h-4 w-4" />
      </div>
    );
  }
  return (
    // eslint-disable-next-line @next/next/no-img-element -- arbitrary external hosts; next/image would need remotePatterns + optimization fetches
    <img
      src={book.coverImageUrl}
      alt={`Cover of ${book.title || book.isbn}`}
      loading="lazy"
      className={`${className} object-cover`}
      onError={() => setBroken(true)}
    />
  );
}

function buildColumns(
  onSelectBook: (book: CommunityBookListItem) => void
): ColumnDef<CommunityBookListItem>[] {
  return [
    {
      id: "cover",
      header: "Cover",
      enableSorting: false,
      cell: ({ row }) => (
        <button
          type="button"
          onClick={() => onSelectBook(row.original)}
          className="block transition-opacity hover:opacity-80"
          title="Click to view or replace this cover"
        >
          <CoverThumb
            book={row.original}
            className="h-14 w-10 rounded ring-1 ring-foreground/10"
          />
        </button>
      ),
    },
    {
      accessorKey: "title",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Title" />
      ),
      cell: ({ row }) => (
        <div>
          <div className="font-medium">{row.original.title || "Untitled"}</div>
          <div className="text-xs text-muted-foreground">{row.original.isbn}</div>
        </div>
      ),
    },
    {
      accessorKey: "author",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Author" />
      ),
      cell: ({ row }) => row.original.author || "—",
    },
    {
      accessorKey: "readingLevel",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Level" />
      ),
      cell: ({ row }) => row.original.readingLevel || "—",
    },
    {
      accessorKey: "source",
      header: "Source",
      cell: ({ row }) => (
        <code className="rounded bg-muted px-2 py-1 text-xs">
          {row.original.source || "—"}
        </code>
      ),
    },
    {
      accessorKey: "contributedByName",
      header: "Contributed By",
      cell: ({ row }) => row.original.contributedByName || "—",
    },
    {
      accessorKey: "createdAt",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Added" />
      ),
      cell: ({ row }) => formatDate(row.original.createdAt),
    },
  ];
}

function coverHost(url: string): string | null {
  try {
    return new URL(url).hostname;
  } catch {
    return null;
  }
}

export function CommunityBooksTable({
  data,
}: {
  data: CommunityBookListItem[];
}) {
  const router = useRouter();
  const [selected, setSelected] = useState<CommunityBookListItem | null>(null);
  const [uploading, setUploading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const columns = useMemo(() => buildColumns(setSelected), []);

  const handleUpload = async (file: File) => {
    if (!selected) return;
    setUploading(true);
    try {
      const form = new FormData();
      form.append("file", file);
      const res = await fetch(
        `/api/community-books/${encodeURIComponent(selected.isbn)}/cover`,
        { method: "POST", body: form }
      );
      const json = (await res.json()) as {
        coverImageUrl?: string;
        error?: string;
      };
      if (!res.ok) {
        throw new Error(json.error ?? "Failed to upload cover");
      }
      toast.success(`Cover replaced for “${selected.title || selected.isbn}”`);
      setSelected(null);
      // Re-runs the RSC page so the table (and any other consumer of the
      // list) reflects the new URL.
      router.refresh();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to upload");
    } finally {
      setUploading(false);
    }
  };

  const host = selected?.coverImageUrl ? coverHost(selected.coverImageUrl) : null;

  return (
    <>
      <DataTable
        columns={columns}
        data={data}
        searchKey="title"
        searchPlaceholder="Search by title..."
      />

      <Dialog
        open={selected !== null}
        onOpenChange={(open) => {
          if (!open && !uploading) setSelected(null);
        }}
      >
        <DialogContent>
          {selected && (
            <>
              <DialogHeader>
                <DialogTitle>
                  {selected.title || "Untitled"}{" "}
                  <span className="font-normal text-muted-foreground">
                    · {selected.isbn}
                  </span>
                </DialogTitle>
                <DialogDescription>
                  Replacing the cover overwrites the current one (teacher or
                  admin upload) everywhere — apps and portals read the same
                  URL.
                </DialogDescription>
              </DialogHeader>

              <div className="flex items-start gap-4">
                <CoverThumb
                  book={selected}
                  className="h-48 w-32 rounded-md ring-1 ring-foreground/10"
                />
                <div className="space-y-1 text-xs text-muted-foreground">
                  <p>
                    <span className="font-medium text-foreground">Source:</span>{" "}
                    {selected.source || "—"}
                  </p>
                  <p>
                    <span className="font-medium text-foreground">
                      Contributed by:
                    </span>{" "}
                    {selected.contributedByName || "—"}
                  </p>
                  <p>
                    <span className="font-medium text-foreground">
                      Cover host:
                    </span>{" "}
                    {host ?? "no cover set"}
                  </p>
                  <p className="pt-2">
                    JPEG, PNG or WebP, up to 2MB. Portrait around 600×800
                    works best.
                  </p>
                </div>
              </div>

              <input
                ref={fileInputRef}
                type="file"
                accept="image/jpeg,image/png,image/webp"
                className="hidden"
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) void handleUpload(file);
                  e.target.value = "";
                }}
              />

              <DialogFooter>
                <Button
                  variant="outline"
                  onClick={() => setSelected(null)}
                  disabled={uploading}
                >
                  Close
                </Button>
                <Button
                  onClick={() => fileInputRef.current?.click()}
                  disabled={uploading}
                >
                  <Upload className="mr-1 h-3.5 w-3.5" />
                  {uploading
                    ? "Uploading…"
                    : selected.coverImageUrl
                      ? "Replace cover"
                      : "Upload cover"}
                </Button>
              </DialogFooter>
            </>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}
