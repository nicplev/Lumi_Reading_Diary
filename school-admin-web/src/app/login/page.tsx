'use client';

import { useState } from 'react';
import { signInWithEmailAndPassword } from 'firebase/auth';
import { auth } from '@/lib/firebase/client';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense } from 'react';
import { Icon } from '@/components/lumi/icon';

function LoginForm() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const router = useRouter();
  const searchParams = useSearchParams();

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

      if (!res.ok) {
        const data = await res.json();
        throw new Error(data.error || 'Login failed');
      }

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

  return (
    <div className="min-h-screen flex items-center justify-center bg-background px-4">
      <div className="w-full max-w-sm">
        {/* Logo / Brand */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-[var(--radius-xl)] bg-rose-pink/10 mb-4">
            <span className="text-rose-pink"><Icon name="library_books" size={32} /></span>
          </div>
          <h1 className="text-[28px] font-bold text-charcoal">Lumi School</h1>
          <p className="text-text-secondary text-sm mt-1">Sign in to your school portal</p>
        </div>

        {/* Login Form */}
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
            <label htmlFor="password" className="block text-sm font-semibold text-charcoal mb-1.5">
              Password
            </label>
            <input
              id="password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              required
              className="w-full px-4 py-3 rounded-[var(--radius-md)] border border-divider bg-surface text-charcoal placeholder:text-text-secondary/50 focus:outline-none focus:ring-2 focus:ring-rose-pink/30 focus:border-rose-pink transition-colors text-[15px]"
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full py-3 px-4 rounded-[var(--radius-md)] bg-rose-pink text-white font-bold text-[15px] hover:bg-rose-pink-dark transition-colors disabled:opacity-50 disabled:cursor-not-allowed shadow-card"
          >
            {loading ? 'Signing in...' : 'Sign In'}
          </button>
        </form>

        <p className="text-center text-text-secondary text-xs mt-6">
          Contact your school admin if you need access
        </p>
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
