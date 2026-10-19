import { test } from 'node:test';
import assert from 'node:assert/strict';
import { maskAccountNumber, toMinor } from '../src/money.ts';

test('decimal strings become whole cents without floating point', () => {
  assert.equal(toMinor('420.28'), 42028);
  assert.equal(toMinor('0.1'), 10);
  assert.equal(toMinor('1000'), 100000);
  assert.equal(toMinor('-12.5'), -1250);
  assert.equal(toMinor('+3.05'), 305);
  assert.equal(toMinor('19.999'), 2000);
  assert.equal(toMinor('19.994'), 1999);
  assert.equal(toMinor(' 7.00 '), 700);
});

test('anything that is not an amount is refused rather than guessed', () => {
  assert.equal(toMinor(undefined), null);
  assert.equal(toMinor(null), null);
  assert.equal(toMinor(''), null);
  assert.equal(toMinor('1,000.00'), null);
  assert.equal(toMinor('abc'), null);
  assert.equal(toMinor('1e5'), null);
  assert.equal(toMinor('99999999999999999999'), null);
});

test('account numbers keep only the last four digits', () => {
  assert.equal(maskAccountNumber('063000 1234 1965'), '•••• 1965');
  assert.equal(maskAccountNumber('xxxx-xxxx-8802'), '•••• 8802');
  assert.equal(maskAccountNumber(undefined, '600000157441965'), '•••• 1965');
  assert.equal(maskAccountNumber('xxxx', '12'), '••••');
});
