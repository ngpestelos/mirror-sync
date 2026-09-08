import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = (ROOT / '.github/workflows/sync.yml').read_text()
SCRIPT = textwrap.dedent(WORKFLOW.split("python3 - << 'PY'\n", 1)[1].split('\n          PY', 1)[0])
CATALOG = (ROOT / 'mirrors.yml').read_text()


def matrix(catalog, only=''):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory)
        (path / 'mirrors.yml').write_text(catalog)
        output = path / 'output'
        subprocess.run(
            [sys.executable, '-c', SCRIPT], cwd=directory, check=True,
            env={**os.environ, 'ONLY': only, 'GITHUB_OUTPUT': str(output)},
            capture_output=True, text=True,
        )
        return json.loads(output.read_text().removeprefix('batches='))


def destinations(batches):
    return {entry['dest']: batch['id'] for batch in batches for entry in batch['entries']}


def grown_catalog(total):
    count = len(re.findall(r'^  - dest:', CATALOG, re.MULTILINE))
    return CATALOG + ''.join(
        f'  - dest: regression-added-{i}\n    src: example/repo-{i}\n'
        '    default: main\n    timeout: 60\n'
        for i in range(total - count)
    )


class SyncMatrixTest(unittest.TestCase):
    def test_coverage_and_existing_batch_ids(self):
        for total in (480, 575, 606):
            with self.subTest(total=total):
                catalog = grown_catalog(total)
                batches = matrix(catalog)
                entries = [entry for batch in batches for entry in batch['entries']]
                expected = re.findall(r'^  - dest: (.+)$', catalog, re.MULTILINE)
                self.assertCountEqual([entry['dest'] for entry in entries], expected)
                self.assertLessEqual(len(batches), 256)
                for batch in batches:
                    for entry in batch['entries']:
                        if entry['timeout'] >= 90:
                            self.assertEqual(batch['id'], f"heavy-{entry['dest']}")
                            self.assertEqual(len(batch['entries']), 1)
                        else:
                            bucket = int(hashlib.sha256(entry['dest'].encode()).hexdigest(), 16) % 3
                            self.assertEqual(batch['id'], f'normal-{bucket}')

    def test_catalog_growth_preserves_existing_locks(self):
        before = destinations(matrix(grown_catalog(575)))
        after = destinations(matrix(grown_catalog(606)))
        moved = [dest for dest, lock in before.items() if after[dest] != lock]
        self.assertEqual(moved, [], f'{len(moved)} existing destinations changed locks')

    def test_manual_dispatch_keeps_full_run_lock(self):
        catalog = grown_catalog(606)
        for batch in matrix(catalog):
            dest = batch['entries'][0]['dest']
            selected = matrix(catalog, only=dest)
            self.assertEqual(destinations(selected), {dest: batch['id']})
            self.assertEqual(sum(len(b['entries']) for b in selected), 1)


if __name__ == '__main__':
    unittest.main()
