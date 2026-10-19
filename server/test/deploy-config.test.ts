import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadConfig } from '../src/config.ts';

/// The two Fly apps and the two shipping builds of the app have to agree: a
/// Staging build talking to the production API, or a server expecting the
/// other bundle id, fails only once someone tries to sign in.

const read = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8');

/// The [env] table of a fly.toml — flat `KEY = "value"` lines only.
function flyEnv(file: string): Record<string, string> {
  const section = /\n\[env\]\n([\s\S]*?)(?:\n\[|$)/.exec(read(file))?.[1] ?? '';
  return Object.fromEntries([...section.matchAll(/^\s*([A-Z_]+)\s*=\s*"([^"]*)"/gm)].map((m) => [m[1]!, m[2]!]));
}

/// One build configuration's settings for the app target in the Xcode project.
function xcodeSettings(configuration: string): Record<string, string> {
  const project = read('../../CashStack.xcodeproj/project.pbxproj');
  const blocks = [...project.matchAll(/\/\* (\w+) \*\/ = \{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = \{\n([\s\S]*?)\n\t\t\t\};/g)];
  const app = blocks.find((b) => b[1] === configuration && b[2]!.includes('CASHSTACK_API_URL'));
  assert.ok(app, `no ${configuration} configuration for the app target`);
  return Object.fromEntries([...app[2]!.matchAll(/^\t+([A-Z_]+) = "?([^";]*)"?;/gm)].map((m) => [m[1]!, m[2]!]));
}

const secrets = {
  DATABASE_URL: 'postgres://example',
  BASIQ_API_KEY: 'key',
  BASIQ_WEBHOOK_SECRET: 'whsec_x',
  DATA_KEY: Buffer.alloc(32, 1).toString('base64'),
};

describe('deploy config', () => {
  for (const [file, configuration] of [['../fly.toml', 'Release'], ['../fly.staging.toml', 'Staging']] as const) {
    test(`${file} matches the ${configuration} build`, () => {
      const env = flyEnv(file);
      const xcode = xcodeSettings(configuration);
      assert.match(env.APP_BUNDLE_ID ?? '', /^com\.bokscot\.cashstack/);
      assert.match(env.PUBLIC_URL ?? '', /^https:\/\//);
      assert.equal(env.APP_BUNDLE_ID, xcode.PRODUCT_BUNDLE_IDENTIFIER);
      assert.equal(env.PUBLIC_URL, xcode.CASHSTACK_API_URL);
    });

    test(`${file} starts in production once its secrets are set`, () => {
      const config = loadConfig({ ...flyEnv(file), ...secrets });
      assert.equal(config.env, 'production');
      assert.equal(config.basiq.mode, 'live');
    });
  }

  test('staging and production are different apps', () => {
    assert.notEqual(flyEnv('../fly.toml').PUBLIC_URL, flyEnv('../fly.staging.toml').PUBLIC_URL);
    assert.match(read('../fly.staging.toml'), /^app = "cashstack-api-staging"$/m);
  });
});
