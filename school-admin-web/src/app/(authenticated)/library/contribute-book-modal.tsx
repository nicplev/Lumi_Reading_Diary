'use client';

import { useEffect, useRef, useState } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Input } from '@/components/lumi/input';
import { useToast } from '@/components/lumi/toast';
import { useContributeCommunityBook } from '@/lib/hooks/use-community-books';

// Resize to fit within 600x800 and re-encode as JPEG q85, matching the app's
// cover processing — keeps the upload small and consistent.
async function resizeToDataUrl(file: File, maxW = 600, maxH = 800, quality = 0.85): Promise<string> {
  const dataUrl = await new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = () => reject(new Error('read failed'));
    reader.readAsDataURL(file);
  });
  const img = await new Promise<HTMLImageElement>((resolve, reject) => {
    const i = new Image();
    i.onload = () => resolve(i);
    i.onerror = () => reject(new Error('decode failed'));
    i.src = dataUrl;
  });
  let { width, height } = img;
  if (width > maxW || height > maxH) {
    const scale = Math.min(maxW / width, maxH / height);
    width = Math.round(width * scale);
    height = Math.round(height * scale);
  }
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  if (!ctx) return dataUrl;
  ctx.drawImage(img, 0, 0, width, height);
  return canvas.toDataURL('image/jpeg', quality);
}

interface ContributeBookModalProps {
  open: boolean;
  onClose: () => void;
}

export function ContributeBookModal({ open, onClose }: ContributeBookModalProps) {
  const { toast } = useToast();
  const contribute = useContributeCommunityBook();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [isbn, setIsbn] = useState('');
  const [title, setTitle] = useState('');
  const [author, setAuthor] = useState('');
  const [readingLevel, setReadingLevel] = useState('');
  const [description, setDescription] = useState('');
  const [coverDataUrl, setCoverDataUrl] = useState('');
  const [lookupNote, setLookupNote] = useState<string | null>(null);
  const [lookingUp, setLookingUp] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setIsbn('');
      setTitle('');
      setAuthor('');
      setReadingLevel('');
      setDescription('');
      setCoverDataUrl('');
      setLookupNote(null);
      setError(null);
    }
  }, [open]);

  const handleLookup = async () => {
    const value = isbn.trim();
    if (!value) return setError('Enter an ISBN to look up.');
    setError(null);
    setLookingUp(true);
    setLookupNote(null);
    try {
      const res = await fetch('/api/books/lookup', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isbn: value }),
      });
      const data = await res.json();
      if (data.book) {
        setTitle((t) => t || data.book.title || '');
        setAuthor((a) => a || data.book.author || '');
        if (data.book.readingLevel) setReadingLevel((l) => l || data.book.readingLevel);
        setLookupNote('Prefilled from online lookup — edit as needed, and add a cover photo.');
      } else {
        setLookupNote('No online match — enter the details manually.');
      }
    } catch {
      setLookupNote('Lookup failed — enter the details manually.');
    } finally {
      setLookingUp(false);
    }
  };

  const onFile = async (file: File) => {
    if (!file.type.startsWith('image/')) {
      toast('Please choose an image file', 'error');
      return;
    }
    try {
      setCoverDataUrl(await resizeToDataUrl(file));
    } catch {
      toast('Could not read that image', 'error');
    }
  };

  const handleSubmit = async () => {
    setError(null);
    if (!isbn.trim()) return setError('Enter an ISBN.');
    if (!title.trim()) return setError('Title is required.');
    try {
      const r = await contribute.mutateAsync({
        isbn: isbn.trim(),
        title: title.trim(),
        author: author.trim() || undefined,
        readingLevel: readingLevel.trim() || undefined,
        description: description.trim() || undefined,
        coverDataUrl: coverDataUrl || undefined,
      });
      toast(r.created ? 'Added to the community catalog' : 'Updated the community book', 'success');
      onClose();
    } catch (e) {
      const m = e instanceof Error ? e.message : 'Failed to contribute book';
      setError(m);
      toast(m, 'error');
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Contribute a Book"
      description="Add a book (and cover) to the shared community catalog used across schools."
      size="lg"
      footer={
        <>
          <Button variant="outline" onClick={onClose} disabled={contribute.isPending}>
            Cancel
          </Button>
          <Button onClick={handleSubmit} loading={contribute.isPending}>
            Contribute
          </Button>
        </>
      }
    >
      <form className="space-y-4" onSubmit={(e) => e.preventDefault()}>
        <div className="flex items-end gap-2">
          <div className="flex-1">
            <Input
              label="ISBN"
              placeholder="ISBN-10 or ISBN-13"
              value={isbn}
              onChange={(e) => setIsbn(e.target.value)}
            />
          </div>
          <Button variant="outline" onClick={handleLookup} loading={lookingUp} disabled={!isbn.trim()}>
            Look up
          </Button>
        </div>
        {lookupNote && <p className="text-xs text-text-secondary -mt-2">{lookupNote}</p>}

        <Input label="Title" value={title} onChange={(e) => setTitle(e.target.value)} />
        <Input label="Author" value={author} onChange={(e) => setAuthor(e.target.value)} />
        <Input
          label="Reading level (optional)"
          placeholder="e.g. PM 18, Level F"
          value={readingLevel}
          onChange={(e) => setReadingLevel(e.target.value)}
        />

        <div>
          <label className="block text-sm font-semibold text-charcoal mb-1.5">Description (optional)</label>
          <textarea
            value={description}
            rows={3}
            maxLength={4000}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="A short synopsis…"
            className="w-full px-4 py-3 rounded-[var(--radius-md)] border border-divider bg-surface text-charcoal placeholder:text-text-secondary/50 focus:outline-none focus:ring-2 focus:ring-rose-pink/30 focus:border-rose-pink transition-colors text-[15px] resize-y"
          />
        </div>

        <div>
          <label className="block text-sm font-semibold text-charcoal mb-1.5">Cover photo (optional)</label>
          <div
            onDragOver={(e) => e.preventDefault()}
            onDrop={(e) => {
              e.preventDefault();
              const f = e.dataTransfer.files?.[0];
              if (f) onFile(f);
            }}
            onClick={() => fileInputRef.current?.click()}
            className="border-2 border-dashed border-divider rounded-[var(--radius-md)] p-4 text-center cursor-pointer hover:border-rose-pink/50 transition-colors"
          >
            {coverDataUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={coverDataUrl} alt="Cover preview" className="mx-auto max-h-44 rounded-[var(--radius-sm)]" />
            ) : (
              <p className="text-sm text-text-secondary">Drag a cover image here, or click to choose</p>
            )}
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) onFile(f);
              }}
            />
          </div>
          {coverDataUrl && (
            <button
              type="button"
              onClick={() => setCoverDataUrl('')}
              className="text-xs text-error mt-1.5 hover:underline"
            >
              Remove cover
            </button>
          )}
        </div>

        {error && <p className="text-sm text-error">{error}</p>}
      </form>
    </Modal>
  );
}
