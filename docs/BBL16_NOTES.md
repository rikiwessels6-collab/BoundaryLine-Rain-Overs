# BBL|16 (2026/27) update — notes, 21 Nov 2026

**Status: NOT compiled, NOT run on a device.** Syntax-only parse: 0 error nodes. That is not a build. App Store release remains on HOLD.

Source: 2026/27 BBL Playing Conditions, 1 December 2026 ("BBL|16"), read against the app's existing BBL constants.

## Unchanged (matches the new conditions)
4.0 min/over (13.7.2.1.1) · 160 min net (App. J.1, 2 × 80 min per 12.5.1) · 15-min interval (11.2.1) · no extra time (12.6) · 20 overs, minimum 5 (13.1, 16.1.2) · bowler limits (13.8) · Appendix J.1 worksheets · powerplay/surge table (28.7.4), all rows 20 to 5 compared · reduced-innings rounding.

## CHANGED
| Item | Was (2025/26) | Now (BBL|16) | Clause |
|---|---|---|---|
| In-game over-rate finish time, full innings | 79 min | **84 min** | 12.7.1 |
| Reduced innings | (overs − 1) × 4 + 3 | **overs × 4 + 3** | 12.7.1 |
| e.g. 15 overs | 59 | **63** | |
| e.g. 10 overs | 39 | **43** | |
| Version label and PDF name | 2025/26 | 2026/27 (BBL|16, 1 Dec 2026) | |
| On-screen "2025/26" banner | shown | removed | |

## Open points
1. **Interval reduction boundary (settled by you).** BBL 11.3.3 says "after 21 minutes"; WBBL says "after 16 or more". You confirmed BBL follows the WBBL convention, so 21 minutes lost cuts the interval to 10. The app does this and the self-test now checks 20 → 15, 21 → 10, 22 → 10. The clause itself doesn't say "or more".
2. **One-over allowance, 12.8.2.6.** In reduced-overs matches the fielding side gets a 1-over allowance when over rate is calculated. 12.7.1 also says 12.8.2.6 "shall also apply on the start or recommencement of play". I show the plain overs × 4 + 3 figure and add a short on-screen note rather than adding 4 minutes myself.

## Not checked / not changed
- BBL team and venue lists are still the 2025-26 lists. The conditions don't give them.
- The 90-second drinks break and the no-drinks rule for innings of 15 overs or fewer (11.4) are not modelled by the app.
- The BBL PCs mention an Opening Match in Chennai with its own extra-time rules (12.6, Appendix N). The app has no tile or setting for it.
- Over-rate fines and strikes (12.8.6 onwards) are not calculated.
- BBL latest-start is derived from minimum overs (5 × 4 min, a 10-min interval), not from a CA almanac example (only WBBL has one).

## Tests
`BoundaryLineSelfTests.swift` has a new BBL group of 10 checks (the interval check now includes the 21-minute boundary). Expected values are from `verification/bbl_expectations.py`, worked from Appendix J.1 and the clause text: 30 min lost → H 33.75 → 17 overs a side; second innings 17 min lost → 16 overs (17 with 5 min early-start credit); finish times 84 / 63 / 43.

## Install
Replace the main file with `BoundaryLineRain_AuditPatched_ICC_BBL26_UNVERIFIED.swift` and the tests file with `BoundaryLineSelfTests.swift`. Both are supersets of the ICC pair. Use one `@main` only and paste into an empty file. Rename the BBL PDF `BBL Playing Conditions 2026-27.pdf` if you want it to open from the in-app library.
