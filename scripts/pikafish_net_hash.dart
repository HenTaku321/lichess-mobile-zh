// Computes the architecture hash the vendored Pikafish snapshot expects a network to carry.
//
// The engine loads a network through its `EvalFile` option and compares the hash in the file's
// header against `Network::hash`, a compile-time constant derived from the engine's own headers. A
// network that does not match is not refused with a message: `Network::verify` prints five ERROR
// lines and calls `exit(EXIT_FAILURE)`, and in a library living beside a Dart VM that exit deadlocks
// the threads still waiting on the search — a hang with no message. Nothing in the test suite can
// catch it, because every engine test runs on a fake transport and every `nnuePath` in them is a
// literal that does not exist.
//
// So the pairing is checked here instead: this reads the vendored headers, recomputes the hash the
// way the compiler would, and — with `--check` — fails if it is not the one the manifest pins.
//
// It reads the headers rather than hardcoding the answer because those numbers are exactly what a
// Pikafish bump changes. Hardcoding would turn "someone changed a header" into "the script quietly
// computes the old hash and passes".
//
// Usage:
//   dart run scripts/pikafish_net_hash.dart           print the hash and what it was built from
//   dart run scripts/pikafish_net_hash.dart --check   also compare it to scripts/pikafish-net.json

import 'dart:convert';
import 'dart:io';

/// The seed `NetworkArchitecture::get_hash_value` starts from.
const _architectureSeed = '0xEC42E90Du';

/// The magic `AffineTransform` and `AffineTransformSparseInput` start from, then add their output
/// width to.
const _affineMagic = '0xCC03DAE4u';

/// The magic `ClippedReLU` and `SqrClippedReLU` start from, then add the previous hash to.
const _reluMagic = '0x538D24C7u';

void main(List<String> args) {
  final root = _repoRoot();
  final snapshot = Snapshot.of(root);

  stdout.writeln(snapshot.describe());

  if (!args.contains('--check')) {
    return;
  }

  final manifest = File('${root.path}/scripts/pikafish-net.json');
  if (!manifest.existsSync()) {
    stderr.writeln('::error::${manifest.path} is missing');
    exit(1);
  }
  final pinned = _parseIntLiteral(_stringOf(_jsonObjectOf(manifest)['archHash'], 'archHash'));
  final computed = snapshot.architectureHash;

  if (pinned != computed) {
    stderr.writeln(
      '::error::the manifest pins archHash ${_hex(pinned)}, but the vendored headers compute '
      '${_hex(computed)}.\n'
      'The engine would refuse a network carrying the pinned hash, and would do it by exiting '
      'from inside the first search.\n'
      'Either the vendored snapshot moved without the manifest, or the manifest was edited by '
      'hand. Run scripts/update-pikafish-net.sh against the network you mean to ship.',
    );
    exit(1);
  }
  stdout.writeln('manifest archHash ${_hex(pinned)} — matches the vendored headers.');
}

/// The repository root, found by walking up from this file until a directory holds both
/// `pubspec.yaml` and `scripts/`.
Directory _repoRoot() {
  var dir = File.fromUri(Platform.script).parent;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/scripts').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('no repository root above ${Platform.script}');
    }
    dir = parent;
  }
}

Map<String, dynamic> _jsonObjectOf(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw StateError('${file.path} is not a JSON object');
  }
  return decoded;
}

String _stringOf(Object? value, String key) {
  if (value is! String) {
    throw StateError('`$key` is not a string');
  }
  return value;
}

String _hex(int value) => '0x${value.toRadixString(16).toUpperCase().padLeft(8, '0')}';

int _parseIntLiteral(String text) {
  final trimmed = text.trim().replaceAll(RegExp(r'[uUlL]+$'), '');
  return trimmed.startsWith('0x') || trimmed.startsWith('0X')
      ? int.parse(trimmed.substring(2), radix: 16)
      : int.parse(trimmed);
}

