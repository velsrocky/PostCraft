import '../../editor/domain/editor_document.dart';
import 'project.dart';

/// Storage contract for local projects.
///
/// The domain depends only on this interface, so the file store used today can
/// be swapped for a maintained Isar implementation without touching features.
abstract interface class ProjectRepository {
  /// Projects ordered by most recently updated first.
  Future<List<Project>> list();

  Future<Project?> get(String id);

  /// Persists [document] as a durable project revision, clearing any draft.
  ///
  /// When [existing] is null a new project is created and returned.
  Future<Project> save({
    Project? existing,
    required String name,
    required EditorDocument document,
    List<int>? thumbnail,
  });

  /// Writes a recoverable draft checkpoint without disturbing the last saved
  /// revision. Surfaces as [Project.hasUnsavedDraft] until the next save.
  Future<Project> autosave(String id, EditorDocument document);

  /// Loads a saved revision, or the recoverable draft when [draft] is true.
  Future<EditorDocument> load(String id, {bool draft = false});

  Future<void> delete(String id);
}
