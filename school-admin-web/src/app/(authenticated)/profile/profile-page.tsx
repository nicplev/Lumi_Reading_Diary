'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { useAuth } from '@/lib/auth/auth-context';
import { useSchool } from '@/lib/hooks/use-school';
import { useClasses } from '@/lib/hooks/use-classes';
import { useToast } from '@/components/lumi/toast';
import { Card } from '@/components/lumi/card';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { Input } from '@/components/lumi/input';
import { Avatar } from '@/components/lumi/avatar';
import { Badge } from '@/components/lumi/badge';
import { Icon } from '@/components/lumi/icon';
import type { SchoolUser } from '@/lib/types';

type SerializedProfile = Omit<SchoolUser, 'createdAt' | 'lastLoginAt'> & {
  createdAt: string;
  lastLoginAt?: string;
};

export default function ProfilePage() {
  const { user, logout, refreshUser } = useAuth();
  const { data: school } = useSchool();
  const { data: classes } = useClasses();
  const { toast } = useToast();

  const [profile, setProfile] = useState<SerializedProfile | null>(null);
  const [loadingProfile, setLoadingProfile] = useState(true);

  // Edit form state
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');
  const [saving, setSaving] = useState(false);
  const [dirty, setDirty] = useState(false);

  // Password reset
  const [resettingPassword, setResettingPassword] = useState(false);

  useEffect(() => {
    async function fetchProfile() {
      try {
        const res = await fetch('/api/profile');
        if (res.ok) {
          const data: SerializedProfile = await res.json();
          setProfile(data);
          setFullName(data.fullName || '');
          setPhone(data.phone || '');
        }
      } catch {
        toast('Failed to load profile', 'error');
      } finally {
        setLoadingProfile(false);
      }
    }
    fetchProfile();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!profile) return;
    const nameChanged = fullName.trim() !== (profile.fullName || '');
    const phoneChanged = phone.trim() !== (profile.phone || '');
    setDirty(nameChanged || phoneChanged);
  }, [fullName, phone, profile]);

  const displayName = user?.fullName || user?.email || profile?.fullName || profile?.email || 'User';
  const userClasses = classes?.filter(c =>
    profile?.classIds?.includes(c.id)
  );
  const roleLabel = (user?.role || profile?.role) === 'schoolAdmin' ? 'School Admin' : 'Teacher';
  const roleBadgeVariant = (user?.role || profile?.role) === 'schoolAdmin' ? 'info' as const : 'success' as const;
  const userEmail = user?.email || profile?.email || '';

  async function handleSave() {
    setSaving(true);
    try {
      const res = await fetch('/api/profile', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ fullName: fullName.trim(), phone: phone.trim() }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to save');
      }
      // Update local profile state
      setProfile(prev => prev ? { ...prev, fullName: fullName.trim(), phone: phone.trim() } : prev);
      setDirty(false);
      // Refresh auth context so sidebar updates
      await refreshUser();
      toast('Profile updated', 'success');
    } catch (err) {
      toast(err instanceof Error ? err.message : 'Failed to update profile', 'error');
    } finally {
      setSaving(false);
    }
  }

  async function handlePasswordReset() {
    setResettingPassword(true);
    try {
      const res = await fetch('/api/profile/reset-password', { method: 'POST' });
      if (!res.ok) {
        throw new Error('Failed to send password reset');
      }
      toast('Password reset email sent to ' + userEmail, 'success');
    } catch {
      toast('Failed to send password reset email', 'error');
    } finally {
      setResettingPassword(false);
    }
  }

  function formatDate(dateStr?: string) {
    if (!dateStr) return '—';
    return new Date(dateStr).toLocaleDateString('en-AU', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  return (
    <div className="max-w-2xl space-y-6">
      <PageHeader title="Profile" />

      {/* Profile Header */}
      <Card>
        <div className="flex items-center gap-4">
          <Avatar name={displayName} size="lg" />
          <div>
            <h2 className="text-[22px] font-bold text-charcoal">
              {displayName}
            </h2>
            <p className="text-sm text-text-secondary">{userEmail}</p>
            <Badge variant={roleBadgeVariant} className="mt-1">
              {roleLabel}
            </Badge>
          </div>
        </div>
      </Card>

      {/* Personal Information — Editable */}
      <Card>
        <h3 className="text-[17px] font-bold text-charcoal mb-4 flex items-center gap-2">
          <Icon name="edit" size={18} />
          Personal Information
        </h3>
        <div className="space-y-4">
          <Input
            id="fullName"
            label="Full Name"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            placeholder="Enter your full name"
          />
          <Input
            id="phone"
            label="Phone Number"
            type="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder="Enter your phone number"
          />
          <div className="flex gap-3">
            <Button
              onClick={handleSave}
              loading={saving}
              disabled={!dirty || saving}
            >
              Save Changes
            </Button>
            {dirty && (
              <Button
                variant="ghost"
                onClick={() => {
                  setFullName(profile?.fullName || '');
                  setPhone(profile?.phone || '');
                }}
              >
                Cancel
              </Button>
            )}
          </div>
        </div>
      </Card>

      {/* Account Details */}
      <Card>
        <h3 className="text-[17px] font-bold text-charcoal mb-4 flex items-center gap-2">
          <Icon name="info" size={18} />
          Account Details
        </h3>
        <div className="space-y-3">
          <div className="flex justify-between py-2 border-b border-divider">
            <span className="text-sm text-text-secondary">Email</span>
            <span className="text-sm font-semibold text-charcoal">{userEmail}</span>
          </div>
          <div className="flex justify-between py-2 border-b border-divider">
            <span className="text-sm text-text-secondary">Role</span>
            <Badge variant={roleBadgeVariant}>
              {roleLabel}
            </Badge>
          </div>
          <div className="flex justify-between py-2 border-b border-divider">
            <span className="text-sm text-text-secondary">School</span>
            <span className="text-sm font-semibold text-charcoal">
              {school?.displayName || school?.name || '—'}
            </span>
          </div>
          {!loadingProfile && (
            <>
              <div className="flex justify-between py-2 border-b border-divider">
                <span className="text-sm text-text-secondary">Last Login</span>
                <span className="text-sm text-charcoal">{formatDate(profile?.lastLoginAt)}</span>
              </div>
              <div className="flex justify-between py-2">
                <span className="text-sm text-text-secondary">Account Created</span>
                <span className="text-sm text-charcoal">{formatDate(profile?.createdAt)}</span>
              </div>
            </>
          )}
        </div>
      </Card>

      {/* Assigned Classes — Teachers only */}
      {(user?.role || profile?.role) === 'teacher' && userClasses && userClasses.length > 0 && (
        <Card>
          <h3 className="text-[17px] font-bold text-charcoal mb-4 flex items-center gap-2">
            <Icon name="school" size={18} />
            Assigned Classes
          </h3>
          <div className="space-y-2">
            {userClasses.map((cls) => (
              <Link
                key={cls.id}
                href={`/classes/${cls.id}`}
                className="flex items-center justify-between p-3 rounded-[var(--radius-md)] hover:bg-background transition-colors"
              >
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-[var(--radius-md)] bg-brand-primary/10 flex items-center justify-center">
                    <Icon name="school" size={16} className="text-brand-primary" />
                  </div>
                  <div>
                    <p className="text-sm font-semibold text-charcoal">{cls.name}</p>
                    {cls.yearLevel && (
                      <p className="text-xs text-text-secondary">Year {cls.yearLevel}</p>
                    )}
                  </div>
                </div>
                <Icon name="chevron_right" size={18} className="text-text-secondary" />
              </Link>
            ))}
          </div>
        </Card>
      )}

      {/* Security */}
      <Card>
        <h3 className="text-[17px] font-bold text-charcoal mb-4 flex items-center gap-2">
          <Icon name="lock" size={18} />
          Security
        </h3>
        <p className="text-sm text-text-secondary mb-4">
          Request a password reset link sent to your email address.
        </p>
        <div className="flex gap-3">
          <Button
            variant="outline"
            onClick={handlePasswordReset}
            loading={resettingPassword}
            disabled={resettingPassword}
          >
            Reset Password
          </Button>
          <Button variant="outline" onClick={logout}>
            Sign Out
          </Button>
        </div>
      </Card>
    </div>
  );
}