/// The vendored Pikafish snapshot: its directory, and the headers the hash is built from.
final class Snapshot._(
  final Directory directory,

  /// The snapshot's directory name, e.g. `Pikafish-532c3ff216`.
  final String name,
  final _Header _common,
  final _Header _architecture,
  final _Header _transformer,
  final _Header _network,
) {
  /// Locates the snapshot through `.dart_tool/package_config.json`, which is the only thing that
  /// knows where pub put the git checkout. Android and iOS compile the same tree
  /// (`android/CMakeLists.txt` globs into the iOS directory), so one lookup covers both.
  factory of(Directory root) {
    final config = File('${root.path}/.dart_tool/package_config.json');
    if (!config.existsSync()) {
      throw StateError('${config.path} is missing — run `flutter pub get` before this script');
    }
    final packages = _jsonObjectOf(config)['packages'];
    if (packages is! List) {
      throw StateError('${config.path} has no `packages` list');
    }
    String? rootUri;
    for (final entry in packages) {
      if (entry is Map<String, dynamic> && entry['name'] == 'multistockfish_pikafish') {
        rootUri = entry['rootUri'] as String?;
        break;
      }
    }
    if (rootUri == null) {
      throw StateError('${config.path} does not resolve `multistockfish_pikafish`');
    }
    final packageRoot = rootUri.startsWith('file://')
        ? Directory.fromUri(Uri.parse(rootUri))
        : Directory('${root.path}/$rootUri');

    final sources = Directory(
      '${packageRoot.path}/ios/multistockfish_pikafish/Sources/multistockfish_pikafish',
    );
    if (!sources.existsSync()) {
      throw StateError('no vendored sources under ${sources.path}');
    }
    final snapshots = sources
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.split('/').last.startsWith('Pikafish-'))
        .toList();
    if (snapshots.length != 1) {
      throw StateError(
        'expected exactly one `Pikafish-*` directory under ${sources.path}, found '
        '${snapshots.length} — the hash is defined by one snapshot, so this is ambiguous',
      );
    }
    final directory = snapshots.single;
    final src = '${directory.path}/src';
    final common = _Header.read('$src/nnue/nnue_common.h');
    final architecture = _Header.read('$src/nnue/nnue_architecture.h');
    final transformer = _Header.read('$src/nnue/nnue_feature_transformer.h');
    // The feature transformer's dimensions are written in terms of `L1`, which lives in the
    // architecture header; the feature headers' dimensions are written in terms of the common
    // header's types. Follow both rather than special-casing the names.
    transformer.fallbacks = [architecture, common];
    return Snapshot._(
      directory,
      directory.path.split('/').last,
      common,
      architecture,
      transformer,
      _Header.read('$src/nnue/network.h'),
    );
  }

  /// The network format version the engine writes into, and expects in, a file header.
  int get networkFormatVersion => _common.resolve('Version');

  /// The architecture hash, computed exactly as `Network::hash` is:
  /// `FeatureTransformer::get_hash_value() ^ NetworkArchitecture::get_hash_value()`.
  int get architectureHash {
    // The composition is read off `network.h` rather than assumed: if the engine ever stops being
    // an xor of these two, this script must stop claiming to compute it.
    _network.require('static constexpr u32 hash =');
    _network.require(
      'FeatureTransformer::get_hash_value() ^ NetworkArchitecture::get_hash_value()',
    );

    return (_featureTransformerHash ^ _networkArchitectureHash) & 0xFFFFFFFF;
  }

  int get _featureTransformerHash {
    _transformer.require('hash = (hash << 1) | (hash >> 31);');
    _transformer.require('hash ^= component_hash;');
    _transformer.require(
      'return combine_hash({ThreatFeatureSet::HashValue, PSQFeatureSet::HashValue})',
    );
    _transformer.require('^ (OutputDimensions * 2);');

    final threat = _featureSet('ThreatFeatureSet');
    final psq = _featureSet('PSQFeatureSet');
    final outputDimensions = _transformer.resolve('OutputDimensions');

    var hash = 0;
    for (final component in [threat.hashValue, psq.hashValue]) {
      hash = ((hash << 1) | (hash >> 31)) & 0xFFFFFFFF;
      hash ^= component;
    }
    return (hash ^ (outputDimensions * 2)) & 0xFFFFFFFF;
  }

  int get _networkArchitectureHash {
    _architecture.require('u32 hashValue = $_architectureSeed;');
    _architecture.require('hashValue ^= TransformedFeatureDimensions * 2;');

    var hash =
        (_parseIntLiteral(_architectureSeed) ^
            (_architecture.resolve('TransformedFeatureDimensions') * 2)) &
        0xFFFFFFFF;

    // The order the layers are folded in is read from the body rather than assumed, and each
    // layer's output width is read from that layer's own class rather than from a template
    // argument position — `ClippedReLU`'s width is its first argument and `AffineTransform`'s is
    // its last, so any positional rule is wrong for one of them. A layer whose class is neither
    // shape below is an error, not a silently skipped step.
    for (final layer in _architecture.getHashValueLayers) {
      final declaration = _architecture.layerDeclarationOf(layer);
      final className = declaration.className;
      if (className.startsWith('AffineTransform')) {
        final width = _layerOutputDimensions(declaration);
        // `prevHash` is the value this layer was handed, not the magic-plus-width the first line
        // just computed: the layer's own hash mixes the incoming hash back in.
        final previous = hash;
        var layer = (_parseIntLiteral(_affineMagic) + width) & 0xFFFFFFFF;
        layer = (layer ^ (previous >> 1)) & 0xFFFFFFFF;
        layer = (layer ^ (previous << 31)) & 0xFFFFFFFF;
        hash = layer;
      } else if (className.startsWith('ClippedReLU') || className.startsWith('SqrClippedReLU')) {
        hash = (_parseIntLiteral(_reluMagic) + hash) & 0xFFFFFFFF;
      } else {
        throw StateError(
          '${_architecture.path}: `$layer` is a $className, whose hash this script does not know '
          'how to fold in',
        );
      }
    }
    return hash;
  }

  /// The width a layer writes out, with its template arguments bound to the parameters its own
  /// class declares.
  int _layerOutputDimensions(_LayerDeclaration declaration) {
    final layer = _LayerClass.of(directory, declaration.className);
    return layer.outputDimensions(declaration.arguments, _architecture);
  }

  /// The hash and dimensions of a feature set named by one of the architecture file's aliases.
  ///
  /// The alias is resolved rather than assumed, so swapping `ThreatFeatureSet` and `PSQFeatureSet`
  /// changes the answer instead of being missed.
  _FeatureSet _featureSet(String alias) {
    final target = _architecture.aliasTarget(alias);
    final header = _Header.read(_featureHeader(target));
    return _FeatureSet(
      name: target,
      hashValue: header.resolve('HashValue'),
      dimensions: header.resolve('Dimensions'),
    );
  }

  /// The header for a feature-set class name.
  ///
  /// Found by matching the class name against the directory listing with underscores removed and
  /// case folded — `HalfKAv2_hm` lives in `half_ka_v2_hm.h` and `FullThreats` in `full_threats.h`,
  /// and no single capitalisation rule produces both. Ambiguity is an error rather than a guess.
  String _featureHeader(String className) {
    final dir = Directory('${directory.path}/src/nnue/features');
    final wanted = className.toLowerCase().replaceAll('_', '');
    final matches = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.h')).where((f) {
      final stem = f.path.split('/').last.replaceAll('.h', '');
      return stem.toLowerCase().replaceAll('_', '') == wanted;
    }).toList();
    if (matches.length != 1) {
      throw StateError(
        'expected exactly one header for `$className` under ${dir.path}, found '
        '${matches.length}',
      );
    }
    return matches.single.path;
  }

  String describe() {
    final threat = _featureSet('ThreatFeatureSet');
    final psq = _featureSet('PSQFeatureSet');
    // The hashes are hoisted out of the literals so each line stays a single string: a
    // concatenation split across two source lines is what `no_adjacent_strings_in_list` forbids.
    final threatHash = _hex(threat.hashValue);
    final psqHash = _hex(psq.hashValue);
    return [
      name,
      '  network format version   ${_hex(networkFormatVersion)}',
      '  threat feature set       ${threat.name} (hash $threatHash, dimensions ${threat.dimensions})',
      '  psq feature set          ${psq.name} (hash $psqHash, dimensions ${psq.dimensions})',
      '  architecture hash        ${_hex(architectureHash)}',
    ].join('\n');
  }
}

