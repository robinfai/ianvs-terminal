import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import {
  createCanonicalSshProfile,
  emptySshConnection,
  isSshProfile,
  mergeProfilesDocument,
  splitProfilesDocument,
  type ProfilesDocument,
  type TerminalProfile,
} from '../src/lib/profileDoc.ts'

const fixture = JSON.parse(
  readFileSync(new URL('./fixtures/profile_document.json', import.meta.url), 'utf8'),
) as {
  data: Record<string, unknown>
  sensitive: Record<string, unknown>
}

test('profile codec preserves canonical data and recursively encrypted ProxyJump secrets', () => {
  const merged = mergeProfilesDocument(fixture.data, fixture.sensitive)
  const profile = merged.profiles[0]

  assert.ok(isSshProfile(profile))
  assert.equal(profile.connection.host, 'target.example.test')
  assert.equal(profile.connection.password, ' target password ')
  assert.deepEqual(profile.connection.proxyJumpProfiles[0], {
    host: 'jump.example.test',
    user: 'jump-user',
    port: 22,
    auth: 'password',
    privateKeys: [],
    hostKeyPolicy: 'strict',
    connectTimeoutSeconds: 10,
    keepaliveSeconds: 0,
    keepaliveCountMax: 3,
    password: ' jump password ',
    privateKeyPassphrase: ' jump passphrase ',
  })

  const split = splitProfilesDocument(merged)
  assert.deepEqual(split.data, fixture.data)
  assert.deepEqual(split.sensitive, fixture.sensitive)
  assert.doesNotMatch(JSON.stringify(split.data), /target password|jump password|passphrase/)
})

test('canonical web profile exactly matches the shared Dart fixture', () => {
  const profile = createCanonicalSshProfile({
    id: 'fixture-ssh',
    name: 'Fixture SSH',
    connection: emptySshConnection({
      host: 'target.example.test',
      user: 'operator',
      auth: 'public_key',
      privateKeys: ['~/.ssh/id_ed25519'],
      password: ' target password ',
      privateKeyPassphrase: ' target passphrase ',
      proxyJumpProfiles: [
        {
          host: 'jump.example.test',
          user: 'jump-user',
          port: 22,
          auth: 'password',
          privateKeys: [],
          hostKeyPolicy: 'strict',
          connectTimeoutSeconds: 10,
          keepaliveSeconds: 0,
          keepaliveCountMax: 3,
          password: ' jump password ',
          privateKeyPassphrase: ' jump passphrase ',
        },
      ],
      x11AuthCookie: ' 00112233445566778899aabbccddeeff ',
    }),
  })

  const split = splitProfilesDocument({ schemaVersion: 1, profiles: [profile] })
  assert.deepEqual(split.data, fixture.data)
  assert.deepEqual(split.sensitive, fixture.sensitive)
})

test('non-SSH profiles remain untouched and are excluded from SSH management', () => {
  const localProfile: TerminalProfile = {
    id: 'local-shell',
    name: 'Local Shell',
    connection: { type: 'local' },
    launch: { program: '/bin/zsh', args: ['-l'], env: {}, cwd: null },
  }
  const sshDocument = mergeProfilesDocument(fixture.data, fixture.sensitive)
  const document: ProfilesDocument = {
    schemaVersion: 1,
    profiles: [localProfile, ...sshDocument.profiles],
  }

  assert.equal(isSshProfile(localProfile), false)
  assert.equal(document.profiles.filter(isSshProfile).length, 1)

  const split = splitProfilesDocument(document)
  const restored = mergeProfilesDocument(split.data, split.sensitive)
  assert.deepEqual(restored.profiles[0], localProfile)
})
