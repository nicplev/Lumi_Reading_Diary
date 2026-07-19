import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import test from "node:test";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const readText = (relativePath) =>
  readFile(path.join(repoRoot, relativePath), "utf8");

const appId = "C2BSJNTRU5.com.lumi.lumiReadingTracker";
const androidPackage = "com.lumi.lumi_reading_tracker";

test("marketing AASA scopes App Links and enables Apple web credentials", async () => {
  const aasa = JSON.parse(
    await readText("marketing-site/public/aasa.json"),
  );

  assert.deepEqual(aasa.webcredentials.apps, [appId]);
  assert.deepEqual(aasa.applinks.details, [
    { appID: appId, paths: ["/app"] },
  ]);
});

test("Android association uses real fingerprints and both required relations", async () => {
  const statements = JSON.parse(
    await readText("marketing-site/public/assetlinks.json"),
  );
  assert.equal(statements.length, 1);

  const statement = statements[0];
  assert.deepEqual(new Set(statement.relation), new Set([
    "delegate_permission/common.get_login_creds",
    "delegate_permission/common.handle_all_urls",
  ]));
  assert.equal(statement.target.namespace, "android_app");
  assert.equal(statement.target.package_name, androidPackage);
  assert.ok(statement.target.sha256_cert_fingerprints.length > 0);
  for (const fingerprint of statement.target.sha256_cert_fingerprints) {
    assert.match(fingerprint, /^(?:[0-9A-F]{2}:){31}[0-9A-F]{2}$/);
    assert.doesNotMatch(fingerprint, /REPLACE|PLACEHOLDER/i);
  }
});

test("Firebase serves explicit associations only from marketing Hosting", async () => {
  const firebaseConfig = JSON.parse(await readText("firebase.json"));
  assert.equal(
    firebaseConfig.hosting.some((entry) => entry.target === "default"),
    false,
    "The disabled public Flutter Hosting target must not be deployable from this config",
  );

  const marketing = firebaseConfig.hosting.find(
    (entry) => entry.target === "marketing",
  );
  assert.ok(marketing);
  assert.equal(marketing.appAssociation, "NONE");
  assert.deepEqual(marketing.rewrites, [
    {
      source: "/.well-known/apple-app-site-association",
      destination: "/aasa.json",
    },
    {
      source: "/.well-known/assetlinks.json",
      destination: "/assetlinks.json",
    },
  ]);
});

test("native declarations trust only lumi-reading.com and the /app path", async () => {
  const entitlements = await readText("ios/Runner/Runner.entitlements");
  assert.match(entitlements, /applinks:lumi-reading\.com/);
  assert.match(entitlements, /webcredentials:lumi-reading\.com/);
  assert.doesNotMatch(entitlements, /lumi-ninc-au\.(?:web\.app|firebaseapp\.com)/);

  const manifest = await readText("android/app/src/main/AndroidManifest.xml");
  assert.match(manifest, /android:autoVerify="true"/);
  assert.match(manifest, /android:host="lumi-reading\.com"/);
  assert.match(manifest, /android:path="\/app"/);
});
