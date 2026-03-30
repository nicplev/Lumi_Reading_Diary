'use client';

import { useState } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Input } from '@/components/lumi/input';
import { Select } from '@/components/lumi/select';
import { Button } from '@/components/lumi/button';
import { useToast } from '@/components/lumi/toast';
import { useCreateUser } from '@/lib/hooks/use-users';

interface CreateUserModalProps {
  open: boolean;
  onClose: () => void;
}

export function CreateUserModal({ open, onClose }: CreateUserModalProps) {
  const { toast } = useToast();
  const createUser = useCreateUser();

  const [email, setEmail] = useState('');
  const [fullName, setFullName] = useState('');
  const [role, setRole] = useState<'teacher' | 'schoolAdmin'>('teacher');
  const [password, setPassword] = useState('');

  const reset = () => {
    setEmail('');
    setFullName('');
    setRole('teacher');
    setPassword('');
  };

  const handleClose = () => {
    reset();
    onClose();
  };

  const handleCreate = async () => {
    try {
      await createUser.mutateAsync({ email, fullName, role, password });
      toast('User created', 'success');
      handleClose();
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to create user', 'error');
    }
  };

  const isValid = email.includes('@') && fullName.trim().length > 0 && password.length >= 6;

  return (
    <Modal
      open={open}
      onClose={handleClose}
      title="Add Staff Member"
      description="Create a new teacher or admin account."
      size="md"
      footer={
        <>
          <Button variant="outline" onClick={handleClose} disabled={createUser.isPending}>
            Cancel
          </Button>
          <Button onClick={handleCreate} loading={createUser.isPending} disabled={!isValid}>
            Create User
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <Input
          label="Full Name"
          value={fullName}
          onChange={(e) => setFullName(e.target.value)}
          placeholder="e.g. Jane Smith"
          required
        />

        <Input
          label="Email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="teacher@school.com"
          required
        />

        <Select
          label="Role"
          options={[
            { value: 'teacher', label: 'Teacher' },
            { value: 'schoolAdmin', label: 'School Admin' },
          ]}
          value={role}
          onChange={(v) => setRole(v as 'teacher' | 'schoolAdmin')}
        />

        <Input
          label="Temporary Password"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="Min 6 characters"
          required
          error={password.length > 0 && password.length < 6 ? 'Password must be at least 6 characters' : undefined}
        />

        <p className="text-xs text-text-secondary">
          The user will be able to sign in immediately with this password.
          You can generate a password reset link later if needed.
        </p>
      </div>
    </Modal>
  );
}
