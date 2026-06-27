'use client';

import { Card } from './card';
import { Badge } from './badge';
import { ReadingLevelPill } from './reading-level-pill';
import { Icon } from './icon';

interface BookCardProps {
  book: {
    title: string;
    author?: string;
    coverImageUrl?: string;
    isbn?: string;
    readingLevel?: string;
  };
  onClick?: () => void;
  badge?: React.ReactNode;
  compact?: boolean;
}

export function BookCard({ book, onClick, badge, compact }: BookCardProps) {
  if (compact) {
    return (
      <div
        onClick={onClick}
        className={`flex items-center gap-3 p-3 rounded-[var(--radius-md)] border border-rule bg-paper transition-colors ${
          onClick ? 'cursor-pointer hover:bg-cream/50' : ''
        }`}
      >
        <div className="w-10 h-14 flex-shrink-0 rounded bg-cream flex items-center justify-center overflow-hidden">
          {book.coverImageUrl ? (
            <img src={book.coverImageUrl} alt={book.title} className="w-full h-full object-cover" />
          ) : (
            <span className="text-muted/40"><Icon name="auto_stories" size={20} /></span>
          )}
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold text-ink truncate">{book.title}</p>
          {book.author && <p className="text-xs text-muted truncate">{book.author}</p>}
        </div>
        <div className="flex items-center gap-2 flex-shrink-0">
          {book.readingLevel && <ReadingLevelPill level={book.readingLevel} size="sm" />}
          {badge}
        </div>
      </div>
    );
  }

  return (
    <Card hover={!!onClick} padding="none" onClick={onClick}>
      <div className="aspect-[3/4] bg-cream rounded-t-[var(--radius-lg)] flex items-center justify-center overflow-hidden">
        {book.coverImageUrl ? (
          <img src={book.coverImageUrl} alt={book.title} className="w-full h-full object-cover" />
        ) : (
          <span className="text-muted/30"><Icon name="auto_stories" size={48} /></span>
        )}
      </div>
      <div className="p-3">
        <p className="text-sm font-bold text-ink truncate">{book.title}</p>
        {book.author && <p className="text-xs text-muted truncate mt-0.5">{book.author}</p>}
        <div className="flex items-center gap-1.5 mt-2 flex-wrap">
          {book.readingLevel && <ReadingLevelPill level={book.readingLevel} size="sm" />}
          {book.isbn && (
            <Badge variant="default">
              <span className="text-[10px]">{book.isbn}</span>
            </Badge>
          )}
          {badge}
        </div>
      </div>
    </Card>
  );
}
