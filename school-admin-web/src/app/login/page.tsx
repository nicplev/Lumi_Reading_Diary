'use client';

import { useState, useEffect } from 'react';
import { signInWithEmailAndPassword, sendPasswordResetEmail } from 'firebase/auth';
import { auth } from '@/lib/firebase/client';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense } from 'react';
import { Icon } from '@/components/lumi/icon';
import { useAuth } from '@/lib/auth/auth-context';
import { characterImageSrc, randomCharacterId } from '@/lib/characters';

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

  // A different Lumi friend greets every visitor. Picked once on mount
  // (client-only) so it's fresh on every page load and never collides with
  // SSR hydration.
  const [character, setCharacter] = useState<string | null>(null);
  useEffect(() => {
    setCharacter(randomCharacterId());
  }, []);

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
    <div className="min-h-screen flex items-center justify-center bg-cream px-4">
      <div className="w-full max-w-sm">
        {/* Logo / Brand — a surprise Lumi character greets each visitor */}
        <div className="text-center mb-8">
          <div className="flex justify-center mb-4">
            {character ? (
              <img
                src={characterImageSrc(character) ?? ''}
                alt=""
                width={96}
                height={96}
                draggable={false}
                className="w-24 h-24 object-contain animate-success-pop select-none"
              />
            ) : (
              // Reserve the space before the client picks a character (avoids layout shift).
              <span aria-hidden className="block w-24 h-24" />
            )}
          </div>
          <h1 className="font-display text-[28px] font-extrabold tracking-tight text-ink">Lumi School</h1>
          <p className="text-muted text-sm mt-1">
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
              <label htmlFor="reset-email" className="block text-sm font-semibold text-ink mb-1.5">
                Email
              </label>
              <input
                id="reset-email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="teacher@school.com"
                required
                className="w-full px-4 py-3 rounded-[var(--radius-md)] border border-rule bg-paper text-ink placeholder:text-muted/50 focus:outline-none focus:ring-2 focus:ring-section/30 focus:border-section transition-colors text-[15px]"
              />
            </div>

            <button
              type="submit"
              disabled={resetLoading}
              className="w-full py-3 px-4 rounded-[var(--radius-md)] bg-section text-white font-bold text-[15px] hover:bg-lumi-red-dark transition-colors disabled:opacity-50 disabled:cursor-not-allowed shadow-card flex items-center justify-center gap-2"
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
              className="w-full text-sm text-section hover:text-lumi-red-dark font-semibold transition-colors py-2"
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
                <label htmlFor="email" className="block text-sm font-semibold text-ink mb-1.5">
                  Email
                </label>
                <input
                  id="email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="teacher@school.com"
                  required
                  className="w-full px-4 py-3 rounded-[var(--radius-md)] border border-rule bg-paper text-ink placeholder:text-muted/50 focus:outline-none focus:ring-2 focus:ring-section/30 focus:border-section transition-colors text-[15px]"
                />
              </div>

              <div>
                <div className="flex items-center justify-between mb-1.5">
                  <label htmlFor="password" className="block text-sm font-semibold text-ink">
                    Password
                  </label>
                  <button
                    type="button"
                    onClick={() => { setForgotMode(true); setError(''); setResetMessage(null); }}
                    className="text-xs text-section hover:text-lumi-red-dark font-semibold transition-colors"
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
                    className="w-full px-4 py-3 pr-12 rounded-[var(--radius-md)] border border-rule bg-paper text-ink placeholder:text-muted/50 focus:outline-none focus:ring-2 focus:ring-section/30 focus:border-section transition-colors text-[15px]"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    tabIndex={-1}
                    aria-label={showPassword ? 'Hide password' : 'Show password'}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-muted hover:text-ink transition-colors"
                  >
                    <Icon name={showPassword ? 'visibility_off' : 'visibility'} size={20} />
                  </button>
                </div>
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full py-3 px-4 rounded-[var(--radius-md)] bg-section text-white font-bold text-[15px] hover:bg-lumi-red-dark transition-colors disabled:opacity-50 disabled:cursor-not-allowed shadow-card flex items-center justify-center gap-2"
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

            <p className="text-center text-muted text-xs mt-6">
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
      <div className="min-h-screen flex items-center justify-center bg-cream">
        <div className="animate-pulse text-muted">Loading...</div>
      </div>
    }>
      <LoginForm />
    </Suspense>
  );
}
