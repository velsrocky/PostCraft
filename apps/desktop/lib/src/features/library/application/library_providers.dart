import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_paths.dart';
import '../data/file_asset_repository.dart';
import '../domain/asset.dart';
import '../domain/asset_repository.dart';

final assetRepositoryProvider = FutureProvider<AssetRepository>((ref) async {
  final paths = await ref.watch(appPathsProvider.future);
  return FileAssetRepository(paths.assets);
});

class LibraryQuery {
  const LibraryQuery({this.search = '', this.kind});
  final String search;
  final AssetKind? kind;

  bool get isFiltered => search.isNotEmpty || kind != null;

  LibraryQuery copyWith({
    String? search,
    AssetKind? kind,
    bool clearKind = false,
  }) => LibraryQuery(
    search: search ?? this.search,
    kind: clearKind ? null : (kind ?? this.kind),
  );
}

class LibraryQueryController extends Notifier<LibraryQuery> {
  @override
  LibraryQuery build() => const LibraryQuery();

  void setSearch(String value) => state = state.copyWith(search: value);
  void setKind(AssetKind? kind) =>
      state = state.copyWith(kind: kind, clearKind: kind == null);
}

final libraryQueryProvider =
    NotifierProvider<LibraryQueryController, LibraryQuery>(
      LibraryQueryController.new,
    );

final assetsProvider = FutureProvider<List<Asset>>((ref) async {
  final repository = await ref.watch(assetRepositoryProvider.future);
  final query = ref.watch(libraryQueryProvider);
  return repository.list(kind: query.kind, query: query.search);
});

/// Ingests media into the library and refreshes dependent views.
class AssetIngestor {
  const AssetIngestor(this._ref);
  final Ref _ref;

  Future<Asset> add({
    required List<int> bytes,
    required String fileName,
    String? name,
    List<String> tags = const [],
  }) async {
    final repository = await _ref.read(assetRepositoryProvider.future);
    final asset = await repository.add(
      bytes: bytes,
      fileName: fileName,
      name: name,
      tags: tags,
    );
    _ref.invalidate(assetsProvider);
    return asset;
  }
}

final assetIngestorProvider = Provider<AssetIngestor>(AssetIngestor.new);
