import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/preloaded_data.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/service/pikafish_nnue_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

ProviderContainer makePikafishContainer({required Directory? appSupportDirectory}) {
  final container = ProviderContainer(
    overrides: [
      preloadedDataProvider.overrideWith((ref) {
        return (
          sri: 'test-sri',
          packageInfo: PackageInfo(
            appName: 'lichess_mobile_test',
            version: '0.0.0',
            buildNumber: '0',
            packageName: 'lichess_mobile_test',
          ),
          deviceInfo: BaseDeviceInfo({'name': 'test'}),
          authUser: null,
          engineMaxMemoryInMb: 256,
          appDocumentsDirectory: null,
          appSupportDirectory: appSupportDirectory,
        );
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<Directory> makeTempDir() async {
  final dir = await Directory.systemTemp.createTemp('pikafish_nnue_test_');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nnueFile points at the network inside the app support directory', () async {
    final dir = await makeTempDir();
    final service = makePikafishContainer(appSupportDirectory: dir)
        .read(pikafishNnueServiceProvider);
    expect(service.nnueFile.path, '${dir.path}/pikafish/pikafish.nnue');
    // Not in the app support directory itself, where Stockfish's networks live and where
    // StockfishNnueService lists *.nnue files to offer deleting them.
    expect(service.nnueFile.parent.path, isNot(dir.path));
  });

  test('nnueFile throws when there is nowhere to write the network', () {
    final service = makePikafishContainer(appSupportDirectory: null)
        .read(pikafishNnueServiceProvider);
    expect(() => service.nnueFile, throwsA(isA<Exception>()));
  });

  // The one test that proves the network in the bundle is the network the engine was built against:
  // Pikafish takes any file here without complaint and plays noise with it, so a mismatched or
  // truncated asset is not a crash anywhere, it is a computer that cannot play.
  test('writes the bundled network out, whole and unchanged', () async {
    final dir = await makeTempDir();
    final service = makePikafishContainer(appSupportDirectory: dir)
        .read(pikafishNnueServiceProvider);

    final path = await service.ensureNnue();
    expect(path, service.nnueFile.path);
    final file = File(path);
    expect(await file.exists(), isTrue);
    expect(await file.length(), kPikafishNnueSize);

    // Hashed rather than compared to the asset: the asset is what was copied, so comparing the two
    // would only prove the copy was a copy. The constant is what the vendored Pikafish expects.
    final digest = await _sha256Of(path);
    expect(digest, kPikafishNnueSha256);
  });

  test('leaves a file of the right size alone, rather than hashing 48 MB every time', () async {
    final dir = await makeTempDir();
    final service = makePikafishContainer(appSupportDirectory: dir)
        .read(pikafishNnueServiceProvider);

    // Content that is not the network, at the network's size: what an already-written file is taken
    // at its word for. Stated as a test because it is a choice — the checksum is spent on the write,
    // and what can happen to the file afterwards is truncation or deletion, which the size catches.
    final file = service.nnueFile;
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(kPikafishNnueSize, 0), flush: true);
    final before = await file.lastModified();

    expect(await service.ensureNnue(), file.path);
    expect(await file.lastModified(), before);
  });

  test('writes the network again when what is on disk is not whole', () async {
    final dir = await makeTempDir();
    final service = makePikafishContainer(appSupportDirectory: dir)
        .read(pikafishNnueServiceProvider);

    final file = service.nnueFile;
    await file.parent.create(recursive: true);
    await file.writeAsBytes(const [1, 2, 3], flush: true);

    expect(await service.ensureNnue(), file.path);
    expect(await file.length(), kPikafishNnueSize);
    expect(await _sha256Of(file.path), kPikafishNnueSha256);
  });

  test('two callers writing at once share one write', () async {
    final dir = await makeTempDir();
    final service = makePikafishContainer(appSupportDirectory: dir)
        .read(pikafishNnueServiceProvider);

    final both = await Future.wait([service.ensureNnue(), service.ensureNnue()]);
    expect(both, [service.nnueFile.path, service.nnueFile.path]);
    expect(await File(both.first).length(), kPikafishNnueSize);
  });
}

Future<String> _sha256Of(String path) async {
  final bytes = await File(path).readAsBytes();
  return sha256.convert(bytes).toString();
}
