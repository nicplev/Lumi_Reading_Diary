"use client";

import { Suspense, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { signInWithEmailAndPassword } from "firebase/auth";
import { clientAuth } from "@/lib/firebase-client";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { BookOpen } from "lucide-react";

type Stage = "password" | "mfa" | "enroll";

interface Enrollment {
  qrDataUrl: string;
  secret: string;
}

function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const redirect = searchParams.get("redirect") || "/";

  const [stage, setStage] = useState<Stage>("password");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [idToken, setIdToken] = useState("");
  const [enrollment, setEnrollment] = useState<Enrollment | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  function backToPassword(message: string) {
    setStage("password");
    setIdToken("");
    setCode("");
    setEnrollment(null);
    setError(message);
  }

  async function handlePassword(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      const credential = await signInWithEmailAndPassword(clientAuth, email, password);
      const token = await credential.user.getIdToken();
      setIdToken(token);

      const res = await fetch("/api/auth", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ idToken: token }),
      });
      const data = await res.json().catch(() => ({}));

      if (res.ok) {
        router.push(redirect);
        return;
      }
      if (data.status === "mfa_required") {
        setStage("mfa");
        return;
      }
      if (data.status === "enrollment_required") {
        const startRes = await fetch("/api/auth/mfa/enroll", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ idToken: token, step: "start" }),
        });
        const startData = await startRes.json().catch(() => ({}));
        if (!startRes.ok) throw new Error(startData.error || "Could not start enrollment");
        setEnrollment({ qrDataUrl: startData.qrDataUrl, secret: startData.secret });
        setStage("enroll");
        return;
      }
      throw new Error(data.error || "Authentication failed");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Sign in failed");
    } finally {
      setLoading(false);
    }
  }

  async function handleCode(e: React.FormEvent, endpoint: string, step?: string) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ idToken, code, ...(step ? { step } : {}) }),
      });
      const data = await res.json().catch(() => ({}));
      if (res.ok) {
        router.push(redirect);
        return;
      }
      // A stale ID token (sign-in older than 5 min) means we must restart.
      if (/session too old/i.test(data.error || "")) {
        backToPassword("Your sign-in expired. Please enter your password again.");
        return;
      }
      throw new Error(data.error || "Invalid code");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Verification failed");
      setCode("");
    } finally {
      setLoading(false);
    }
  }

  if (stage === "mfa") {
    return (
      <form onSubmit={(e) => handleCode(e, "/api/auth")} className="space-y-4">
        {error && (
          <div className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">{error}</div>
        )}
        <p className="text-sm text-muted-foreground">
          Enter the 6-digit code from your authenticator app.
        </p>
        <div className="space-y-2">
          <Label htmlFor="code">Authentication code</Label>
          <Input
            id="code"
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="\d{6}"
            maxLength={6}
            placeholder="123456"
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
            autoFocus
            required
          />
        </div>
        <Button type="submit" className="w-full" disabled={loading}>
          {loading ? "Verifying..." : "Verify"}
        </Button>
      </form>
    );
  }

  if (stage === "enroll" && enrollment) {
    return (
      <form
        onSubmit={(e) => handleCode(e, "/api/auth/mfa/enroll", "confirm")}
        className="space-y-4"
      >
        {error && (
          <div className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">{error}</div>
        )}
        <p className="text-sm text-muted-foreground">
          Set up two-factor authentication. Scan this QR code with Google
          Authenticator (or any TOTP app), then enter the 6-digit code to confirm.
        </p>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={enrollment.qrDataUrl}
          alt="Authenticator QR code"
          className="mx-auto rounded-md border"
          width={220}
          height={220}
        />
        <p className="text-center text-xs text-muted-foreground">
          Can&rsquo;t scan? Enter this key manually:
          <br />
          <code className="break-all font-mono">{enrollment.secret}</code>
        </p>
        <div className="space-y-2">
          <Label htmlFor="code">Confirmation code</Label>
          <Input
            id="code"
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="\d{6}"
            maxLength={6}
            placeholder="123456"
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
            autoFocus
            required
          />
        </div>
        <Button type="submit" className="w-full" disabled={loading}>
          {loading ? "Confirming..." : "Confirm & sign in"}
        </Button>
      </form>
    );
  }

  return (
    <form onSubmit={handlePassword} className="space-y-4">
      {error && (
        <div className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">{error}</div>
      )}
      <div className="space-y-2">
        <Label htmlFor="email">Email</Label>
        <Input
          id="email"
          type="email"
          placeholder="admin@example.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
      </div>
      <div className="space-y-2">
        <Label htmlFor="password">Password</Label>
        <Input
          id="password"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
        />
      </div>
      <Button type="submit" className="w-full" disabled={loading}>
        {loading ? "Signing in..." : "Sign in"}
      </Button>
    </form>
  );
}

export default function LoginPage() {
  return (
    <div className="flex min-h-svh items-center justify-center bg-muted p-4">
      <Card className="w-full max-w-sm">
        <CardHeader className="text-center">
          <div className="mx-auto mb-2 flex h-12 w-12 items-center justify-center rounded-lg bg-primary text-primary-foreground">
            <BookOpen className="h-6 w-6" />
          </div>
          <CardTitle className="text-2xl">Lumi Admin</CardTitle>
          <CardDescription>Sign in to the admin dashboard</CardDescription>
        </CardHeader>
        <CardContent>
          <Suspense>
            <LoginForm />
          </Suspense>
        </CardContent>
      </Card>
    </div>
  );
}