final class const _FeatureSet({
  required final String name,
  required final int hashValue,
  required final int dimensions,
});

/// One layer's declaration in `nnue_architecture.h`.
final class const _LayerDeclaration({
  required final String className,

  /// The template arguments as written, in order.
  required final List<String> arguments,
});

/// A layer class in `src/nnue/layers/`, reduced to the one thing the hash needs from it: how wide
/// its output is, given its template arguments.
final class const _LayerClass({
  required final String name,
  required final List<String> parameters,
  required final String output,
}) {
  /// Looks up the header for [className] by the same loose name match the feature headers use.
  factory of(Directory snapshot, String className) {
    final dir = Directory('${snapshot.path}/src/nnue/layers');
    final wanted = className.toLowerCase().replaceAll('_', '');
    final matches = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.h')).where((f) {
      final stem = f.path.split('/').last.replaceAll('.h', '');
      return stem.toLowerCase().replaceAll('_', '') == wanted;
    }).toList();
    if (matches.length != 1) {
      throw StateError(
        'expected exactly one header for layer class `$className` under ${dir.path}, found '
        '${matches.length}',
      );
    }
    final header = _Header.read(matches.single.path);
    final declaration = RegExp(
      'template\\s*<([^>]*)>\\s*class\\s+$className\\b',
      multiLine: true,
    ).firstMatch(header.code);
    if (declaration == null) {
      throw StateError('${header.path}: no `template<...> class $className`');
    }
    final parameterNames = _splitTopLevel(declaration.group(1)!)
        .map((parameter) => parameter.split(RegExp(r'\s+')).last.trim())
        .toList();
    return _LayerClass(
      name: className,
      parameters: parameterNames,
      output: header.declarationOf('OutputDimensions'),
    );
  }

  /// Binds [arguments] to the class's parameters and evaluates the result in [context].
  int outputDimensions(List<String> arguments, _Header context) {
    if (arguments.length != parameters.length) {
      throw StateError(
        '$name takes ${parameters.length} template arguments (${parameters.join(', ')}), but the '
        'architecture passes ${arguments.length}',
      );
    }
    var expression = output;
    for (var i = 0; i < parameters.length; i++) {
      expression = expression.replaceAll(
        RegExp('\\b${RegExp.escape(parameters[i])}\\b'),
        '(${arguments[i]})',
      );
    }
    return context.resolve(expression);
  }
}

