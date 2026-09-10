# Existing signal audit

Read-only source audit, not a runtime test. Exact source revisions and inspected bytes are preserved in evidence/runtime-sources.json. No LM/AGC/LMCore code was edited. No new alarm aggregate, power bus, circuit, sensor or switch behavior was synthesized.

| Signal / capability | Verified existing path | Suitability for these physical faces |
|---|---|---|
| Raw AGC computer warning | AGCEngine.DSKYFlags.agcWarning = octal000001; AGCEngineRuntimeIO.updateDSKY sets it when warningFilter exceeds threshold. DSKYSnapshot.channel163 retains raw channel bits. LM PoweredDescentSession.dsky returns snapshot.agc.dsky. | Available candidate: `(session.dsky?.channel163 ?? unavailable) & 0o1`. Missing snapshot is unavailable, not known dark. **Not accepted as a complete Panel1 LGC lamp mapping.** |
| DSKY TEMP, GIMBAL LOCK, RESTART, PROG, etc. | DSKYSnapshot.indicators, decoded by DSKY.swift and already presented by LMPhysicalDSKYPresentation. | Supported for existing DSKY. Their names or AGC alarm programs do not establish hardware CWEA conditions and must not be copied wholesale into this array. |
| Raw AGC channel inspection | AGCSnapshot exposes inputChannels, outputChannels and channelTrace; DSKYSnapshot exposes channel163 separately. | Observation infrastructure exists. Exact electrical routing/polarity, failure signals, delays, reset and power conditions still require a reviewed mapping. |
| LM training hard-landing warning | LMCockpitExperienceDirector emits an application `.warning` cue for `.hardLanding`. | Training/audio feedback only. Does not establish MASTER ALARM or a caution-array sensor input. |
| Lunar probe contact | LMCore landingGear.isProbeContact is separately available and reviewed in the contact lane. | Belongs to LUNAR CONTACT faces owned by EngineControls, not these arrays. Never substitute landed, outcome, footpad or generic surface contact. |
| 31 named C/W cells and master alarm aggregate | No implemented CWEA sensor array, master-alarm latch/acknowledge, bus-power/brightness model or hardware C/W lamp-test selector was found in the inspected LM/LMCore/AGC sources. | **All remain unbound.** Do not manufacture alarm thresholds from fuel mass, altitude or vehicle outcome. Master-alarm push cannot be mapped to DSKY RSET without actual source-backed logic. |

The AOH excerpt explains that LGC power failure also displays on the Panel1 LGC warning light (retained PanelInventory excerpt p7, original PDF121; printed2.1-77). The computer warning flag alone therefore cannot prove complete historical LGC-lamp behavior. That circuit and the corresponding master-alarm routing must be researched before turning a possible input into a binding.

The handbook's Panel3 LAMP/TONE selector separately tests MASTER ALARM tone/lamps and C/W banks; this is not equivalent to AGC V35/DSKY lamp test. The neutral model intentionally contains no emitter or all-lamps-on test state. A future coordinator may change individual Lens/Legend ModelComponents after signal/power qualification; there is no baked electrical behavior here.

Current replay/older snapshots should retain unavailable states rather than reconstruct unavailable CWEA states. A geometrically addressable lamp is not a modeled system. No Vision Pro, simulator, signal injection or replay qualification is claimed by this audit.
