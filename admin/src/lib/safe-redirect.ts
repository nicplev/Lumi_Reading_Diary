const REDIRECT_BASE = "https://admin.lumi.invalid";

/**
 * Accept only an in-portal path. This value ultimately reaches router.push(),
 * so absolute, protocol-relative, script, backslash and login-loop targets are
 * rejected rather than trusted from the query string.
 */
export function safeRedirectTarget(candidate: string | null | undefined): string {
  if (!candidate || !candidate.startsWith("/") || candidate.startsWith("//")) {
    return "/";
  }
  if (candidate.includes("\\")) return "/";

  try {
    const parsed = new URL(candidate, REDIRECT_BASE);
    if (parsed.origin !== REDIRECT_BASE || parsed.pathname === "/login") {
      return "/";
    }
    return `${parsed.pathname}${parsed.search}${parsed.hash}`;
  } catch {
    return "/";
  }
}
