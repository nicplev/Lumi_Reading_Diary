"use client";

import { useEffect, useState } from "react";
import { Search } from "lucide-react";
import { Input } from "@/components/ui/input";

interface SearchInputProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  debounceMs?: number;
}

export function SearchInput({
  value,
  onChange,
  placeholder = "Search...",
  debounceMs = 300,
}: SearchInputProps) {
  const [internal, setInternal] = useState(value);
  const [lastExternalValue, setLastExternalValue] = useState(value);

  // Adjust state during render rather than syncing via useEffect — the
  // react-hooks rule flags prop→state sync effects as a cascading-render risk,
  // and React batches paired setState calls from a single render correctly.
  if (value !== lastExternalValue) {
    setLastExternalValue(value);
    setInternal(value);
  }

  useEffect(() => {
    const timer = setTimeout(() => {
      if (internal !== value) {
        onChange(internal);
      }
    }, debounceMs);
    return () => clearTimeout(timer);
  }, [internal, debounceMs, onChange, value]);

  return (
    <div className="relative">
      <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
      <Input
        placeholder={placeholder}
        value={internal}
        onChange={(e) => setInternal(e.target.value)}
        className="pl-8"
      />
    </div>
  );
}
