/// Basiq sends amounts as decimal strings ("420.28", "-12.5", "1000"). They are
/// turned into whole cents with string arithmetic — never through a float,
/// where 0.1 + 0.2 is not 0.3.
export function toMinor(amount: string | null | undefined): number | null {
  if (amount == null) return null;
  const match = /^\s*([+-])?(\d+)(?:\.(\d+))?\s*$/.exec(amount);
  if (!match) return null;
  const [, sign, whole = '0', fraction = ''] = match;
  // Round half away from zero on the third decimal, as a bank statement would.
  const cents = Number(whole) * 100 + Number(fraction.padEnd(2, '0').slice(0, 2));
  const roundUp = fraction.length > 2 && Number(fraction[2]) >= 5 ? 1 : 0;
  const minor = cents + roundUp;
  if (!Number.isSafeInteger(minor)) return null;
  return sign === '-' ? -minor : minor;
}

/// "•••• 1965" from whatever Basiq has: a masked number, a full number, or a
/// BSB and number with dashes and spaces. Only the last four digits survive.
export function maskAccountNumber(...candidates: Array<string | null | undefined>): string {
  for (const candidate of candidates) {
    const digits = (candidate ?? '').replace(/\D/g, '');
    if (digits.length >= 4) return `•••• ${digits.slice(-4)}`;
  }
  return '••••';
}
