# FDAI cover washout

The shared LMImportedFDAI loader now disables the cosmetic FDAI_Glass node for both commander and pilot instruments. It retains the source asset, fixed reticle, ball texture and moving hierarchy. This removes the glass overlay rather than retuning mission exposure or changing instrument data.

A headless macOS RealityKit load of the packaged FDAI found a PBR glass material with base tint RGBA (0.7, 0.85, 0.9, 0.055), transparent blending opacity scale 1.0, specular 0.5 and roughness 0.12. The authored USD opacity is 0.055. These are material inspection results, not a measured optical-opacity result; the glossy cover is a plausible source of the reported white washout.

The visionOS Simulator-targeted app build passed in the isolated validation checkout. The existing native hierarchy test now also requires the cover to be present but disabled in the imported hierarchy; app tests were not executed because the user prohibited app/simulator launches. Actual on-device appearance remains to be confirmed.