/// A header file, with the questions this script asks of one.
final class _Header._(final String path, final String _code) {
  factory read(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('missing vendored header: $path');
    }
    // Comments are stripped so that an anchor cannot be satisfied by prose describing the code
    // rather than by the code.
    final code = file
        .readAsStringSync()
        .split('\n')
        .map((line) {
          final at = line.indexOf('//');
          return at == -1 ? line : line.substring(0, at);
        })
        .join('\n');
    return _Header._(path, code);
  }

  /// The file's text with comments stripped, for callers that want to match against it directly.
  String get code => _code;

  /// Other headers to consult for a name this one does not declare.
  ///
  /// The declarations chain across files: `nnue_feature_transformer.h` writes
  /// `OutputDimensions = HalfDimensions` and `HalfDimensions = L1`, but `L1` is declared in
  /// `nnue_architecture.h`. Resolution follows the include graph rather than being told the
  /// answer.
  List<_Header> fallbacks = const [];

  /// Fails unless [snippet] appears in the code.
  void require(String snippet) {
    if (!_code.contains(snippet)) {
      throw StateError(
        '$path no longer contains `$snippet`.\n'
        'The hash this script computes is built from that line, so it cannot be trusted until the '
        'script is updated to match the header.',
      );
    }
  }

  /// The value of an integer expression written in this header — either a name's declaration or a
  /// bare expression such as a template argument.
  ///
  /// Resolved recursively, because these declarations chain: `OutputDimensions` is
  /// `HalfDimensions`, which is `L1`, which is `1024`.
  int resolve(String expression) => _evaluate(expression, <String>{});

  int _evaluate(String expression, Set<String> seen) {
    return _ExpressionEvaluator(expression, (identifier) {
      final literal = int.tryParse(identifier.replaceAll(RegExp(r'[uUlL]+$'), ''));
      if (literal != null) {
        return literal;
      }
      if (RegExp(r'^0[xX][0-9a-fA-F]+$').hasMatch(identifier)) {
        return _parseIntLiteral(identifier);
      }
      if (!seen.add(identifier)) {
        throw StateError('$path: `$identifier` is defined in terms of itself');
      }
      final value = _evaluate(declarationOf(identifier), seen);
      seen.remove(identifier);
      return value;
    }).evaluate();
  }

  /// The right-hand side of a `name = <expression>;` declaration, unevaluated.
  String declarationOf(String name) {
    final match = RegExp('\\b$name\\s*=\\s*([^;]+);').firstMatch(_code);
    if (match != null) {
      return match.group(1)!;
    }
    for (final fallback in fallbacks) {
      final found = fallback._declarationOrNull(name);
      if (found != null) {
        return found;
      }
    }
    throw StateError('$path: no declaration for `$name`');
  }

  String? _declarationOrNull(String name) =>
      RegExp('\\b$name\\s*=\\s*([^;]+);').firstMatch(_code)?.group(1);

  /// What `using <alias> = Features::<Target>;` points at.
  String aliasTarget(String alias) {
    final match = RegExp('\\busing\\s+$alias\\s*=\\s*Features::(\\w+)\\s*;').firstMatch(_code);
    if (match == null) {
      throw StateError('$path: no `using $alias = Features::...;` alias');
    }
    return match.group(1)!;
  }

  /// The layer names `NetworkArchitecture::get_hash_value` folds in, in the order it folds them.
  List<String> get getHashValueLayers {
    final body = _bodyOf('static constexpr u32 get_hash_value()');
    final names = <String>[];
    for (final match in RegExp(
      r'decltype\((\w+)\)::get_hash_value\(hashValue\)',
    ).allMatches(body)) {
      names.add(match.group(1)!);
    }
    if (names.isEmpty) {
      throw StateError('$path: `get_hash_value` folds in no layers');
    }
    return names;
  }

  /// The declaration of a member, reduced to its class name and template arguments.
  _LayerDeclaration layerDeclarationOf(String name) {
    // The class name is qualified (`Layers::AffineTransform<...>`), so it is not just `\w+`.
    final match = RegExp(
      '^\\s*([\\w:]+)\\s*<([^;]*?)>\\s+$name\\s*;',
      multiLine: true,
    ).firstMatch(_code);
    if (match == null) {
      throw StateError('$path: no `Class<...> $name;` declaration');
    }
    return _LayerDeclaration(
      className: match.group(1)!.split('::').last,
      arguments: _splitTopLevel(match.group(2)!),
    );
  }

  /// The brace-matched body of the declaration starting at [signature].
  String _bodyOf(String signature) {
    final start = _code.indexOf(signature);
    if (start == -1) {
      throw StateError('$path: no `$signature`');
    }
    final open = _code.indexOf('{', start);
    if (open == -1) {
      throw StateError('$path: `$signature` has no body');
    }
    var depth = 0;
    for (var i = open; i < _code.length; i++) {
      final char = _code[i];
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return _code.substring(open, i + 1);
        }
      }
    }
    throw StateError('$path: `$signature` is not brace-balanced');
  }
}

