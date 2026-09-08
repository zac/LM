# Solid console enclosure phase

Authorized after user review of exposed instrument housings and skeletal framing. Baselines: LMKit main 70c0914; LM cockpit/integration 471b473. This phase prioritizes large solid forms and embedded mounting before additional controls or small decorative details.

## Ownership

- InstrumentConsole: Panel1/2/3 faces, FDAI recesses and enclosed central-console sides.
- LowerConsole: Panel4/5, fitted DSKY opening and enclosed controller/lower-console volumes.
- WindowSurrounds: forward window reveals and solid sidewall transitions; preserve panes and LPD.
- WindowsLPD follow-up: independently verify marking placement/orientation against source evidence and correct supported mismatches; preserve opening/pane datums.
- Coordinator: package APIs/resources, combined assembly and publication.
- Runtime worker: qualified transactional replacement, fallback and native simulator acceptance.

Each modeling worker owns its new component directory on an isolated branch. Original mounts and live instrument semantics remain fixed. Replacements must name exact existing visual nodes; successful loading and validation precede suppression. Geometry is a provisional visual approximation, not mechanical or mission-specific qualification.

## Acceptance

Review both crew positions and oblique views: no exposed instrument backs, floating bezels or unintended console gaps. Solid blank faces are acceptable for unfinished equipment. Preserve intentional center/hatch openings, window apertures, controller reach and all existing live inputs. Validate the combined geometry, byte-identical resource packaging, native loading and relevant app regression tests. Retain screenshots with exact source revisions. Physical Vision Pro acceptance is separate.

## Progress

All three enclosure deliveries and the LPD placement correction are merged with original worker history. Combined geometry clears the resolved lamp/timer/console/breaker incursions, all sampled sightlines and 125 ACA poses; see Docs/Validation/SolidConsole/CombinedGeometry/REVIEW.md. Runtime integration is implemented, with native package and simulator acceptance pending.

The user explicitly added the window-marking audit while enclosure work was in progress. This runs on an isolated WindowsLPD branch alongside WindowSurrounds; reference placement and optical calibration must be distinguished.
