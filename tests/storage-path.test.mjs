// The engine owns its folder: every namespace resolves under mgba/, and none can
// climb out of it. Runs against the built SDK (make build-sdk), the module a host
// actually imports — which also proves it loads with no import map or bundler.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import MgbaSDK, { storagePath, STATE_SLOTS, AUTO_STATE_SLOT, MGBA_SPEC } from '../dist/mgba/mgba.sdk.js';

const cases = [
  [undefined, 'default', 'mgba/default', false],
  ['', 'default', 'mgba/default', false],
  [{ id: 'zelda' }, 'default', 'mgba/default', false],
  ['minish-cap', 'minish-cap', 'mgba/minish-cap', false],
  ['zelda/profile-a', 'zelda/profile-a', 'mgba/zelda/profile-a', false],
  [' a b /c? ', 'a_b/c_', 'mgba/a_b/c_', false],
  ['../x', 'x', 'mgba/x', false],
  ['..', 'default', 'mgba/default', false],
  ['/abs/path', 'abs/path', 'mgba/abs/path', false],
  ['mgba/Zelda', 'Zelda', 'mgba/Zelda', true],
  ['mgba', 'mgba', 'mgba/mgba', false],
];

for (const [input, namespace, path, prefixed] of cases) {
  test(`storagePath('mgba', ${JSON.stringify(input)}) → ${path}`, () => {
    assert.deepEqual(storagePath('mgba', input), { namespace, path, prefixed });
  });
}

test('the engine id is the folder', () => {
  assert.equal(MgbaSDK.id, 'mgba');
});

test('the slots are the other engines\' slots: 0-3 and the unsaved point in 9', () => {
  assert.equal(STATE_SLOTS, 4);
  assert.equal(AUTO_STATE_SLOT, 9);
});

test('the spec describes every option of the settings catalog', () => {
  assert.deepEqual(MGBA_SPEC.assets.rom.allowedTypes, ['.gba', '.gb', '.gbc', '.sgb', '.zip']);
  assert.ok(MGBA_SPEC.assets.bios, 'an optional BIOS asset');
  assert.equal(MGBA_SPEC.storage.namespace.default, 'default');
  assert.equal(MGBA_SPEC.options.system.default, 'auto');
  assert.equal(MGBA_SPEC.options.system.live, false, 'the system needs a reset');
  assert.equal(MGBA_SPEC.options.volume.live, true);
  assert.deepEqual(MGBA_SPEC.options.gbModel.enum, ['auto', 'dmg', 'sgb', 'cgb', 'agb']);
  assert.equal('escMenu' in MGBA_SPEC.options, false, 'mGBA draws no settings overlay of its own');
});

test('a play opened without a ROM says so', async () => {
  // No DOM here: mount() is skipped, so start() stops at the first missing piece.
  await assert.rejects(() => new MgbaSDK().start(), /mount\(\)|ROM/);
});
