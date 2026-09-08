#!/usr/bin/env python3
"""Pin overlapping, fixed-record LOLA strips without bundling the source raster."""
import argparse
import hashlib
import json
import pathlib

IMAGE_SHA256 = '0ab81a3e8d20e5528a21bc6c994974726cb486198013085f4c423c86fbd1154b'
LABEL_SHA256 = '85b1901def6901ee8a50415384f17a71e773af2d979beb7245fd6ac4d5e1671b'
SOURCE_BYTES = 2_123_366_400
ROW_BYTES = 92_160
ROWS = 23_040
CORE_ROWS = 32


def generate(image, label):
    assert image.stat().st_size == SOURCE_BYTES, 'Source size changed'
    digest = hashlib.sha256()
    with image.open('rb') as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            digest.update(block)
    assert digest.hexdigest() == IMAGE_SHA256, 'Source digest changed'
    assert hashlib.sha256(label.read_bytes()).hexdigest() == LABEL_SHA256, 'Label changed'
    hashes = []
    with image.open('rb') as stream:
        for first_core in range(0, ROWS, CORE_ROWS):
            first = max(0, first_core - 1)
            last = min(ROWS - 1, first_core + CORE_ROWS)
            stream.seek(first * ROW_BYTES)
            slab = stream.read((last - first + 1) * ROW_BYTES)
            hashes.append(hashlib.sha256(slab).hexdigest())
    return {
        'schemaVersion': 1,
        'generatorVersion': 'pinned-lola-latitude-strips-v1',
        'productID': 'LDEM_128', 'productVersion': 'V3.0',
        'url': 'https://imbrium.mit.edu/DATA/LOLA_GDR/CYLINDRICAL/IMG/LDEM_128.IMG',
        'labelURL': 'https://imbrium.mit.edu/DATA/LOLA_GDR/CYLINDRICAL/IMG/LDEM_128.LBL',
        'labelFile': 'LDEM_128.LBL', 'labelSHA256': LABEL_SHA256,
        'sourceSHA256': IMAGE_SHA256, 'sourceBytes': SOURCE_BYTES,
        'rows': ROWS, 'rowBytes': ROW_BYTES, 'pixelsPerDegree': 128,
        'coreRows': CORE_ROWS, 'haloRows': 1,
        'postSpacingMeters': 236.9011751886625, 'residualCapRatio': 0.12,
        'detail': 'LOLA source-grid heights, including interpolated gaps. The source label warns of possible artifacts at 45-degree latitude-band boundaries. No source posts are altered by strip generation.',
        'sha256': hashes,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', type=pathlib.Path, required=True)
    parser.add_argument('--label', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[2] / 'Packages/LunarMap/Sources/LunarMap/Resources/Terrain/LunarElevationStrips.json')
    parser.add_argument('--dry-run', action='store_true', help='Print the output path without reading sources or writing assets')
    args = parser.parse_args()
    if args.dry_run:
        print(args.output.resolve())
        raise SystemExit(0)
    catalog = generate(args.image, args.label)
    payload = (json.dumps(catalog, sort_keys=True, separators=(',', ':')) + '\n').encode()
    args.output.write_bytes(payload)
    print(f'{len(catalog["sha256"])} strips; {len(payload)} catalog bytes; SHA-256 {hashlib.sha256(payload).hexdigest()}')
