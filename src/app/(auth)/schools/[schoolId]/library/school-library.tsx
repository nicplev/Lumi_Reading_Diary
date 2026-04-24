"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { type ColumnDef } from "@tanstack/react-table";
import { Plus, Pencil, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import type { BookListItem } from "@/lib/firestore/books";

interface SchoolLibraryProps {
  schoolId: string;
  books: BookListItem[];
}

interface BookFormState {
  title: string;
  author: string;
  isbn: string;
  readingLevel: string;
  genres: string;
  pageCount: string;
  publisher: string;
  description: string;
}

const emptyForm: BookFormState = {
  title: "",
  author: "",
  isbn: "",
  readingLevel: "",
  genres: "",
  pageCount: "",
  publisher: "",
  description: "",
};

export function SchoolLibrary({ schoolId, books }: SchoolLibraryProps) {
  const router = useRouter();
  const [createOpen, setCreateOpen] = useState(false);
  const [editBook, setEditBook] = useState<BookListItem | null>(null);
  const [deleteBookId, setDeleteBookId] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState<BookFormState>(emptyForm);

  const setField = (field: keyof BookFormState, value: string) =>
    setForm((prev) => ({ ...prev, [field]: value }));

  const resetForm = () => {
    setForm(emptyForm);
  };

  const openEdit = (book: BookListItem) => {
    setForm({
      title: book.title,
      author: book.author ?? "",
      isbn: book.isbn ?? "",
      readingLevel: book.readingLevel ?? "",
      genres: book.genres.join(", "),
      pageCount: "",
      publisher: "",
      description: "",
    });
    setEditBook(book);
  };

  const handleCreate = async () => {
    if (!form.title.trim()) {
      toast.error("Title is required");
      return;
    }
    setLoading(true);
    try {
      const body: Record<string, unknown> = { title: form.title.trim() };
      if (form.author) body.author = form.author;
      if (form.isbn) body.isbn = form.isbn;
      if (form.readingLevel) body.readingLevel = form.readingLevel;
      if (form.genres)
        body.genres = form.genres.split(",").map((g) => g.trim()).filter(Boolean);
      if (form.pageCount) body.pageCount = parseInt(form.pageCount, 10);
      if (form.publisher) body.publisher = form.publisher;
      if (form.description) body.description = form.description;

      const res = await fetch(`/api/schools/${schoolId}/books`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to create book");
      }
      setCreateOpen(false);
      resetForm();
      router.refresh();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const handleEdit = async () => {
    if (!editBook || !form.title.trim()) {
      toast.error("Title is required");
      return;
    }
    setLoading(true);
    try {
      const body: Record<string, unknown> = { title: form.title.trim() };
      if (form.author) body.author = form.author;
      if (form.isbn) body.isbn = form.isbn;
      if (form.readingLevel) body.readingLevel = form.readingLevel;
      if (form.genres)
        body.genres = form.genres.split(",").map((g) => g.trim()).filter(Boolean);
      if (form.pageCount) body.pageCount = parseInt(form.pageCount, 10);
      if (form.publisher) body.publisher = form.publisher;
      if (form.description) body.description = form.description;

      const res = await fetch(
        `/api/schools/${schoolId}/books/${editBook.id}`,
        {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        }
      );
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to update book");
      }
      setEditBook(null);
      resetForm();
      router.refresh();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const handleDelete = async () => {
    if (!deleteBookId) return;
    setLoading(true);
    try {
      const res = await fetch(
        `/api/schools/${schoolId}/books/${deleteBookId}`,
        { method: "DELETE" }
      );
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to delete book");
      }
      setDeleteBookId(null);
      router.refresh();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const columns: ColumnDef<BookListItem, unknown>[] = [
    {
      accessorKey: "title",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Title" />
      ),
    },
    {
      accessorKey: "author",
      header: "Author",
      cell: ({ row }) => row.original.author ?? "\u2014",
    },
    {
      accessorKey: "readingLevel",
      header: "Reading Level",
      cell: ({ row }) => row.original.readingLevel ?? "\u2014",
    },
    {
      accessorKey: "genres",
      header: "Genres",
      cell: ({ row }) => {
        const genres = row.original.genres;
        if (!genres.length) return "\u2014";
        const text = genres.join(", ");
        return text.length > 30 ? text.slice(0, 30) + "..." : text;
      },
    },
    {
      accessorKey: "timesRead",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Times Read" />
      ),
    },
    {
      accessorKey: "isPopular",
      header: "Popular",
      cell: ({ row }) =>
        row.original.isPopular ? (
          <StatusBadge status="popular" />
        ) : (
          "\u2014"
        ),
    },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => (
        <div className="flex gap-1">
          <Button
            variant="ghost"
            size="sm"
            onClick={(e) => {
              e.stopPropagation();
              openEdit(row.original);
            }}
          >
            <Pencil className="h-4 w-4" />
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="text-destructive"
            onClick={(e) => {
              e.stopPropagation();
              setDeleteBookId(row.original.id);
            }}
          >
            <Trash2 className="h-4 w-4" />
          </Button>
        </div>
      ),
    },
  ];

  const formFields = (
    <div className="space-y-4 pt-4">
      <div className="space-y-2">
        <Label>Title *</Label>
        <Input
          value={form.title}
          onChange={(e) => setField("title", e.target.value)}
        />
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-2">
          <Label>Author</Label>
          <Input
            value={form.author}
            onChange={(e) => setField("author", e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>ISBN</Label>
          <Input
            value={form.isbn}
            onChange={(e) => setField("isbn", e.target.value)}
          />
        </div>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-2">
          <Label>Reading Level</Label>
          <Input
            value={form.readingLevel}
            onChange={(e) => setField("readingLevel", e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>Genres (comma-separated)</Label>
          <Input
            value={form.genres}
            onChange={(e) => setField("genres", e.target.value)}
            placeholder="e.g. Fiction, Adventure"
          />
        </div>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-2">
          <Label>Page Count</Label>
          <Input
            type="number"
            value={form.pageCount}
            onChange={(e) => setField("pageCount", e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>Publisher</Label>
          <Input
            value={form.publisher}
            onChange={(e) => setField("publisher", e.target.value)}
          />
        </div>
      </div>
      <div className="space-y-2">
        <Label>Description</Label>
        <Input
          value={form.description}
          onChange={(e) => setField("description", e.target.value)}
        />
      </div>
    </div>
  );

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-medium">Books</h3>
        <Dialog
          open={createOpen}
          onOpenChange={(open) => {
            setCreateOpen(open);
            if (!open) resetForm();
          }}
        >
          <DialogTrigger render={<Button />}>
            <Plus className="mr-2 h-4 w-4" />
            Add Book
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Add Book</DialogTitle>
            </DialogHeader>
            {formFields}
            <div className="flex justify-end gap-2 pt-2">
              <Button variant="outline" onClick={() => setCreateOpen(false)}>
                Cancel
              </Button>
              <Button onClick={handleCreate} disabled={loading}>
                {loading ? "Creating..." : "Create"}
              </Button>
            </div>
          </DialogContent>
        </Dialog>
      </div>

      <DataTable
        columns={columns}
        data={books}
        searchKey="title"
        searchPlaceholder="Search books..."
      />

      {/* Edit Dialog */}
      <Dialog
        open={!!editBook}
        onOpenChange={(open) => {
          if (!open) {
            setEditBook(null);
            resetForm();
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit Book</DialogTitle>
          </DialogHeader>
          {formFields}
          <div className="flex justify-end gap-2 pt-2">
            <Button
              variant="outline"
              onClick={() => {
                setEditBook(null);
                resetForm();
              }}
            >
              Cancel
            </Button>
            <Button onClick={handleEdit} disabled={loading}>
              {loading ? "Saving..." : "Save Changes"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Delete Confirm */}
      <ConfirmDialog
        open={!!deleteBookId}
        onOpenChange={(open) => {
          if (!open) setDeleteBookId(null);
        }}
        title="Delete Book"
        description="This will permanently delete this book. This action cannot be undone."
        confirmLabel="Delete"
        variant="destructive"
        onConfirm={handleDelete}
        loading={loading}
      />
    </div>
  );
}
