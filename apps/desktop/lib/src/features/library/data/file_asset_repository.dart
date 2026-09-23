import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../domain/asset.dart';
import '../domain/asset_repository.dart';

/// Filesystem-backed [AssetRepository].
///
/// Media is stored content-addressed under `<assetsRoot>/<id>/<file>` with a
/// single atomic `index.json` holding queryable metadata. Re-adding identical
/// bytes updates the existing asset instead of duplicating it.
class FileAssetRepository implements AssetRepository {
  FileAssetRepository(this.assetsRoot, {Random? random})
    : _random = random ?? Random();

  final Directory assetsRoot;
  final Random _random;

  static const _indexFile = 'index.json';

  @override
  Future<List<Asset>> list({AssetKind? kind, String query = ''}) async {
    final needle = query.trim().toLowerCase();
    final assets = (await _load())
        .where((asset) => kind == null || asset.kind == kind)
        .where(
          (asset) =>
              needle.isEmpty ||
              asset.name.toLowerCase().contains(needle) ||
              asset.tags.any((tag) => tag.toLowerCase().contains(needle)),
        )
        .toList();
    assets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return assets;
  }

  @override
  Future<Asset> add({
    required List<int> bytes,
    required String fileName,
    String? name,
    List<String> tags = const [],
  }) async {
    final hash = sha256.convert(bytes).toString();
    final assets = await _load();
    final existing = assets.where((a) => a.contentHash == hash).firstOrNull;
    if (existing != null) {
      final merged = existing.copyWith(
        name: name ?? existing.name,
        tags: <String>{...existing.tags, ...tags}.toList(),
      );
      await _save(_replace(assets, merged));
      return merged;
    }

    final id = _newId();
    final extension = _extensionOf(fileName);
    final storedFileName = extension.isEmpty ? id : '$id.$extension';
    final directory = Directory(_path(id));
    await directory.create(recursive: true);
    final file = File(_path(id) + Platform.pathSeparator + storedFileName);
    await file.writeAsBytes(bytes, flush: true);

    final resolvedName = (name ?? _baseName(fileName)).trim();
    final asset = Asset(
      id: id,
      name: resolvedName.isEmpty ? 'Untitled' : resolvedName,
      storedFileName: storedFileName,
      kind: assetKindForExtension(extension),
      contentHash: hash,
      byteSize: bytes.length,
      createdAt: DateTime.now().toUtc(),
      tags: tags,
    );
    await _save([...assets, asset]);
    return asset;
  }

  @override
  Future<Asset?> get(String id) async =>
      (await _load()).where((a) => a.id == id).firstOrNull;

  @override
  Future<void> remove(String id) async {
    final assets = await _load();
    if (assets.every((a) => a.id != id)) return;
    final directory = Directory(_path(id));
    if (await directory.exists()) await directory.delete(recursive: true);
    await _save(assets.where((a) => a.id != id).toList());
  }

  @override
  Future<Asset> setTags(String id, List<String> tags) async {
    final assets = await _load();
    final current = assets.where((a) => a.id == id).firstOrNull;
    if (current == null) {
      throw const FileSystemException('Cannot tag an unknown asset.');
    }
    final cleaned = tags
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final updated = current.copyWith(tags: cleaned);
    await _save(_replace(assets, updated));
    return updated;
  }

  @override
  Future<String?> filePath(String id) async {
    final asset = await get(id);
    if (asset == null) return null;
    final file = File(
      _path(id) + Platform.pathSeparator + asset.storedFileName,
    );
    return await file.exists() ? file.path : null;
  }

  List<Asset> _replace(List<Asset> assets, Asset updated) => [
    for (final a in assets)
      if (a.id == updated.id) updated else a,
  ];

  Future<List<Asset>> _load() async {
    final index = File(_path(_indexFile));
    if (!await index.exists()) return [];
    try {
      return Asset.decodeIndex(await index.readAsString());
    } on Object {
      return [];
    }
  }

  Future<void> _save(List<Asset> assets) async {
    await assetsRoot.create(recursive: true);
    final target = File(_path(_indexFile));
    final temporary = File('${target.path}.tmp-${_random.nextInt(1 << 32)}');
    try {
      await temporary.writeAsString(Asset.encodeIndex(assets), flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  String _newId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = _random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
    return 'a_${stamp}_$suffix';
  }

  String _path(String relative) =>
      '${assetsRoot.path}${Platform.pathSeparator}$relative';

  String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1);
  }

  String _baseName(String fileName) {
    final slash = fileName.replaceAll('\\', '/').lastIndexOf('/');
    final base = slash >= 0 ? fileName.substring(slash + 1) : fileName;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }
}
