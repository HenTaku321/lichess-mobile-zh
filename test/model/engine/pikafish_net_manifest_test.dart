import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';

/// The manifest is the one place the Pikafish network is described, and the constants in
/// `engine_utils.dart` are a second copy of two of its numbers — a copy the app needs, because the
/// size and the hash are what it checks the network it writes on first run against, and it cannot
/// read a file that only exists in the repository.
///
/// Two copies of one fact drift. This holds them together: the constants are what the app ships,
/// the manifest is what the build fetches, and if they disagree then the app is verifying a
/// network nobody downloaded.
///
/// It reads the manifest as a file rather than importing the script that consumes it, because
/// `scripts/` sits outside `lib/` and `always_use_package_imports` forbids reaching it relatively.
/// The precedent is `test/service/weights_service_test.dart`, which reads `assets/maia/...` the
/// same way.
void main() {
  group('Pikafish network manifest', () {
    late Map<String, dynamic> manifest;

    setUpAll(() {
      final file = File('scripts/pikafish-net.json');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'scripts/pikafish-net.json is the source of the URL and the checks in '
            'scripts/fetch-pikafish-nnue.sh',
      );
      final decoded = jsonDecode(file.readAsStringSync());
      expect(decoded, isA<Map<String, dynamic>>());
      manifest = decoded as Map<String, dynamic>;
    });

    test('the size the app checks against is the size the build downloads', () {
      expect(manifest['size'], kPikafishNnueSize);
    });

    test('the hash the app checks against is the hash the build downloads', () {
      expect(manifest['sha256'], kPikafishNnueSha256);
    });

    test('the hash is a lowercase sha256 and the size is plausible', () {
      // A manifest that drifted to an uppercase digest, or to a truncated file's size, would still
      // satisfy the two comparisons above if the constants drifted with it.
      expect(manifest['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(manifest['size'], greaterThan(40 * 1024 * 1024));
    });

    test('the URL is a fixed release, not a rolling one', () {
      // The whole failure this manifest exists to prevent: official-pikafish/Networks serves its
      // network from a `master-net` release whose asset is replaced in place, so a build pinned to
      // it breaks the day upstream ships a new network. A tag that cannot move is the property
      // being asserted here, and a `master-net` URL is the shape of the thing that must never
      // come back.
      final url = manifest['url'];
      expect(url, isA<String>());
      expect(url as String, startsWith('https://'));
      expect(
        url,
        isNot(contains('official-pikafish/Networks')),
        reason: 'that repository publishes a rolling release; pin a fixed tag instead',
      );
      expect(
        url,
        contains('/releases/download/'),
        reason: 'the asset should be addressed through a release tag',
      );
    });

    test('the engine commit names a vendored snapshot', () {
      final commit = manifest['engineCommit'];
      expect(commit, isA<String>());
      // The upstream Pikafish commit, not the pubspec's fork ref: the two are different commits in
      // different repositories, and the manifest has to be unambiguous about which one it means.
      expect(commit as String, matches(RegExp(r'^[0-9a-f]{6,40}$')));
      expect(commit, isNot(contains('f9dd136b')));
    });

    test('the architecture hash is written as a 32-bit literal', () {
      expect(manifest['archHash'], matches(RegExp(r'^0x[0-9A-F]{8}$')));
    });

    test('the URL points at a release on the repository the sync publishes to', () {
      // The sync republishes the network and rewrites the URL to point at the new release. If the
      // two ever disagree — a hand-edited URL left on an old host, a publishRepo changed without
      // the URL following — the build downloads one thing while the manifest describes another,
      // and nothing else here would notice.
      //
      // The tag is only checked to be a `pikafish-net-` one, not to be derived from the digest.
      // The first release was named after the engine commit (`pikafish-net-532c3ff216`) and later
      // ones after the digest; renaming the first would break the URL in an already-published
      // commit's manifest for no gain, since the fetch script verifies the bytes against `sha256`
      // either way.
      final source = manifest['source'] as Map<String, dynamic>;
      expect(
        manifest['url'],
        startsWith('https://github.com/${source['publishRepo']}/releases/download/pikafish-net-'),
      );
      expect(manifest['url'], endsWith('/pikafish.nnue'));
    });

    test('the sync looks for networks in a repository that can be read without credentials', () {
      // `fetch-pikafish-nnue.sh` downloads the asset with a plain curl, so the repository it comes
      // from has to be public. A private one would turn every build red with a 404 that reads like
      // a missing file. This cannot be checked from here — the test has no network — so what is
      // asserted is the shape: an `owner/name` pair, and the fork that is known to be public.
      final source = manifest['source'] as Map<String, dynamic>;
      expect(source['publishRepo'], matches(RegExp(r'^[^/]+/[^/]+$')));
      expect(source['publishRepo'], isNot(contains('.git')));
      expect(source['repo'], matches(RegExp(r'^[^/]+/[^/]+$')));
      expect(source['member'], 'pikafish.nnue');
      expect(source['notBefore'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('the difficulty levels are recorded as calibrated for the pinned network', () {
      // Not an assertion that they *are* calibrated — nothing can check that — but that the field
      // exists and is a digest, so that the sync's warning has something to compare against and a
      // network swap leaves a visible diff here rather than a silent one.
      expect(manifest['difficultyCalibratedFor'], matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });
}
