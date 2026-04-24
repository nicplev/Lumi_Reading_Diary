"use client";

import { useState, useRef } from "react";
import { toast } from "sonner";
import Papa from "papaparse";
import { Upload } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import type { SchoolListItem } from "@/lib/firestore/schools";

interface BulkImportProps {
  schools: SchoolListItem[];
}

interface ParsedRow {
  firstName: string;
  lastName: string;
  studentId?: string;
  className: string;
  currentReadingLevel?: string;
}

// Map various CSV header names to our expected fields
const HEADER_MAP: Record<string, keyof ParsedRow> = {
  firstname: "firstName",
  first_name: "firstName",
  "first name": "firstName",
  lastname: "lastName",
  last_name: "lastName",
  "last name": "lastName",
  studentid: "studentId",
  student_id: "studentId",
  "student id": "studentId",
  classname: "className",
  class_name: "className",
  "class name": "className",
  class: "className",
  readinglevel: "currentReadingLevel",
  reading_level: "currentReadingLevel",
  "reading level": "currentReadingLevel",
  level: "currentReadingLevel",
};

function normalizeHeaders(
  row: Record<string, string>
): ParsedRow {
  const result: Record<string, string> = {};
  for (const [key, value] of Object.entries(row)) {
    const normalizedKey = key.toLowerCase().trim();
    const mappedKey = HEADER_MAP[normalizedKey];
    if (mappedKey) {
      result[mappedKey] = value?.trim() ?? "";
    }
  }
  return result as unknown as ParsedRow;
}

export function BulkImport({ schools }: BulkImportProps) {
  const [schoolId, setSchoolId] = useState("");
  const [rows, setRows] = useState<ParsedRow[]>([]);
  const [fileName, setFileName] = useState("");
  const [importing, setImporting] = useState(false);
  const [result, setResult] = useState<{
    created: number;
    errors: { row: number; message: string }[];
  } | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setFileName(file.name);
    setResult(null);

    Papa.parse(file, {
      header: true,
      skipEmptyLines: true,
      complete: (results) => {
        const parsed = (results.data as Record<string, string>[]).map(
          normalizeHeaders
        );
        // Filter out rows with no firstName
        const valid = parsed.filter((r) => r.firstName);
        setRows(valid);
        if (valid.length === 0) {
          toast.error(
            "No valid rows found. Ensure CSV has headers: firstName, lastName, className"
          );
        } else {
          toast.success(`Parsed ${valid.length} rows from ${file.name}`);
        }
      },
      error: () => {
        toast.error("Failed to parse CSV file");
      },
    });
  };

  const handleImport = async () => {
    if (!schoolId || rows.length === 0) return;
    setImporting(true);
    setResult(null);

    try {
      const res = await fetch("/api/bulk/students", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ schoolId, students: rows }),
      });
      if (!res.ok) throw new Error("Import failed");
      const data = await res.json();
      setResult(data);
      toast.success(`Imported ${data.created} students`);
      if (data.errors.length > 0) {
        toast.warning(`${data.errors.length} rows had errors`);
      }
    } catch {
      toast.error("Failed to import students");
    } finally {
      setImporting(false);
    }
  };

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Import Students from CSV</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label>School *</Label>
            <Select
              value={schoolId}
              onValueChange={(v) => v && setSchoolId(v)}
            >
              <SelectTrigger>
                <SelectValue placeholder="Select a school" />
              </SelectTrigger>
              <SelectContent>
                {schools.map((s) => (
                  <SelectItem key={s.id} value={s.id}>
                    {s.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label>CSV File *</Label>
            <p className="text-xs text-muted-foreground">
              Required columns: firstName, lastName, className. Optional:
              studentId, readingLevel
            </p>
            <input
              ref={fileRef}
              type="file"
              accept=".csv"
              onChange={handleFileChange}
              className="hidden"
            />
            <Button
              variant="outline"
              onClick={() => fileRef.current?.click()}
            >
              <Upload className="mr-2 h-4 w-4" />
              {fileName || "Choose CSV file"}
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Preview */}
      {rows.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle>Preview ({rows.length} rows)</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="max-h-80 overflow-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-left text-muted-foreground">
                    <th className="pb-2 pr-3">#</th>
                    <th className="pb-2 pr-3">First Name</th>
                    <th className="pb-2 pr-3">Last Name</th>
                    <th className="pb-2 pr-3">Student ID</th>
                    <th className="pb-2 pr-3">Class</th>
                    <th className="pb-2">Level</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.slice(0, 50).map((row, i) => {
                    const hasError = result?.errors.find(
                      (e) => e.row === i + 1
                    );
                    return (
                      <tr
                        key={i}
                        className={`border-b ${hasError ? "bg-red-50 dark:bg-red-950" : ""}`}
                      >
                        <td className="py-1.5 pr-3 text-muted-foreground">
                          {i + 1}
                        </td>
                        <td className="py-1.5 pr-3">{row.firstName}</td>
                        <td className="py-1.5 pr-3">{row.lastName}</td>
                        <td className="py-1.5 pr-3">
                          {row.studentId || "\u2014"}
                        </td>
                        <td className="py-1.5 pr-3">{row.className}</td>
                        <td className="py-1.5">
                          {row.currentReadingLevel || "\u2014"}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
              {rows.length > 50 && (
                <p className="mt-2 text-sm text-muted-foreground">
                  Showing first 50 of {rows.length} rows.
                </p>
              )}
            </div>

            <div className="mt-4">
              <Button
                onClick={handleImport}
                disabled={!schoolId || importing}
              >
                {importing
                  ? "Importing..."
                  : `Import ${rows.length} Students`}
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Results */}
      {result && (
        <Card>
          <CardHeader>
            <CardTitle>Import Results</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <p className="text-sm">
              <span className="font-bold text-green-600">
                {result.created}
              </span>{" "}
              students created successfully.
            </p>
            {result.errors.length > 0 && (
              <div>
                <p className="text-sm font-medium text-red-600">
                  {result.errors.length} errors:
                </p>
                <ul className="mt-1 space-y-1">
                  {result.errors.map((err, i) => (
                    <li key={i} className="text-sm text-red-600">
                      Row {err.row}: {err.message}
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  );
}
