# Combined enclosure geometry review

Final reviewed WindowSurrounds candidate is clear of the identified cross-component blockers. This is source/USD geometry acceptance; native scene lighting, head movement, readability and historical/mechanical qualification remain separate.

## Exact assets

| Component | SHA-256 of reviewed USDZ |
|---|---|
| InstrumentConsole (`b6d2712d885a0ff69896f4efa8d352e978cdf4a5`) | `27a29aee1d909d482b0a4edcca5fbdf1ba227bebcb85bcee1c94405ac1475b26` |
| LowerConsole (`d15b4fb2b187c37d7ef8f5cded2288f46bf59700`) | `8ee9a28d08735a225c081e96509b611cdaf552f6af8f59d7ed7ca6874d4bc4f0` |
| WindowSurrounds (stable final candidate; commit owned by worker) | `1c5e9057ed75469edc3d63524680cada285b14ca6143acd7cc82f58a761ce9a6` |
| Corrected packaged WindowsLPD (main includes `f5824e4`) | `a9a8cc1fd43f5c95a3be729d44afbe8704f07ac551cea9e1518479b96e0c9c18` |

`report.json` includes input interface/build hashes and confirms unchanged inputs during the run. `packaged-windows-report.json` and `breaker-report.json` identify their exact peer resources. All geometry uses raw USD points and accumulated transforms in the common identity Cabin frame, avoiding Blender import correction ambiguity.

## Results

- Zero triangle surface crossings between the three enclosure assets.
- Zero enclosure crossings with corrected packaged WindowsLPD or the accepted BreakerBanks asset.
- 1,560 sampled rays through the two actual window triangles clear. The focused packaged-Windows check repeats this same ray set against the packaged interface; it is not an additional independent sample population.
- 13 actual mounted instrument face targets clear, including both FDAIs and pilot lunar contact. The component worker supplies a broader 79-face check separately.
- 25 DSKY opening rays clear.
- 125 sampled ACA poses spanning -11, -5.5, 0, 5.5 and 11 degrees on all three presentation axes: no enclosure crossings. This is a sampled presentation check, not continuous articulation or human reach qualification.
- All three interfaces are identity Cabin roots. Their 22 / 4 / 38 suppression entries are disjoint.

## Resolved findings and retained contacts

The initial WindowSurrounds draft blocked the pilot contact lamp, crossed the mission timer lens/readout/mounting face, and intruded into the console skins up to 19.5 mm inside the upper edge and 29–72 mm inside Panel 3's edge. The retained `report-before-surround-fix.json` records those failure locations. The final candidate clears these surfaces and rays. Breaker reliefs now have opaque rear sheets rather than leaving open mounting gaps; all breaker mesh crossings clear in the independent final check.

An apparent initial ACA collision in the worker's Blender-import audit was a basis-conversion error: raw mounted USD bounds are Y 0.9075–1.163 m and Z -0.45495–-0.28505 m. The controller itself was not moved or trimmed.

Two mission-timer **rear housing** intersections with InstrumentConsole front skins remain; its lens, readout backing and mounting face do not intersect any new enclosure. These are hidden mounting contacts, not a new visible hardware obstruction. The existing rear FDAI/enclosure seating through the provisional pressure-shell volume remains mechanically unqualified. Upper/lower joint geometry preserves the explicitly agreed approximately 1.156 mm seam. Intentional mounting contacts and existing rear pressure-shell seating are not classified as automatic blockers.

The window worker separately reports residual pressure-wall seam/registration pairs, planning-frame/backing contacts and two header-return bolt contacts. This review does not turn those into historical fit qualification or assert a globally watertight pressure vessel.

## Reproduction

The scripts write only this audit directory and do not modify peer sources:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
  -P /private/tmp/lm-solid-console-combined/audit.py \
  -P /private/tmp/lm-solid-console-combined/windows_audit.py \
  -P /private/tmp/lm-solid-console-combined/breaker_audit.py
```

No simulator, native build, render, asset edit or repository mutation was performed by this reviewer. Finite geometry samples cannot establish every possible crew viewpoint; coordinator acceptance should inspect the combined commander/pilot views and oblique mounting seams in the native scene.
