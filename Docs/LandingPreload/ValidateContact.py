"""Compile the production contact sampler in isolation; no app or simulator.
External terrain/simulation interfaces are stubs. This checks interpolation,
not a complete simulation or renderer. Run from the LM repository root.
"""
from pathlib import Path
import subprocess, tempfile
source = Path("Packages/LunarMap/Sources/LunarMap/LMTerrainLandingSurface.swift").read_text().split("/// Builds the contact patch")[0]
source = source.replace("import LMCore", "")
stubs = r"""
struct LMVector3D { var x: Double; var y: Double; var z: Double }
protocol LMLandingSurfaceModel {}
protocol LMTerrainHeightField { func relativeElevation(eastMeters: Double, northMeters: Double) -> Float? }
struct LMTerrainFrameAlignment { func terrainPosition(from p: LMVector3D) -> LMVector3D { p } }
struct LMLunarTerrainMeshSnapshot {
    struct Sample { var elevation: Float }
    func sample(east: Double, north: Double) -> Sample? { nil }
}
struct Field: LMTerrainHeightField {
    func relativeElevation(eastMeters: Double, northMeters: Double) -> Float? { 17 }
}
"""
checks = r"""
// Deliberately non-planar quad: a bilinear sampler would give wrong heights.
let surface = LMTerrainContactSurface(cornerEastMeters: 0, cornerNorthMeters: 2,
    spacingMeters: 2, columns: 2, rows: 2, heights: [0, 2, 4, 10],
    heightField: Field(), alignment: nil, referenceElevationMeters: 7)
let cases: [(Double, Double, Double)] = [
    (2, 0, 0), (2, 2, 2), (0, 0, 4), (0, 2, 10),
    (1.5, 0.5, 1.5), (0.5, 1.5, 6.5), (1, 1, 3), (3, 3, 10)
]
for (north, east, expected) in cases {
    let actual = surface.surfaceHeightMeters(northMeters: north, eastMeters: east)
    precondition(abs(actual - expected) < 1e-6, "contact mismatch: \(actual) vs \(expected)")
}
print("PASS: 8 production contact-sampler checks (corners, both triangles, seam, fallback datum)")
"""
with tempfile.TemporaryDirectory(prefix="lm-contact-") as directory:
    path = Path(directory)
    (path / "main.swift").write_text(stubs + source + checks)
    subprocess.run(["swiftc", "-module-cache-path", str(path / "cache"), str(path / "main.swift"), "-o", str(path / "check")], check=True)
    subprocess.run([str(path / "check")], check=True)