/// Evaluates the integer arithmetic a header uses for its dimensions.
///
/// A small evaluator rather than a literal parse because `Dimensions` is written as
/// `6 * AttackBucketNB * PS_NB` in the feature headers: the numbers it is built from are the ones a
/// bump changes, so the expression has to be followed to them.
final class _ExpressionEvaluator(final String _expression, final int Function(String) _lookup) {
  late final List<String> _tokens = RegExp(
    r'0[xX][0-9a-fA-F]+[uUlL]*|[0-9]+[uUlL]*|[A-Za-z_]\w*|[-+*/()]',
  ).allMatches(_expression).map((match) => match.group(0)!).toList();

  int _position = 0;

  int evaluate() {
    final value = _expression_();
    if (_position != _tokens.length) {
      throw StateError('`$_expression` has trailing tokens from `${_tokens[_position]}`');
    }
    return value;
  }

  int _expression_() {
    var value = _term();
    while (_position < _tokens.length && (_peek() == '+' || _peek() == '-')) {
      final operator = _tokens[_position++];
      final right = _term();
      value = operator == '+' ? value + right : value - right;
    }
    return value;
  }

  int _term() {
    var value = _factor();
    while (_position < _tokens.length && (_peek() == '*' || _peek() == '/')) {
      final operator = _tokens[_position++];
      final right = _factor();
      value = operator == '*' ? value * right : value ~/ right;
    }
    return value;
  }

  int _factor() {
    if (_position >= _tokens.length) {
      throw StateError('`$_expression` ends early');
    }
    final token = _tokens[_position++];
    if (token == '(') {
      final value = _expression_();
      if (_position >= _tokens.length || _tokens[_position] != ')') {
        throw StateError('`$_expression` has an unclosed `(`');
      }
      _position++;
      return value;
    }
    if (token == '-') {
      return -_factor();
    }
    return _lookup(token);
  }

  String _peek() => _tokens[_position];
}

/// Splits a template argument list on its top-level commas.
List<String> _splitTopLevel(String text) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    switch (text[i]) {
      case '<' || '(':
        depth++;
      case '>' || ')':
        depth--;
      case ',' when depth == 0:
        parts.add(text.substring(start, i));
        start = i + 1;
    }
  }
  parts.add(text.substring(start));
  return parts.map((part) => part.trim()).toList();
}
