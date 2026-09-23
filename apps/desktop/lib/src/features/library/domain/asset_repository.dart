import '../domain/asset.dart';

/// Storage + query contract for the local media library.
///
/// Like [ProjectRepository], this lets the file-backed index be swapped for a
/// maintained engine later without touching the Library UI.
abstract interface class AssetRepository {
  /// Newest first, optionally filtered by kind and free-text search over the
  /// asset name and tags.
  Future<List<Asset>> list({AssetKind? kind, String query = ''});

  /// Registers a media file. De-duplicates by content hash (re-adding the same
  /// bytes updates the existing asset rather than storing a second copy).
  Future<Asset> add({
    required List<int> bytes,
    required String fileName,
    String? name,
    List<String> tags,
  });

  Future<Asset?> get(String id);

  Future<void> remove(String id);

  Future<Asset> setTags(String id, List<String> tags);

  /// Absolute path to an asset's stored bytes, or null if unavailable.
  Future<String?> filePath(String id);
}
