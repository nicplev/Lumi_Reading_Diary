const { test } = require('node:test');
const assert = require('node:assert/strict');

// Built to lib/ by `npm run build`.
const { assertNotReadOnly } = require('../lib/read_only_guard.js');

function ctx(token) {
  return token === undefined ? {} : { auth: { uid: 'u1', token } };
}

test('assertNotReadOnly: throws when devReadOnly claim is true', () => {
  assert.throws(
    () => assertNotReadOnly(ctx({ devReadOnly: true })),
    (e) => e.code === 'permission-denied',
  );
});

test('assertNotReadOnly: throws for the read-only demo administrator', () => {
  assert.throws(
    () => assertNotReadOnly(ctx({ demoReadOnly: true })),
    (e) => e.code === 'permission-denied',
  );
});

test('assertNotReadOnly: allows a normal user (no impersonation claims)', () => {
  assert.doesNotThrow(() => assertNotReadOnly(ctx({ email: 'a@b.com' })));
});

test('assertNotReadOnly: allows an unauthenticated context', () => {
  assert.doesNotThrow(() => assertNotReadOnly(ctx()));
});

test('assertNotReadOnly: only the boolean true blocks, not truthy values', () => {
  // Firebase claims are typed; guard must match the exact devReadOnly:true
  // pairing the minter sets, not incidental truthy strings.
  assert.doesNotThrow(() => assertNotReadOnly(ctx({ devReadOnly: 'false' })));
  assert.doesNotThrow(() => assertNotReadOnly(ctx({ devReadOnly: false })));
  assert.doesNotThrow(() => assertNotReadOnly(ctx({ demoReadOnly: 'true' })));
  assert.doesNotThrow(() => assertNotReadOnly(ctx({ demoReadOnly: false })));
});
