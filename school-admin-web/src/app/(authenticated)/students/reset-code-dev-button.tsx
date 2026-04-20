'use client';

import { useState } from 'react';
import { Button } from '@/components/lumi/button';
import { Modal } from '@/components/lumi/modal';
import { Input } from '@/components/lumi/input';
import { useToast } from '@/components/lumi/toast';

// DEV ONLY: opens a dialog to paste a parent link code and calls
// /api/link-codes/reset to flip it back to `active` and unlink any parent.
// Only rendered when the server resolved the caller to have dev access
// (see page.tsx → hasDevAccess via Firestore /devAccessEmails).
export function ResetCodeDevButton({ visible }: { visible: boolean }) {
  const [open, setOpen] = useState(false);
  const [code, setCode] = useState('');
  const [loading, setLoading] = useState(false);
  const { toast } = useToast();

  if (!visible) return null;

  const handleReset = async () => {
    const normalized = code.toUpperCase().trim();
    if (!/^[A-Z0-9]{8}$/.test(normalized)) {
      toast('Code must be 8 uppercase letters or digits', 'error');
      return;
    }
    setLoading(true);
    try {
      const res = await fetch('/api/link-codes/reset', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code: normalized }),
      });
      const json = await res.json();
      if (!res.ok) throw new Error(json.error || 'Reset failed');

      const unlinked = json.unlinkedParent?.email || json.unlinkedParent?.uid;
      toast(
        unlinked
          ? `Reset ${normalized} — unlinked ${unlinked}`
          : `Reset ${normalized} (no parent was linked)`,
        'success',
      );
      setCode('');
      setOpen(false);
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Reset failed', 'error');
    } finally {
      setLoading(false);
    }
  };

  return (
    <>
      <Button
        variant="outline"
        size="sm"
        onClick={() => setOpen(true)}
        className="border-amber-400 text-amber-700 hover:bg-amber-50"
        title="DEV ONLY — reset a parent link code"
      >
        🧪 Reset Test Code
      </Button>
      <Modal
        open={open}
        onClose={() => { if (!loading) { setOpen(false); setCode(''); } }}
        title="Reset Parent Link Code"
        description="Flips the code back to active, unlinks any linked parent, and deletes their parent doc + email index. The Firebase Auth user is left intact — the same email can be reused on the next test run (registration will fall through the email-already-in-use → sign-in path)."
        size="sm"
        footer={
          <>
            <Button variant="ghost" onClick={() => setOpen(false)} disabled={loading}>
              Cancel
            </Button>
            <Button variant="danger" onClick={handleReset} loading={loading}>
              Reset
            </Button>
          </>
        }
      >
        <Input
          label="Link code"
          placeholder="e.g. ABC12345"
          value={code}
          onChange={(e) => setCode(e.target.value.toUpperCase())}
          maxLength={8}
          autoFocus
        />
      </Modal>
    </>
  );
}
