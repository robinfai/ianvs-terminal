import assert from 'node:assert/strict'
import test from 'node:test'
import {
  SensitiveDataAuthenticationError,
  decryptSensitive,
  encryptSensitive,
} from '../src/crypto/sensitive.ts'

test('browser encrypts and decrypts opaque sensitive envelopes locally', async () => {
  const envelope = await encryptSensitive(
    'test-master-key-material-with-enough-entropy',
    'owner-a',
    'profile',
    'work',
    { password: 'secret' },
  )

  assert.doesNotMatch(JSON.stringify(envelope), /secret/)
  assert.deepEqual(
    await decryptSensitive(
      'test-master-key-material-with-enough-entropy',
      'owner-a',
      'profile',
      'work',
      envelope,
    ),
    { password: 'secret' },
  )
})

test('wrong key and transplanted resource identity fail locally', async () => {
  const envelope = await encryptSensitive(
    'correct-test-master-key-material',
    'owner-a',
    'profile',
    'work',
    { password: 'secret' },
  )

  await assert.rejects(
    decryptSensitive(
      'wrong-test-master-key-material',
      'owner-a',
      'profile',
      'work',
      envelope,
    ),
    SensitiveDataAuthenticationError,
  )
  await assert.rejects(
    decryptSensitive(
      'correct-test-master-key-material',
      'owner-b',
      'profile',
      'work',
      envelope,
    ),
    SensitiveDataAuthenticationError,
  )
})
