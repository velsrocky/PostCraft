import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/feedback.dart';
import '../../editor/application/editor_controller.dart';
import '../../editor/domain/editor_document.dart';
import '../../projects/application/projects_providers.dart';
import '../domain/template.dart';

final templatesProvider = Provider<List<ProjectTemplate>>(
  (ref) => ProjectTemplate.builtIns,
);

EditorDocument documentFromTemplate(ProjectTemplate template) {
  final objects = <EditorObject>[];
  var nextId = 1;
  for (final seed in template.objectSeeds) {
    switch (seed) {
      case TemplateShapeSeed(
        :final kind,
        :final color,
        :final left,
        :final top,
        :final width,
        :final height,
      ):
        objects.add(
          ShapeObject(
            id: nextId,
            color: Color(color),
            rect: Rect.fromLTWH(left, top, width, height),
            kind: editorToolFromName(kind),
          ),
        );
        nextId++;
      case TemplateTextSeed(:final color, :final x, :final y, :final text):
        objects.add(
          TextObject(
            id: nextId,
            color: Color(color),
            position: Offset(x, y),
            text: text,
          ),
        );
        nextId++;
    }
  }
  return EditorDocument(
    objects: objects,
    nextId: nextId,
    width: template.canvasWidth,
    height: template.canvasHeight,
  );
}

Future<void> applyTemplate(Ref ref, ProjectTemplate template) async {
  final feedback = ref.read(feedbackProvider.notifier);
  try {
    final document = documentFromTemplate(template);
    ref.read(editorControllerProvider.notifier).replaceDocument(document);
    await ref
        .read(workspaceControllerProvider.notifier)
        .startProject(document, name: template.name);
    ref.read(routerProvider).go('/editor');
    feedback.notify('${template.name} template applied');
  } on Object catch (error) {
    feedback.notify('Could not apply template: $error');
  }
}

final applyTemplateProvider = Provider<Future<void> Function(ProjectTemplate)>((
  ref,
) => (template) => applyTemplate(ref, template));
