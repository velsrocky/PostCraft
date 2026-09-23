import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../../../app/theme.dart';
import '../application/editor_controller.dart';
import '../domain/editor_document.dart';
import 'editor_surface.dart';
import '../../export/document_renderer.dart';
import '../../projects/application/projects_providers.dart';
import '../../projects/data/project_file_service.dart';
import '../../capture/application/capture_providers.dart';
import '../../capture/domain/capture_result.dart';

const _projectFileService = ProjectFileService();
const _documentRenderer = DocumentRenderer();

class EditorPage extends ConsumerWidget {
  const EditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorControllerProvider);
    final controller = ref.read(editorControllerProvider.notifier);
    final captureCapabilities = ref.watch(captureCapabilitiesProvider);
    final canCapture =
        captureCapabilities.hasValue &&
        captureCapabilities.requireValue.desktopCapture;
    final workspace = ref.watch(workspaceControllerProvider);

    // Any document edit schedules a debounced, recoverable autosave.
    ref.listen(editorControllerProvider.select((value) => value.document), (
      previous,
      next,
    ) {
      if (!identical(previous, next)) {
        ref.read(workspaceControllerProvider.notifier).markChanged();
      }
    });

    return CallbackShortcuts(
      bindings: {
        SingleActivator(
          LogicalKeyboardKey.keyA,
          control: true,
          shift: true,
        ): canCapture
            ? () => _capture(context, ref, CaptureMode.region)
            : () {},
        SingleActivator(
          LogicalKeyboardKey.keyF,
          control: true,
          shift: true,
        ): canCapture
            ? () => _capture(context, ref, CaptureMode.screen)
            : () {},
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            _ProjectHeader(state: workspace, onSave: () => _saveNow(ref)),
            if (!captureCapabilities.isLoading && !canCapture)
              MaterialBanner(
                leading: const Icon(Icons.screenshot_monitor_outlined),
                content: Text(
                  captureCapabilities.hasError
                      ? 'Could not check screen capture availability.'
                      : 'Screen capture is unavailable in this Linux desktop session.',
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(captureCapabilitiesProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            _EditorToolbar(
              state: state,
              onTool: controller.selectTool,
              onUndo: controller.undo,
              onRedo: controller.redo,
              onImport: () => _importImage(context, ref),
              onCaptureRegion: canCapture
                  ? () => _capture(context, ref, CaptureMode.region)
                  : null,
              onCaptureScreen: canCapture
                  ? () => _capture(context, ref, CaptureMode.screen)
                  : null,
              captureTooltip: captureCapabilities.when(
                data: (capabilities) => capabilities.desktopCapture
                    ? 'Capture screen or region'
                    : 'Linux capture is unavailable in this desktop session',
                error: (_, _) => 'Could not check Linux capture availability',
                loading: () => 'Checking capture availability…',
              ),
              onOpen: () => _openProject(context, ref),
              onSave: () => _saveNow(ref),
              onExport: () => _exportPng(context, state.document),
              onCopy: () => _copyPng(context, state.document),
              onColor: controller.selectColor,
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      color: const Color(0xFF111318),
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: AspectRatio(
                          aspectRatio:
                              state.document.width / state.document.height,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF242833),
                              borderRadius: BorderRadius.circular(5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: .4),
                                  blurRadius: 34,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: EditorSurface(
                              state: state,
                              onCommit: controller.commit,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _PropertiesPanel(
                    state: state,
                    onColor: controller.selectColor,
                    onRemove: controller.removeObject,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _capture(
    BuildContext context,
    WidgetRef ref,
    CaptureMode mode,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final capture = await ref.read(linuxCaptureServiceProvider).capture(mode);
      final image = await decodeImageFromList(capture.bytes);
      ref
          .read(editorControllerProvider.notifier)
          .openImage(capture.bytes, image.width, image.height);
      image.dispose();
      final document = ref.read(editorControllerProvider).document;
      await ref
          .read(workspaceControllerProvider.notifier)
          .startProject(
            document,
            name: mode == CaptureMode.region
                ? 'Region capture'
                : 'Screen capture',
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            mode == CaptureMode.region
                ? 'Region captured and opened in the editor'
                : 'Screen captured and opened in the editor',
          ),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Capture failed: $error')));
    }
  }

  Future<void> _importImage(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
        ),
      ],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final image = await decodeImageFromList(bytes);
    ref
        .read(editorControllerProvider.notifier)
        .importSourceImage(bytes, image.width, image.height);
    image.dispose();
    final document = ref.read(editorControllerProvider).document;
    await ref
        .read(workspaceControllerProvider.notifier)
        .startProject(document, name: 'Imported image');
    messenger.showSnackBar(const SnackBar(content: Text('Image imported')));
  }

  Future<void> _openProject(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final document = await _projectFileService.open();
      if (document == null) return;
      ref.read(editorControllerProvider.notifier).replaceDocument(document);
      await ref
          .read(workspaceControllerProvider.notifier)
          .startProject(document, name: 'Opened project');
      messenger.showSnackBar(const SnackBar(content: Text('Project opened')));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open project: $error')),
      );
    }
  }

  Future<void> _saveNow(WidgetRef ref) async {
    final workspace = ref.read(workspaceControllerProvider.notifier);
    if (ref.read(workspaceControllerProvider).current == null) {
      await workspace.startProject(ref.read(editorControllerProvider).document);
    } else {
      await workspace.saveNow();
    }
  }

  Future<void> _exportPng(BuildContext context, EditorDocument document) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _documentRenderer.renderPng(document);
      final location = await getSaveLocation(
        suggestedName: 'PostCraft-export.png',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PNG image', extensions: ['png']),
        ],
      );
      if (location == null) return;
      await XFile.fromData(
        bytes,
        mimeType: 'image/png',
        name: 'PostCraft-export.png',
      ).saveTo(location.path);
      messenger.showSnackBar(const SnackBar(content: Text('PNG exported')));
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $error')));
    }
  }

  Future<void> _copyPng(BuildContext context, EditorDocument document) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _documentRenderer.renderPng(document);
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Clipboard is unavailable on this platform'),
          ),
        );
        return;
      }
      final item = DataWriterItem();
      item.add(Formats.png(bytes));
      await clipboard.write([item]);
      messenger.showSnackBar(
        const SnackBar(content: Text('Image copied to clipboard')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Clipboard copy failed: $error')),
      );
    }
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({required this.state, required this.onSave});
  final WorkspaceState state;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final project = state.current;
    final status = switch (state.status) {
      SaveStatus.saving => 'Saving…',
      SaveStatus.saved => state.dirty ? 'Unsaved changes' : 'Saved',
      SaveStatus.none => project == null ? 'No project' : 'Saved',
    };
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: PostCraftTheme.elevated,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: .06)),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.folder_rounded,
            size: 15,
            color: PostCraftTheme.muted,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              project?.name ?? 'Untitled project',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          if (project != null)
            Icon(
              state.dirty ? Icons.circle : Icons.cloud_done_outlined,
              size: 10,
              color: state.dirty
                  ? const Color(0xFFFFBE62)
                  : const Color(0xFF63D6A2),
            ),
          const SizedBox(width: 6),
          Text(
            status,
            style: const TextStyle(color: PostCraftTheme.muted, fontSize: 11),
          ),
          const Spacer(),
          if (project != null && state.dirty)
            TextButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save_outlined, size: 15),
              label: const Text('Save'),
            ),
        ],
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.state,
    required this.onTool,
    required this.onUndo,
    required this.onRedo,
    required this.onImport,
    required this.onCaptureRegion,
    required this.onCaptureScreen,
    required this.captureTooltip,
    required this.onOpen,
    required this.onSave,
    required this.onExport,
    required this.onCopy,
    required this.onColor,
  });
  final EditorState state;
  final ValueChanged<EditorTool> onTool;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onImport;
  final VoidCallback? onCaptureRegion;
  final VoidCallback? onCaptureScreen;
  final String captureTooltip;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onExport;
  final VoidCallback onCopy;
  final ValueChanged<Color> onColor;

  @override
  Widget build(BuildContext context) {
    const tools = [
      (EditorTool.select, Icons.near_me_outlined, 'Select'),
      (EditorTool.arrow, Icons.north_east_rounded, 'Arrow'),
      (EditorTool.rectangle, Icons.crop_din_rounded, 'Rectangle'),
      (EditorTool.ellipse, Icons.circle_outlined, 'Ellipse'),
      (EditorTool.text, Icons.title_rounded, 'Text'),
      (EditorTool.pencil, Icons.gesture_rounded, 'Pencil'),
      (EditorTool.blur, Icons.blur_on_rounded, 'Blur'),
    ];
    return Container(
      height: 55,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: PostCraftTheme.panel,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: .06)),
        ),
      ),
      child: Row(
        children: [
          for (final entry in tools)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Tooltip(
                message: entry.$3,
                child: IconButton.filledTonal(
                  onPressed: () => onTool(entry.$1),
                  isSelected: state.tool == entry.$1,
                  icon: Icon(entry.$2, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: state.tool == entry.$1
                        ? PostCraftTheme.accent.withValues(alpha: .2)
                        : Colors.transparent,
                    foregroundColor: state.tool == entry.$1
                        ? const Color(0xFFC8BDFF)
                        : PostCraftTheme.muted,
                    minimumSize: const Size(36, 36),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 10),
          for (final color in [
            const Color(0xFF8D7CFF),
            const Color(0xFFFF6C8A),
            const Color(0xFFFFC85A),
            const Color(0xFF63D6A2),
            Colors.white,
          ])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onColor(color),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: state.color == color
                          ? Colors.white
                          : Colors.white24,
                      width: state.color == color ? 2 : 1,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          Container(width: 1, height: 24, color: Colors.white12),
          const SizedBox(width: 10),
          IconButton(
            tooltip: '$captureTooltip · Region',
            onPressed: onCaptureRegion,
            icon: const Icon(Icons.crop_free_rounded, size: 18),
          ),
          IconButton(
            tooltip: '$captureTooltip · Full screen',
            onPressed: onCaptureScreen,
            icon: const Icon(Icons.screenshot_monitor_outlined, size: 18),
          ),
          IconButton(
            tooltip: 'Open image',
            onPressed: onImport,
            icon: const Icon(Icons.image_outlined, size: 18),
          ),
          IconButton(
            tooltip: 'Open project',
            onPressed: onOpen,
            icon: const Icon(Icons.folder_open_outlined, size: 18),
          ),
          IconButton(
            tooltip: 'Save project',
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined, size: 18),
          ),
          IconButton(
            tooltip: 'Undo',
            onPressed: state.undoStack.isEmpty ? null : onUndo,
            icon: const Icon(Icons.undo_rounded, size: 18),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: state.redoStack.isEmpty ? null : onRedo,
            icon: const Icon(Icons.redo_rounded, size: 18),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Copy image to clipboard',
            onPressed: onCopy,
            icon: const Icon(Icons.content_copy_rounded, size: 17),
          ),
          FilledButton.tonalIcon(
            onPressed: onExport,
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Export'),
          ),
          const SizedBox(width: 12),
          const Icon(
            Icons.zoom_out_rounded,
            size: 17,
            color: PostCraftTheme.muted,
          ),
          const SizedBox(width: 8),
          const Text(
            '100%',
            style: TextStyle(color: PostCraftTheme.muted, fontSize: 12),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.zoom_in_rounded,
            size: 17,
            color: PostCraftTheme.muted,
          ),
        ],
      ),
    );
  }
}

