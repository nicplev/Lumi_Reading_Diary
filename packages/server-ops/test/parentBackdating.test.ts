import test from "node:test";
import assert from "node:assert/strict";
import { parentBackdatingEnabledFromDoc } from "../src/parentBackdating";

// The only other resolver of platformConfig/parentBackdating is the Flutter
// client (isParentBackdatingEnabled in lib/services/platform_config_service
// .dart): `!doc.exists || data['enabled'] != false`. Dart can't be imported
// here, so these fixtures pin the exact semantics the card must share with
// the app — if the resolver ever tightens (e.g. `enabled === true`), the
// portal would show OFF while every parent still saw the Yesterday toggle.

test("parent backdating resolves ENABLED for everything except literal false", () => {
  const enabledFixtures: unknown[] = [
    // The case that matters most: no document has ever been written —
    // decision D1 ships the feature ON for first-round school testing.
    undefined,
    null,
    {},
    { enabled: true },
    // Only a literal false may disable. Everything else is on.
    { enabled: "false" },
    { enabled: 0 },
    { enabled: null },
    { enabled: undefined },
    { somethingElse: true },
    // Hostile / malformed shapes.
    [],
    "nonsense",
    42,
    { enabled: { nested: false } },
  ];
  for (const fixture of enabledFixtures) {
    assert.equal(
      parentBackdatingEnabledFromDoc(fixture),
      true,
      `expected ENABLED for ${JSON.stringify(fixture) ?? "undefined"}`
    );
  }
  assert.equal(parentBackdatingEnabledFromDoc({ enabled: false }), false);
});

test("the flag fails OPEN — the D1 kill switch, not a launch gate", () => {
  // A missing doc or a Firestore blip must never remove the feature
  // mid-beta; only Nic explicitly writing {enabled: false} does.
  assert.equal(parentBackdatingEnabledFromDoc(undefined), true);
  assert.equal(parentBackdatingEnabledFromDoc({}), true);
  assert.equal(parentBackdatingEnabledFromDoc({ enabled: false }), false);
});
