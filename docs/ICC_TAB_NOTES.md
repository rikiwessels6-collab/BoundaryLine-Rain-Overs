# ICC Men's ODI and T20I tiles — notes (2 Nov 2026)

**Status: NOT compiled, NOT run on a device.** Syntax-only parse: 0 error nodes in both Swift files. That is not a build. App Store release remains on HOLD.

## What was added
Two new start-screen tiles, **ICC Men's ODI** and **ICC Men's T20I**, using the same tabs as the other competitions (Late start, First innings, Termination, Second start, Second interruption, Powerplays, Breaks, Summary). Source: ICC Men's ODI and T20I Playing Conditions, effective October 2026 (the two PDFs you attached).

| Item | ODI | T20I | PC reference |
|---|---|---|---|
| Net playing time | 420 min | 170 min | 12.7.1 |
| Interval | 30 min | 15 min | 11.2.1 |
| Rate for revisions | 4.2 min/over | 4.25 min/over | 13.7.2, Appendix E |
| Overs per side | 50 | 20 | 13.6.1 |
| Minimum for a result | 20 overs | 5 overs | 16.1.2 |
| Bowler limit | 10 (one-fifth, rounded up when reduced) | 4 (one-fifth; 2 for 5–9-over innings) | 13.9 |
| Powerplay | P1/P2/P3 table | overs.balls table (e.g. 16 ov = 4.5) | 28.7.2.3 / 28.7.6 |
| Calculation sheets | Appendix E Tables 1–4 | Appendix E Tables 1–4 | App. E |

The ODI powerplay table (20–49 overs) is identical to your ODC table; I checked every row. The T20I table was added new.

## Extra time (new per-match setting)
ICC extra time exists only where the participating countries agree it (ODI 13.7.3: up to 90 min; T20I 13.7.3: no cap stated). Set it in **Match Info → Extra time (ICC)** (0 to 180 min, steps of 5). It defaults to 0 and resets on every new match. It is kept through relaunch and saved matches (older saved matches load with 0). It is used first, as one pool across both innings, the same way WNCL's 60 minutes already works.

## NOT modelled (the app says so on screen)
- **DLS targets and par scores** (ICC 16.4). The app gives overs and times only.
- **ICC over-rate penalty offsets** (13.8). The over-rate cut-off row is hidden for ICC matches.
- **Match Referee's discretion to shorten the interval** (ODI 11.4.1 note, T20I 11.4.2; minimum 10 min). The interval is never reduced automatically; if it is reduced, the T20I rule 11.4.3 adjustment has to be handled by you.
- **T20I drinks break** (2 min 30 s per innings, where agreed).
- **Latest-permissible-start** for ICC matches: the ICC PCs give no such rule, so the CA-specific block is hidden for ICC.
- Women's ICC conditions were not provided; the tiles are labelled Men's.

## Tests
`BoundaryLineSelfTests.swift` (the ICC version replaces the earlier one) has a new ICC group of 27 checks (77 call sites in the whole file). Expected values come from `verification/icc_expectations.py`, which is written from the Appendix E worksheet formulas, not from the Swift code. Examples: ODI 45 min lost = 89.29 → 45 overs a side (60 min agreed extra time → 50); T20I 30 min lost = 32.94 → 17; ODI second innings 30 min lost → 43; T20I 17 min lost → 16.

## Known edge to check
App computes overs from the unrounded G ÷ rate; the worksheet says "to 2 decimal places" first. These can differ only at a razor-thin boundary (for example 44.002 vs 44.00). This exists for the other competitions too.

## Install on iPad
Replace your main file with `BoundaryLineRain_AuditPatched_ICC_UNVERIFIED.swift` and your tests file with `BoundaryLineSelfTests.swift` (both are supersets of the previous pair). Build, then About → Run self-tests. To enable the in-app PDF library for ICC, add the two PDFs to the project renamed exactly `ICC Men's ODI Playing Conditions 2026.pdf` and `ICC Men's T20I Playing Conditions 2026.pdf`.