class _PropertiesPanel extends StatelessWidget {
  const _PropertiesPanel({
    required this.state,
    required this.onColor,
    required this.onRemove,
  });
  final EditorState state;
  final ValueChanged<Color> onColor;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => Container(
    width: 246,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: PostCraftTheme.panel,
      border: Border(
        left: BorderSide(color: Colors.white.withValues(alpha: .06)),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Properties',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 22),
        const _SectionLabel('DOCUMENT'),
        const SizedBox(height: 10),
        _PropertyRow('Canvas', '${state.document.width} × ${state.document.height}'),
        _PropertyRow(
          'Background',
          state.document.sourceImage == null ? 'Empty' : 'Image',
        ),
        const SizedBox(height: 22),
        const _SectionLabel('COLOR'),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final color in [
              const Color(0xFF8D7CFF),
              const Color(0xFFFF6C8A),
              const Color(0xFFFFC85A),
              const Color(0xFF63D6A2),
              Colors.white,
            ])
              GestureDetector(
                onTap: () => onColor(color),
                child: Container(
                  width: 25,
                  height: 25,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionLabel('LAYERS'),
        const SizedBox(height: 8),
        Expanded(
          child: state.document.objects.isEmpty
              ? const Center(
                  child: Text(
                    'Your layers will appear here',
                    style: TextStyle(color: PostCraftTheme.muted, fontSize: 11),
                  ),
                )
              : ListView.builder(
                  itemCount: state.document.objects.length,
                  itemBuilder: (context, index) {
                    final object = state.document.objects.reversed.elementAt(
                      index,
                    );
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        object is TextObject
                            ? Icons.title
                            : Icons.crop_din_outlined,
                        size: 16,
                        color: object.color,
                      ),
                      title: Text(
                        object is TextObject
                            ? object.text
                            : 'Shape ${object.id}',
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete layer',
                        onPressed: () => onRemove(object.id),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                        ),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
          label: const Text('Social preset'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(38),
          ),
        ),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: PostCraftTheme.muted,
      fontSize: 10,
      letterSpacing: 1,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: PostCraftTheme.muted, fontSize: 11),
        ),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}
