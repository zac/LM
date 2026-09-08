# Enclosed interior and replaceable equipment phase

Authorized 2026-09-08. Starting references: LMKit `86aa71b4b9ed203f11e8b572e23da2b0285a0ad8`, LM `11f7335b73884ce8dd8ebe33583f666e2b329c72`, AGC/LMCore `b3f15533db335ee882dc07401790c93010809e8f`.

## User direction

Create a credible, visually enclosed cabin with blank, labeled panel sections. Completed equipment replaces its corresponding placeholder while working instruments remain installed. Existing LPD assumptions are not authoritative. Approximate geometry is acceptable at this stage when its appearance is closer to the real hardware. Review the conspicuous magenta/green markings and remove the digital LPD indicator from the normal historical cockpit view. Do not preserve questionable geometry merely because existing code calls it calibrated.

The earlier proposal to freeze all existing LPD optical geometry is superseded. Preserve its baseline as comparison evidence, classify assumptions and change them when justified. Do not change flight dynamics to compensate for revised graphics.

## Ownership and dependencies

| Worker | Owned area | Deliverable |
|---|---|---|
| Cabin foundation | `Assets/Cockpit/Components/Cabin/` | Evolved enclosed shell/deck/ceiling/forward/aft interior, closed hatch surfaces and cutaway groups; coordinated window openings and mounting datum |
| Windows and LPD | `Assets/Cockpit/Components/WindowsLPD/` | Fresh evidence audit, credible frames/seals/panes/markings, versioned optical/layout interface and migration notes |
| Panel inventory | `Assets/Cockpit/Components/PanelInventory/` | Source-backed panel/region inventory, shaped blank placeholders, separate readable review labels and replaceable slot manifest |
| Historical cockpit presentation (LM) | Training/LPD presentation code and focused tests | Normal view without digital angle marker/readout and diagnostic color aids; explicit optional training aids retained separately where useful |
| Coordinator | Shared LMKit resources/APIs/tests/tools and LM master assembly | Review contracts, package components, replace old surfaces once, integrate placeholders and working equipment, combined validation |

All workers use isolated local worktrees. Existing instruments, surrounds, controllers, simulation repositories and other workers' binaries are read-only inputs. Preserve delivered history and LFS assets. One heavy render/bake and one simulator test/capture job per machine; lightweight independent authoring is allowed.

Windows and foundation must exchange a small versioned datum/outline contract before final geometry. Source-supported revisions to eye/pane geometry may require changes in both components and LM; coordinator reconciles them. Panel inventory starts from evidence and declares parent-local versus Cabin-relative poses explicitly; it can research and author independent placeholders before the final mounting pass. Workers send early interface decisions to the coordinator rather than reading uncommitted peer files.

## Assembly behavior

- Provide a coherent interior seen from both stations and rear-facing views. Close accidental holes; retain actual window apertures and separately addressable hatch leaves. This is visual enclosure, not certified pressure-vessel or hatch-mechanism engineering.
- Preserve metric unit scale and one explicit cabin datum. Use evidence to reconcile shell depth, floor level, standing positions, windows, panel boundaries and access space. Record approximate dimensions and source applicability.
- Each panel and each replaceable instrument region has a stable ID, face datum, envelope, parent, source/confidence, status and placeholder node. Numbering must follow actual references; ambiguous regions get descriptive provisional IDs, not invented flight numbers.
- Keep frame/surround, placeholder, planning label and installed equipment separate. A successfully loaded component hides only its placeholder. Failed/missing component load retains the blank. Working DSKY/FDAI/ACA and their identities must survive replacement.
- Planning labels are a separately switchable inspection layer. They identify the intended equipment and development status; they are not simulated flight placards or controls. Normal historical presentation hides development labels and electronic training indicators.
- Do not duplicate LPD marks between LM-generated geometry and imported assets. Document which representation owns them at each stage. Keep graphical LPD appearance separate from AGC numeric readouts on the actual DSKY.
- Preserve access to useful training/recenter/navigation controls as app UI. Diagnostic overlays must not be mistaken for flight hardware or enabled by default in the historical view.

## Acceptance

Workers deliver reproducible Blender source, neutral USDZ, evidence with URLs/pages/photo crops and hashes, interfaces, validation and handoff. Required visual reviews include front, side, commander eye, pilot eye, rear and overhead/cutaway views; windows include closeups against source photos. Distinguish approximate appearance acceptance from surveyed optical calibration.

Coordinator verifies no double shell/windows/LPD/instruments, correct placeholder substitution/fallback, visible enclosure, instrument sightlines, rough controller/panel clearance and normal-view overlay suppression. Run native package tests and serial visionOS integration tests/captures on exact pinned revisions. Promote the enclosed assembly to the normal interior only after combined review; keep a fallback for asset failures. Physical headset gaze/pinch, stereo, reach, photometry and performance remain separate acceptance work when a headset is available.

This document starts the phase; it does not claim any of these new deliverables or physical checks are complete.
