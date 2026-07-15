import assert from 'node:assert/strict';
import test from 'node:test';

import {
  allowVerifiedJwtAfterMembershipLookupFailure,
  isCurrentMembershipValid,
} from './session-policy.ts';

test('old session is rejected after deactivation, deletion or role change', () => {
  assert.equal(isCurrentMembershipValid(false, undefined, 'teacher'), false);
  assert.equal(
    isCurrentMembershipValid(true, { role: 'teacher', isActive: false }, 'teacher'),
    false,
  );
  assert.equal(
    isCurrentMembershipValid(
      true,
      { role: 'teacher', pendingDeletion: true },
      'teacher',
    ),
    false,
  );
  assert.equal(
    isCurrentMembershipValid(true, { role: 'teacher' }, 'schoolAdmin'),
    false,
  );
  assert.equal(
    isCurrentMembershipValid(true, { role: 'teacher', isActive: true }, 'teacher'),
    true,
  );
});

test('membership lookup errors fail closed for mutable routes', () => {
  assert.equal(allowVerifiedJwtAfterMembershipLookupFailure(true), false);
  assert.equal(allowVerifiedJwtAfterMembershipLookupFailure(false), true);
});
