'use client';

import { useState } from 'react';
import { signInWithEmailAndPassword, sendPasswordResetEmail } from 'firebase/auth';
import { auth } from '@/lib/firebase/client';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense } from 'react';
import { Icon } from '@/components/lumi/icon';
import { useAuth } from '@/lib/auth/auth-context';

function LoginForm() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [forgotMode, setForgotMode] = useState(false);
  const [resetMessage, setResetMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
  const [resetLoading, setResetLoading] = useState(false);
  const router = useRouter();
  const searchParams = useSearchParams();
  const { setSessionData } = useAuth();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const credential = await signInWithEmailAndPassword(auth, email, password);
      const idToken = await credential.user.getIdToken();

      const res = await fetch('/api/auth/session', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ idToken }),
      });

      const sessionData = await res.json();
      if (!res.ok) {
        throw new Error(sessionData.error || 'Login failed');
      }

      // Inject session data directly into AuthContext to avoid race condition
      setSessionData(sessionData);

      const from = searchParams.get('from') || '/dashboard';
      router.push(from);
      router.refresh();
    } catch (err) {
      if (err instanceof Error) {
        if (err.message.includes('auth/invalid-credential') || err.message.includes('auth/wrong-password') || err.message.includes('auth/user-not-found')) {
          setError('Invalid email or password');
        } else {
          setError(err.message);
        }
      } else {
        setError('An unexpected error occurred');
      }
    } finally {
      setLoading(false);
    }
  };

  const handleResetPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email) {
      setResetMessage({ type: 'error', text: 'Please enter your email address above.' });
      return;
    }
    setResetLoading(true);
    setResetMessage(null);
    try {
      await sendPasswordResetEmail(auth, email);
      setResetMessage({ type: 'success', text: 'Password reset email sent. Check your inbox.' });
    } catch {
      // Show generic success to prevent user enumeration
      setResetMessage({ type: 'success', text: 'If an account exists with this email, a reset link has been sent.' });
    } finally {
      setResetLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-background px-4">
      <div className="w-full max-w-sm">
        {/* Logo / Brand */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-[var(--radius-xl)] bg-rose-pink/10 mb-4">
            <span className="text-rose-pink"><Icon name="library_books" size={32} /></span>
          </div>
          <h1 className="text-[28px] font-bold text-charcoal">Lumi School</h1>
          <p className="text-text-secondary text-sm mt-1">
            {forgotMode ? 'Reset your password' : 'Sign in to your school portal'}
          </p>
        </div>

        {forgotMode ? (
          /* Forgot Password Form */
          <form onSubmit={handleResetPassword} className="space-y-4">
            {resetMessage && (
              <div className={`text-sm rounded-[var(--radius-md)] px-4 py-3 ${
                resetMessage.type === 'success'
                  ? 'bg-success/10 text-success'
                  : 'bg-error/10 text-error'
              }`}>
                {resetMessage.text}
              </div>
            )}

            <div>
              <label htmlFor="reset-email" className="block text-sm font-semibold text-charcoal mb-1.5">
                Email
              </label>
              <input
                id="reset-email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="teacher@school.com"
                required
                className="w-full px-4 py-3 rounded-[var(--radius-md)] border border-divider bg-surface text-charcoal placeholder:text-text-secondary/50 focus:outline-none focus:ring-2 focus:ring-rose-pink/30 focus:border-rose-pink transition-colors text-[15px]"
              />
            </div>

            <button
              type="submit"
              disabled={resetLoading}
              className="w-full py-3 px-4 rounded-[var(--radius-md)] bg-rose-pink text-white font-bold text-[15px] hover:bg-rose-pink-dark transition-colors disabled:opacity-50 disabled:cursor-not-allowed shadow-card flex items-center justify-center gap-2"
            >
              {resetLoading && (
                <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24" fill="none">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                </svg>
              )}
              {resetLoading ? 'Sending...' : 'Send Reset Email'}
            </button>

            <button
              type="button"
              onClick={() => { setForgotMode(false); setResetMessage(null); setError(''); }}
              className="w-full text-sm text-rose-pink hover:text-rose-pink-dark font-semibold transition-colors py-2"
            >
              Back to sign in
            </button>
          </form>
        ) : (
          /* Login Form */
          <>
            <form onSubmit={handleSubmit} className="space-y-4">
              {error && (
                <div className="bg-error/10 text-error text-sm rounded-[var(--radius-md)] px-4 py-3">
                  {error}
                </div>
              )}

              <div>
                <label htmlFor="email" className="block text-sm font-semibold text-charcoal mb-1.5">
                  Email
                </label>
                <input
                  id="email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="teacher@school.com"
                  required
                  className="w-full px-4 py-3 rounded-[var(--radius-md)] border border-divider bg-surface text-charcoal placeholder:text-text-secondary/50 focus:outline-none focus:ring-2 focus:ring-rose-pink/30 focus:border-rose-pink transition-colors text-[15px]"
                />
              </div>

              <div>
                <div className="flex items-center justify-between mb-1.5">
                  <label htmlFor="password" className="block text-sm font-semibold text-charcoal">
                    Password
                  </label>
                  <button
                    type="button"
                    onClick={() => { setForgotMode(true); setError(''); setResetMessage(null); }}
                    className="text-xs text-rose-pink hover:text-rose-pink-dark font-semibold transition-colors"
                  >
                    Forgot password?
                  </button>
                </div>
                <div className="relative">
                  <input
                    id="password"
                    type={showPassword ? 'text' : 'password'}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="••••••••"
                    required
                    className="w-full px-4 py-3 pr-12 rounded-[var(--radius-md)] border border-divider bg-surface text-charcoal placeholder:text-text-secondary/50 focus:outline-none focus:ring-2 focus:ring-rose-pink/30 focus:border-rose-pink transition-colors text-[15px]"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    tabIndex={-1}
                    aria-label={showPassword ? 'Hide password' : 'Show password'}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-text-secondary hover:text-charcoal transition-colors"
                  >
                    <Icon name={showPassword ? 'visibility_off' : 'visibility'} size={20} />
                  </button>
                </div>
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full py-3 px-4 rounded-[var(--radius-md)] bg-rose-pink text-white font-bold text-[15px] hover:bg-rose-pink-dark transition-colors disabled:opacity-50 disabled:cursor-not-allowed shadow-card flex items-center justify-center gap-2"
              >
                {loading && (
                  <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24" fill="none">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                  </svg>
                )}
                {loading ? 'Signing in...' : 'Sign In'}
              </button>
            </form>

            <p className="text-center text-text-secondary text-xs mt-6">
              Contact your school admin if you need access
            </p>
          </>
        )}
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="animate-pulse text-text-secondary">Loading...</div>
      </div>
    }>
      <LoginForm />
    </Suspense>
  );
}
