import 'package:flutter_test/flutter_test.dart';
import 'package:postcraft/src/features/templates/application/templates_controller.dart';
import 'package:postcraft/src/features/templates/domain/template.dart';

void main() {
  test('built-in templates cover the six showcase cards', () {
    final ids = ProjectTemplate.builtIns.map((template) => template.id).toList();
    expect(ids, [
      'developer',
      'tutorial',
      'bug-report',
      'feature-request',
      'business',
      'education',
    ]);
  });

  test('each built-in template has a canvas and 2–5 seed objects', () {
    for (final template in ProjectTemplate.builtIns) {
      expect(template.canvasWidth, greaterThan(0));
      expect(template.canvasHeight, greaterThan(0));
      expect(template.objectSeeds.length, inInclusiveRange(2, 5));
    }
  });

  test('template JSON round trips', () {
    final original = ProjectTemplate.builtIns.first;
    final restored = ProjectTemplate.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.name, original.name);
    expect(restored.description, original.description);
    expect(restored.iconName, original.iconName);
    expect(restored.colorSeed, original.colorSeed);
    expect(restored.canvasWidth, original.canvasWidth);
    expect(restored.canvasHeight, original.canvasHeight);
    expect(restored.objectSeeds.length, original.objectSeeds.length);
    for (var i = 0; i < original.objectSeeds.length; i++) {
      expect(
        restored.objectSeeds[i].toJson(),
        original.objectSeeds[i].toJson(),
      );
    }
  });

  test('documentFromTemplate builds editor objects from seeds', () {
    final template = ProjectTemplate.builtIns.first;
    final document = documentFromTemplate(template);

    expect(document.width, template.canvasWidth);
    expect(document.height, template.canvasHeight);
    expect(document.objects, hasLength(template.objectSeeds.length));
    expect(document.nextId, template.objectSeeds.length + 1);
    expect(document.sourceImage, isNull);
    expect(document.timeline.isEmpty, isTrue);
  });
}
