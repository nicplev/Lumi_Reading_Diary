'use client';

import { useEffect, useRef, useState } from 'react';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { useToast } from '@/components/lumi/toast';
import {
  useLogComments,
  usePostComment,
  useMarkCommentsRead,
} from '@/lib/hooks/use-reading-logs';

function formatTime(iso: string | null): string {
  if (!iso) return '';
  return new Date(iso).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

export function CommentThread({ logId, hasUnread }: { logId: string; hasUnread: boolean }) {
  const { toast } = useToast();
  const { data: comments, isLoading } = useLogComments(logId);
  const postComment = usePostComment(logId);
  const markRead = useMarkCommentsRead(logId);
  const [draft, setDraft] = useState('');
  const markedRef = useRef(false);

  // This component mounts fresh each time a thread is expanded, so clearing the
  // staff unread badge once on mount (when there are unseen parent replies) is
  // correct. markCommentsRead is a no-op write otherwise.
  useEffect(() => {
    if (hasUnread && !markedRef.current) {
      markedRef.current = true;
      markRead.mutate();
    }
  }, [hasUnread, markRead]);

  const handleSend = async () => {
    const body = draft.trim();
    if (!body) return;
    try {
      await postComment.mutateAsync({ body });
      setDraft('');
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Failed to post comment', 'error');
    }
  };

  return (
    <div className="mt-3 border-t border-rule pt-3 space-y-3">
      {isLoading ? (
        <p className="text-xs text-muted">Loading comments…</p>
      ) : (comments ?? []).length === 0 ? (
        <p className="text-xs text-muted">
          No comments yet — start the conversation with this family.
        </p>
      ) : (
        <ul className="space-y-2.5">
          {(comments ?? []).map((c) => (
            <li key={c.id} className="flex flex-col gap-0.5">
              <div className="flex items-center gap-2">
                <span className="text-sm font-semibold text-ink">{c.authorName}</span>
                <Badge variant={c.authorRole === 'teacher' ? 'info' : 'default'}>
                  {c.authorRole === 'teacher' ? 'Staff' : 'Parent'}
                </Badge>
                <span className="text-xs text-muted">{formatTime(c.createdAt)}</span>
              </div>
              <p className="text-sm text-ink whitespace-pre-wrap">{c.body}</p>
            </li>
          ))}
        </ul>
      )}

      <div className="flex items-end gap-2">
        <textarea
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          rows={2}
          maxLength={2000}
          placeholder="Reply to the family…"
          className="flex-1 px-3 py-2 rounded-[var(--radius-md)] border border-rule bg-paper text-ink placeholder:text-muted/50 focus:outline-none focus:ring-2 focus:ring-section/30 focus:border-section transition-colors text-sm resize-y"
        />
        <Button size="sm" onClick={handleSend} loading={postComment.isPending} disabled={!draft.trim()}>
          Send
        </Button>
      </div>
    </div>
  );
}
