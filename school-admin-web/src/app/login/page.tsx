'use client';

import { useState, useEffect } from 'react';
import {
  signInWithEmailAndPassword,
  sendPasswordResetEmail,
  getMultiFactorResolver,
  multiFactor,
  PhoneAuthProvider,
  PhoneMultiFactorGenerator,
  RecaptchaVerifier,
  sendEmailVerification,
  signOut,
  TotpMultiFactorGenerator,
  type MultiFactorResolver,
  type MultiFactorError,
  type MultiFactorInfo,
  type PhoneMultiFactorInfo,
  type TotpSecret,
  type User,
} from 'firebase/auth';
import QRCode from 'qrcode';
import { auth } from '@/lib/firebase/client';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense } from 'react';
import { Icon } from '@/components/lumi/icon';
import { useAuth, type AuthUser } from '@/lib/auth/auth-context';
import { characterImageSrc, randomCharacterId } from '@/lib/characters';

type SessionResponse = Partial<AuthUser> & {
  code?: string;
  error?: string;
  enrollmentToken?: string;
};

function LoginForm() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [forgotMode, setForgotMode] = useState(false);
  const [resetMessage, setResetMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
  const [resetLoading, setResetLoading] = useState(false);
  // Second-factor challenge state (SMS for existing staff accounts, or TOTP).
  const [mfaResolver, setMfaResolver] = useState<MultiFactorResolver | null>(null);
  const [mfaHint, setMfaHint] = useState<MultiFactorInfo | null>(null);
  const [mfaVerificationId, setMfaVerificationId] = useState('');
  const [mfaCode, setMfaCode] = useState('');
  const [mfaSending, setMfaSending] = useState(false);
  const [mfaLoading, setMfaLoading] = useState(false);
  // Mandatory first-login TOTP enrollment state for school administrators.
  const [totpEnrollmentToken, setTotpEnrollmentToken] = useState('');
  const [totpSecret, setTotpSecret] = useState<TotpSecret | null>(null);
  const [totpQrCode, setTotpQrCode] = useState('');
  const [totpEnrollmentCode, setTotpEnrollmentCode] = useState('');
  const [totpEnrollmentLoading, setTotpEnrollmentLoading] = useState(false);
  const [emailVerificationRequired, setEmailVerificationRequired] = useState(false);
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

  // Mint the server session cookie and enter the portal (shared by password,
  // MFA challenge, and first-time authenticator enrollment paths).
  const finishLogin = async (user: User, enrollmentProof?: string) => {
    const idToken = await user.getIdToken(Boolean(enrollmentProof));

    const res = await fetch('/api/auth/session', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken, enrollmentToken: enrollmentProof }),
    });

    // A deployment or proxy error can return an empty/non-JSON response. Do
    // not expose its parser error to a person trying to sign in.
    const sessionData = await res.json().catch(() => null) as SessionResponse | null;
    if (
      res.status === 403 &&
      sessionData?.code === 'admin-totp-enrollment-required' &&
      typeof sessionData.enrollmentToken === 'string'
    ) {
      await beginTotpEnrollment(user, sessionData.enrollmentToken);
      return;
    }
    if (!res.ok) {
      throw new Error(sessionData?.error || 'We could not create a secure portal session. Please try again.');
    }

    if (
      !sessionData ||
      typeof sessionData.uid !== 'string' ||
      typeof sessionData.email !== 'string' ||
      typeof sessionData.schoolId !== 'string' ||
      (sessionData.role !== 'teacher' && sessionData.role !== 'schoolAdmin') ||
      typeof sessionData.fullName !== 'string'
    ) {
      throw new Error('We could not create a secure portal session. Please try again.');
    }

    // Inject session data directly into AuthContext to avoid race condition
    setSessionData(sessionData as AuthUser);

    const requestedFrom = searchParams.get('from');
    // Never pass an untrusted absolute or javascript: URL to router.push().
    const from =
      requestedFrom?.startsWith('/') && !requestedFrom.startsWith('//')
        ? requestedFrom
        : '/dashboard';
    router.push(from);
    router.refresh();
  };

  async function beginTotpEnrollment(user: User, enrollmentProof: string) {
    setTotpEnrollmentToken(enrollmentProof);
    setTotpSecret(null);
    setTotpQrCode('');
    setTotpEnrollmentCode('');
    setError('');

    // Firebase requires a verified email before any second factor can be
    // enrolled. Existing Admin-SDK-created staff accounts may not have one yet.
    await user.reload();
    if (!user.emailVerified) {
      setEmailVerificationRequired(true);
      try {
        await sendEmailVerification(user, {
          url: `${window.location.origin}/login`,
        });
      } catch (err) {
        const code = (err as { code?: string })?.code ?? '';
        if (code !== 'auth/too-many-requests') throw err;
      }
      return;
    }

    setEmailVerificationRequired(false);
    // Refresh the token so Identity Platform sees the newly verified-email
    // claim when it authorizes generation of the TOTP enrollment secret.
    await user.getIdToken(true);
    const mfaUser = multiFactor(user);
    const session = await mfaUser.getSession();
    const secret = await TotpMultiFactorGenerator.generateSecret(session);
    const qrCodeUrl = secret.generateQrCodeUrl(
      user.email || 'School administrator',
      'Lumi School',
    );
    const qrDataUrl = await QRCode.toDataURL(qrCodeUrl, {
      width: 220,
      margin: 1,
      errorCorrectionLevel: 'M',
    });
    setTotpSecret(secret);
    setTotpQrCode(qrDataUrl);
  }

  const handleEmailVerified = async () => {
    const user = auth.currentUser;
    if (!user || !totpEnrollmentToken) return;
    setError('');
    setTotpEnrollmentLoading(true);
    try {
      await user.reload();
      if (!user.emailVerified) {
        setError('Your email is not verified yet. Open the link in your email, then try again.');
        return;
      }
      await beginTotpEnrollment(user, totpEnrollmentToken);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not continue setup. Please sign in again.');
    } finally {
      setTotpEnrollmentLoading(false);
    }
  };

  const cancelTotpEnrollment = async () => {
    await signOut(auth);
    setTotpEnrollmentToken('');
    setTotpSecret(null);
    setTotpQrCode('');
    setTotpEnrollmentCode('');
    setEmailVerificationRequired(false);
    setPassword('');
    setError('');
  };

  const handleTotpEnrollmentSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const user = auth.currentUser;
    if (!user || !totpSecret || !totpEnrollmentToken) return;
    setError('');
    setTotpEnrollmentLoading(true);
    try {
      const assertion = TotpMultiFactorGenerator.assertionForEnrollment(
        totpSecret,
        totpEnrollmentCode.trim(),
      );
      await multiFactor(user).enroll(assertion, 'Google Authenticator');
      await finishLogin(user, totpEnrollmentToken);
    } catch (err) {
      const code = (err as { code?: string })?.code ?? '';
      if (code === 'auth/invalid-verification-code') {
        setError("That code didn't match. Wait for a new code and try again.");
      } else if (code === 'auth/requires-recent-login') {
        setError('Setup expired. Return to sign in and enter your password again.');
      } else {
        setError(err instanceof Error ? err.message : 'Authenticator setup failed. Please try again.');
      }
    } finally {
      setTotpEnrollmentLoading(false);
    }
  };

  // Send (or resend) the SMS code for the second factor. The invisible
  // reCAPTCHA needs a live DOM container — #mfa-recaptcha is always rendered.
  const sendMfaCode = async (resolver: MultiFactorResolver, hint: MultiFactorInfo) => {
    setMfaSending(true);
    setError('');
    try {
      const verifier = new RecaptchaVerifier(auth, 'mfa-recaptcha', { size: 'invisible' });
      try {
        const provider = new PhoneAuthProvider(auth);
        const verificationId = await provider.verifyPhoneNumber(
          { multiFactorHint: hint, session: resolver.session },
          verifier,
        );
        setMfaVerificationId(verificationId);
      } finally {
        verifier.clear();
        // The container must be empty before a verifier can bind to it again.
        const el = document.getElementById('mfa-recaptcha');
        if (el) el.innerHTML = '';
      }
    } catch {
      setError('Could not send the verification code. Please try again.');
    } finally {
      setMfaSending(false);
    }
  };

  const startMfaChallenge = async (err: MultiFactorError) => {
    const resolver = getMultiFactorResolver(auth, err);
    // Prefer TOTP when both are enrolled. The server requires TOTP for admins;
    // teachers with only SMS continue through the existing flow.
    const hint =
      resolver.hints.find((h) => h.factorId === TotpMultiFactorGenerator.FACTOR_ID) ??
      resolver.hints.find((h) => h.factorId === PhoneMultiFactorGenerator.FACTOR_ID);
    if (!hint) {
      setError('This account uses a second factor this portal does not support yet.');
      return;
    }
    setMfaResolver(resolver);
    setMfaHint(hint);
    setMfaCode('');
    setMfaVerificationId('');
    if (hint.factorId === PhoneMultiFactorGenerator.FACTOR_ID) {
      await sendMfaCode(resolver, hint);
    }
  };

  const cancelMfa = () => {
    setMfaResolver(null);
    setMfaHint(null);
    setMfaVerificationId('');
    setMfaCode('');
    setError('');
  };

  const handleMfaSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!mfaResolver || !mfaHint) return;
    setError('');
    setMfaLoading(true);
    try {
      const assertion = mfaHint.factorId === TotpMultiFactorGenerator.FACTOR_ID
        ? TotpMultiFactorGenerator.assertionForSignIn(mfaHint.uid, mfaCode.trim())
        : PhoneMultiFactorGenerator.assertion(
            PhoneAuthProvider.credential(mfaVerificationId, mfaCode.trim()),
          );
      const credential = await mfaResolver.resolveSignIn(assertion);
      await finishLogin(credential.user);
    } catch (err) {
      const code = (err as { code?: string })?.code ?? '';
      if (code === 'auth/invalid-verification-code') {
        setError(
          mfaHint.factorId === TotpMultiFactorGenerator.FACTOR_ID
            ? "That code didn't match. Wait for a new code and try again."
            : "That code didn't match. Check the SMS and try again.",
        );
      } else if (code === 'auth/code-expired') {
        setError(
          mfaHint.factorId === TotpMultiFactorGenerator.FACTOR_ID
            ? 'That code has expired. Wait for the next code and try again.'
            : 'That code has expired — tap "Resend code" for a new one.',
        );
      } else {
        setError(err instanceof Error ? err.message : 'Verification failed. Please try again.');
      }
    } finally {
      setMfaLoading(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const credential = await signInWithEmailAndPassword(auth, email, password);
      await finishLogin(credential.user);
    } catch (err) {
      const code = (err as { code?: string })?.code ?? '';
      if (code === 'auth/multi-factor-auth-required') {
        // Resolve either a TOTP or the existing staff SMS factor.
        try {
          await startMfaChallenge(err as MultiFactorError);
        } catch {
          setError('Could not start two-step verification. Please try again.');
        }
      } else if (err instanceof Error) {
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
            {totpEnrollmentToken
              ? 'Secure administrator access'
              : mfaResolver
                ? 'Two-step verification'
                : forgotMode
                  ? 'Reset your password'
                  : 'Sign in to your school portal'}
          </p>
        </div>

        {totpEnrollmentToken ? (
          /* Mandatory administrator TOTP enrollment */
          <form onSubmit={handleTotpEnrollmentSubmit} className="space-y-4">
            {error && (
              <div className="bg-error/10 text-error text-sm rounded-[var(--radius-md)] px-4 py-3">
                {error}
              </div>
            )}

            <div className="rounded-[var(--radius-md)] border border-section/20 bg-section/5 px-4 py-3">
              <p className="text-sm font-semibold text-ink">Authenticator app required</p>
              <p className="mt-1 text-xs leading-5 text-muted">
                School administrators must use two-step verification because they can access
                student information and manage staff permissions.
              </p>
            </div>

            {emailVerificationRequired ? (
              <>
                <p className="text-sm leading-6 text-muted">
                  We sent a verification link to <span className="font-semibold text-ink">{auth.currentUser?.email}</span>.
                  Verify your email first, then return here to continue setup.
                </p>
                <button
                  type="button"
                  disabled={totpEnrollmentLoading}
                  onClick={handleEmailVerified}
                  className="w-full py-3 px-4 rounded-[var(--radius-md)] bg-section text-white font-bold text-[15px] hover:bg-lumi-red-dark transition-colors disabled:opacity-50 disabled:cursor-not-allowed shadow-card"
                >
                  {totpEnrollmentLoading ? 'Checking…' : "I've verified my email"}
                </button>
              </>
            ) : totpSecret && totpQrCode ? (
              <>
                <ol className="list-decimal space-y-2 pl-5 text-sm leading-5 text-muted">
                  <li>Open Google Authenticator and tap the plus button.</li>
                  <li>Scan this QR code.</li>
                  <li>Enter the 6-digit code shown in the app.</li>
                </ol>

                <div className="flex justify-center rounded-[var(--radius-md)] border border-rule bg-white p-3">
                  <img
                    src={totpQrCode}
                    alt="QR code for Google Authenticator setup"
                    width={220}
                    height={220}
                    className="h-[220px] w-[220px]"
                  />
                </div>

                <details className="rounded-[var(--radius-md)] border border-rule bg-paper px-4 py-3 text-sm">
                  <summary className="cursor-pointer font-semibold text-ink">Can&apos;t scan the QR code?</summary>
                  <p className="mt-2 text-xs text-muted">Enter this setup key manually:</p>
                  <code className="mt-2 block break-all select-all rounded bg-cream px-3 py-2 text-xs font-semibold tracking-wider text-ink">
                    {totpSecret.secretKey}
                  </code>
                </details>

                <div>
                  <label htmlFor="totp-enrollment-code" className="block text-sm font-semibold text-ink mb-1.5">
                    Verification code
                  </label>
                  <input
                    id="totp-enrollment-code"
                    type="text"
                    inputMode="numeric"
                    autoComplete="one-time-code"
                    pattern="[0-9]*"
                    maxLength={6}
                    value={totpEnrollmentCode}
                    onChange={(e) => setTotpEnrollmentCode(e.target.value.replace(/\D/g, ''))}
                    placeholder="123456"
                    required
                    autoFocus
                    className="w-full px-4 py-3 rounded-[var(--radius-md)] border border-rule bg-paper text-ink placeholder:text-muted/50 focus:outline-none focus:ring-2 focus:ring-section/30 focus:border-section transition-colors text-[15px] tracking-[0.3em] text-center"
                  />
                </div>

                <button
                  type="submit"
                  disabled={totpEnrollmentLoading || totpEnrollmentCode.length < 6}
                  className="w-full py-3 px-4 rounded-[var(--radius-md)] bg-section text-white font-bold text-[15px] hover:bg-lumi-red-dark transition-colors disabled:opacity-50 disabled:cursor-not-allowed shadow-card flex items-center justify-center gap-2"
                >
                  {totpEnrollmentLoading ? 'Securing account…' : 'Enable & Sign In'}
                </button>
              </>
            ) : (
              <p className="py-6 text-center text-sm text-muted">Preparing secure setup…</p>
            )}

            <button
              type="button"
              disabled={totpEnrollmentLoading}
              onClick={cancelTotpEnrollment}
              className="w-full text-sm text-muted hover:text-ink font-semibold transition-colors py-2 disabled:opacity-50"
            >
              Back to sign in
            </button>
          </form>
        ) : mfaResolver ? (
          /* Existing SMS or authenticator second-factor challenge */
          <form onSubmit={handleMfaSubmit} className="space-y-4">
            {error && (
              <div className="bg-error/10 text-error text-sm rounded-[var(--radius-md)] px-4 py-3">
                {error}
              </div>
            )}

            {mfaHint?.factorId === TotpMultiFactorGenerator.FACTOR_ID ? (
              <p className="text-sm text-muted">
                Open Google Authenticator and enter the current 6-digit code to finish signing in.
              </p>
            ) : (
              <p className="text-sm text-muted">
                We sent a 6-digit code by SMS
                {(mfaHint as PhoneMultiFactorInfo | null)?.phoneNumber
                  ? ` to ${(mfaHint as PhoneMultiFactorInfo).phoneNumber}`
                  : ' to your enrolled phone'}
                . Enter it below to finish signing in.
              </p>
            )}

            <div>
              <label htmlFor="mfa-code" className="block text-sm font-semibold text-ink mb-1.5">
                Verification code
              </label>
              <input
                id="mfa-code"
                type="text"
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="[0-9]*"
                maxLength={6}
                value={mfaCode}
                onChange={(e) => setMfaCode(e.target.value.replace(/\D/g, ''))}
                placeholder="123456"
                required
                autoFocus
                className="w-full px-4 py-3 rounded-[var(--radius-md)] border border-rule bg-paper text-ink placeholder:text-muted/50 focus:outline-none focus:ring-2 focus:ring-section/30 focus:border-section transition-colors text-[15px] tracking-[0.3em] text-center"
              />
            </div>

            <button
              type="submit"
              disabled={
                mfaLoading ||
                mfaSending ||
                mfaCode.length < 6 ||
                (mfaHint?.factorId === PhoneMultiFactorGenerator.FACTOR_ID && !mfaVerificationId)
              }
              className="w-full py-3 px-4 rounded-[var(--radius-md)] bg-section text-white font-bold text-[15px] hover:bg-lumi-red-dark transition-colors disabled:opacity-50 disabled:cursor-not-allowed shadow-card flex items-center justify-center gap-2"
            >
              {mfaLoading && (
                <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24" fill="none">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                </svg>
              )}
              {mfaLoading ? 'Verifying...' : 'Verify & Sign In'}
            </button>

            <div className="flex items-center justify-between">
              {mfaHint?.factorId === PhoneMultiFactorGenerator.FACTOR_ID ? (
                <button
                  type="button"
                  disabled={mfaSending}
                  onClick={() => mfaResolver && mfaHint && sendMfaCode(mfaResolver, mfaHint)}
                  className="text-sm text-section hover:text-lumi-red-dark font-semibold transition-colors py-2 disabled:opacity-50"
                >
                  {mfaSending ? 'Sending…' : 'Resend code'}
                </button>
              ) : <span />}
              <button
                type="button"
                onClick={cancelMfa}
                className="text-sm text-muted hover:text-ink font-semibold transition-colors py-2"
              >
                Back to sign in
              </button>
            </div>
          </form>
        ) : forgotMode ? (
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

        {/* Invisible reCAPTCHA anchor for the SMS second factor — must always
            be in the DOM before a challenge starts. */}
        <div id="mfa-recaptcha" />
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
