"""Two hosted image releases can contain exactly the same test renderer."""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import xiangqi_visual_runtime as renderer


class RendererIdentityTests(unittest.TestCase):
    def test_host_label_can_change_but_linked_library_content_cannot(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            engine = root / 'bin/cache/artifacts/engine/linux-x64'
            engine.mkdir(parents=True)
            for name in ['flutter_tester', 'icudtl.dat']:
                (engine / name).write_bytes(name.encode())
            fonts = root / 'bin/cache/artifacts/material_fonts'
            fonts.mkdir()
            for name in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'MaterialIcons-Regular.otf']:
                (fonts / name).write_bytes(name.encode())
            (root / 'scripts').mkdir()
            (root / 'scripts/desktop-test-fonts.json').write_text('{"fonts":[]}')
            (root / 'pubspec.lock').write_text('locked')
            library = root / 'libtest.so.1'
            library.write_bytes(b'original')

            def output(argv, **kwargs):
                if argv[0] == 'flutter':
                    return json.dumps({'frameworkRevision': 'fixed', 'engineRevision': 'fixed'})
                self.assertEqual(argv[0], 'ldd')
                return f'linux-vdso.so.1 (0xf)\nlibtest.so.1 => {library} (0x1)\n'

            with patch.dict(os.environ, GITHUB_ACTIONS='true', FLUTTER_ROOT=temp, ImageVersion='one'), \
                    patch.object(renderer.subprocess, 'check_output', side_effect=output):
                first = renderer.runtime(root, fonts)
                os.environ['ImageVersion'] = 'two'
                self.assertEqual(first, renderer.runtime(root, fonts))
                library.write_bytes(b'different')
                self.assertNotEqual(first, renderer.runtime(root, fonts))

    def test_unresolved_libraries_are_reported(self):
        with patch.object(renderer.subprocess, 'check_output', return_value='libfoo.so => not found\n'):
            with self.assertRaisesRegex(ValueError, 'libfoo.so'):
                renderer.linked_libraries(Path('/unused/flutter_tester'))
