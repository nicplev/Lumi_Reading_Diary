import test from 'node:test';
import assert from 'node:assert/strict';
import {
  hasDemoAllocationCapability,
  isCurrentDemoAllocationAuthority,
} from './allocation-policy.ts';

test('only the exact signed demo-admin capability reaches mutation handlers', () => {
  const valid = {
    role: 'schoolAdmin',
    mfaExemptReason: 'isolatedDemoReadOnly',
    demoAllocationMutations: true,
    demoGenerationId: 'generation-1',
  };
  assert.equal(hasDemoAllocationCapability(valid), true);
  assert.equal(hasDemoAllocationCapability({ ...valid, role: 'teacher' }), false);
  assert.equal(hasDemoAllocationCapability({ ...valid, demoAllocationMutations: false }), false);
  assert.equal(hasDemoAllocationCapability({ ...valid, demoGenerationId: '' }), false);
});

test('live membership and the current reseed lease are both mandatory', () => {
  const valid = {
    schoolExists: true,
    schoolIsDemo: true,
    membershipExists: true,
    membershipRole: 'schoolAdmin',
    membershipActive: true,
    membershipPendingDeletion: false,
    reseedState: 'succeeded',
    reseedSchoolId: 'demo-school',
    reseedLeaseId: 'generation-1',
    sessionSchoolId: 'demo-school',
    sessionGenerationId: 'generation-1',
  };
  assert.equal(isCurrentDemoAllocationAuthority(valid), true);
  assert.equal(isCurrentDemoAllocationAuthority({ ...valid, reseedLeaseId: 'generation-2' }), false);
  assert.equal(isCurrentDemoAllocationAuthority({ ...valid, membershipActive: false }), false);
  assert.equal(isCurrentDemoAllocationAuthority({ ...valid, schoolIsDemo: false }), false);
});

