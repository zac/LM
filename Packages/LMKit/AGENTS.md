# LMKit work

This is the internal asset package at `Packages/LMKit` in the LM repository.
Run component authoring, resource sync and package tests from this directory.
Do not require a sibling LMKit checkout or copy changes back to the historical
standalone repository. Original commit provenance remains in Git history.

LMKit owns model assets, authoring tools and resource APIs. AGC and LMCore own simulation; do not duplicate their behavior here. Each component worker owns only its assigned Assets/Cockpit/Components directory. The coordinator owns Sources, Tests, Tools and master assembly. Keep moving parts independently addressable and preserve source evidence. Do not infer live bindings from geometry names. Use Git LFS for Blender and USD files. Preserve original commit provenance and mark unverified dimensions. Validate packaging after refreshing runtime resources with Tools/sync_dsky.py. Do not overwrite another worker's branch or binary assets.
