# Bounded Vision Pro acceptance checklist

Use the reviewed worker/integration build with LMKit 75bdea77b57e0ae4971bb4ffbee21c4643e3b4cf and AGC b3f15533db335ee882dc07401790c93010809e8f. Record source SHA, app hash, device UDID, OS, entry eye/recenter transform and input method. Do not change account, device security or developer settings to run this check.

1. Enter the commander station in the real P64 scenario with scripted validation inputs disabled. Confirm one imported DSKY and one imported FDAI. Record baseline P64 V06 N64 and a screenshot/video.
2. Gaze at VERB and pinch/release, then select 1, 6, NOUN, 3, 6, ENTR. Each completed pinch must produce exactly one production completion event, retain FIFO order, and produce live V16 N36. Hover alone must not enqueue.
3. After VERB, select adjacent 7 then 8 individually and verify the displayed entry is 78 without a neighboring-key substitution. Clear/restart the entry with the real DSKY controls; use VERB 1 6 NOUN 3 6 ENTR to return to the monitor.
4. Select PRO and release. Verify one bounded PRO down/up pulse and return to V06 N64. Repeat two completed PRO taps; both must be retained. The implementation is a completed-tap pulse, not press-and-hold semantics.
5. Start a pinch at PRO, move away enough to cancel, and release. Verify no completed callback or pulse. During a completed PRO pulse, stop the session and verify release, with pending queued events discarded. Native queue cancellation tests support this, but do not replace this device check.
6. Enter VERB 3 5 ENTR for the live AGC lamp test; inspect white/amber legends, COMP ACTY, digits and signs. Reset with RSET. Off lamps must be distinguishable from on lamps. Read all key labels at the intended eye pose, including adjacent keys, without changing instrument scale.
7. Observe the FDAI through live attitude motion: housing and fixed index stay still while the ball moves. No unsupported rate/error needles or duplicated face should appear.

Record failures and missed/extra key events. These checks do not establish historical brightness, stereo comfort across users, calibrated photometry, mechanical fit or frame-time qualification; those require separate measurements.
