import 'package:flutter/material.dart';

IconData templateIconData(String name) => switch (name) {
  'code' => Icons.code_rounded,
  'school' => Icons.school_outlined,
  'bug_report' => Icons.bug_report_outlined,
  'lightbulb' => Icons.lightbulb_outline_rounded,
  'business_center' => Icons.business_center_outlined,
  'menu_book' => Icons.menu_book_outlined,
  _ => Icons.dashboard_customize_outlined,
};

sealed class TemplateObjectSeed {
  const TemplateObjectSeed({required this.color});
  final int color;

  Map<String, Object?> toJson();

  factory TemplateObjectSeed.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Template seed must be an object.');
    }
    final map = Map<String, Object?>.from(raw);
    final type = map['type'];
    final color = map['color'];
    if (color is! int) {
      throw const FormatException('Template seed color must be an int.');
    }
    return switch (type) {
      'shape' => TemplateShapeSeed(
        color: color,
        kind: map['kind'] as String? ?? 'rectangle',
        left: _number(map['left']),
        top: _number(map['top']),
        width: _number(map['width']),
        height: _number(map['height']),
      ),
      'text' => TemplateTextSeed(
        color: color,
        x: _number(map['x']),
        y: _number(map['y']),
        text: map['text'] as String? ?? '',
      ),
      _ => throw const FormatException('Unknown template seed type.'),
    };
  }
}

class TemplateShapeSeed extends TemplateObjectSeed {
  const TemplateShapeSeed({
    required super.color,
    required this.kind,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String kind;
  final double left;
  final double top;
  final double width;
  final double height;

  @override
  Map<String, Object?> toJson() => {
    'type': 'shape',
    'color': color,
    'kind': kind,
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };
}

class TemplateTextSeed extends TemplateObjectSeed {
  const TemplateTextSeed({
    required super.color,
    required this.x,
    required this.y,
    required this.text,
  });

  final double x;
  final double y;
  final String text;

  @override
  Map<String, Object?> toJson() => {
    'type': 'text',
    'color': color,
    'x': x,
    'y': y,
    'text': text,
  };
}

class ProjectTemplate {
  const ProjectTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.iconName,
    required this.colorSeed,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.objectSeeds,
  });

  final String id;
  final String name;
  final String description;
  final String iconName;
  final int colorSeed;
  final int canvasWidth;
  final int canvasHeight;
  final List<TemplateObjectSeed> objectSeeds;

  IconData get icon => templateIconData(iconName);

  Color get color => Color(colorSeed);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'iconName': iconName,
    'colorSeed': colorSeed,
    'canvasWidth': canvasWidth,
    'canvasHeight': canvasHeight,
    'objectSeeds': objectSeeds.map((seed) => seed.toJson()).toList(),
  };

  factory ProjectTemplate.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) {
      throw const FormatException('Template id and name must be strings.');
    }
    final seeds = (json['objectSeeds'] as List?)
        ?.map(TemplateObjectSeed.fromJson)
        .toList() ??
        const <TemplateObjectSeed>[];
    return ProjectTemplate(
      id: id,
      name: name,
      description: json['description'] as String? ?? '',
      iconName: json['iconName'] as String? ?? '',
      colorSeed: json['colorSeed'] is int ? json['colorSeed']! as int : 0xFF9B8CFF,
      canvasWidth: json['canvasWidth'] is int ? json['canvasWidth']! as int : 1920,
      canvasHeight: json['canvasHeight'] is int ? json['canvasHeight']! as int : 1080,
      objectSeeds: seeds,
    );
  }

  static const List<ProjectTemplate> builtIns = [
    ProjectTemplate(
      id: 'developer',
      name: 'Developer',
      description: 'Dev-log layout with accent bars and a content panel.',
      iconName: 'code',
      colorSeed: 0xFF6E8AFF,
      canvasWidth: 1920,
      canvasHeight: 1080,
      objectSeeds: [
        TemplateTextSeed(color: 0xFFFFFFFF, x: 140, y: 150, text: 'What I shipped this week'),
        TemplateTextSeed(color: 0xFF6E8AFF, x: 140, y: 200, text: 'Dev log · #12'),
        TemplateShapeSeed(color: 0xFF6E8AFF, kind: 'rectangle', left: 140, top: 260, width: 520, height: 8),
        TemplateShapeSeed(color: 0xFF2A2F3A, kind: 'rectangle', left: 140, top: 320, width: 1100, height: 560),
      ],
    ),
    ProjectTemplate(
      id: 'tutorial',
      name: 'Tutorial',
      description: 'Step-by-step walkthrough with numbered markers.',
      iconName: 'school',
      colorSeed: 0xFF62C9B1,
      canvasWidth: 1600,
      canvasHeight: 900,
      objectSeeds: [
        TemplateTextSeed(color: 0xFFFFFFFF, x: 100, y: 110, text: 'How to do X in 5 minutes'),
        TemplateShapeSeed(color: 0xFF62C9B1, kind: 'rectangle', left: 100, top: 190, width: 72, height: 72),
        TemplateTextSeed(color: 0xFFFFFFFF, x: 122, y: 212, text: '1'),
        TemplateTextSeed(color: 0xFF62C9B1, x: 100, y: 300, text: 'Step one: open the project'),
        TemplateShapeSeed(color: 0xFF62C9B1, kind: 'rectangle', left: 100, top: 360, width: 900, height: 6),
      ],
    ),
    ProjectTemplate(
      id: 'bug-report',
      name: 'Bug report',
      description: 'Repro steps, severity, and environment sections.',
      iconName: 'bug_report',
      colorSeed: 0xFFFF7787,
      canvasWidth: 1600,
      canvasHeight: 900,
      objectSeeds: [
        TemplateTextSeed(color: 0xFFFFFFFF, x: 100, y: 110, text: 'Bug: crash on export'),
        TemplateTextSeed(color: 0xFFFF7787, x: 100, y: 160, text: 'Severity: high'),
        TemplateShapeSeed(color: 0xFFFF7787, kind: 'rectangle', left: 100, top: 230, width: 8, height: 320),
        TemplateShapeSeed(color: 0xFF2A2F3A, kind: 'rectangle', left: 140, top: 230, width: 860, height: 320),
        TemplateTextSeed(color: 0xFFFFFFFF, x: 170, y: 270, text: 'Steps to reproduce…'),
      ],
    ),
    ProjectTemplate(
      id: 'feature-request',
      name: 'Feature request',
      description: 'Problem, proposal, and impact layout.',
      iconName: 'lightbulb',
      colorSeed: 0xFFFFBE62,
      canvasWidth: 1600,
      canvasHeight: 900,
      objectSeeds: [
        TemplateTextSeed(color: 0xFFFFFFFF, x: 100, y: 110, text: 'Feature: scheduled publishing'),
        TemplateTextSeed(color: 0xFFFFBE62, x: 100, y: 165, text: 'Why it matters'),
        TemplateShapeSeed(color: 0xFFFFBE62, kind: 'rectangle', left: 100, top: 230, width: 780, height: 6),
        TemplateShapeSeed(color: 0xFF2A2F3A, kind: 'rectangle', left: 100, top: 290, width: 780, height: 340),
      ],
    ),
    ProjectTemplate(
      id: 'business',
      name: 'Business',
      description: 'Quarterly review with headline and chart blocks.',
      iconName: 'business_center',
      colorSeed: 0xFFB18AFF,
      canvasWidth: 1920,
      canvasHeight: 1080,
      objectSeeds: [
        TemplateTextSeed(color: 0xFFFFFFFF, x: 140, y: 130, text: 'Q3 Business Review'),
        TemplateShapeSeed(color: 0xFFB18AFF, kind: 'rectangle', left: 140, top: 200, width: 420, height: 8),
        TemplateShapeSeed(color: 0xFF2A2F3A, kind: 'rectangle', left: 140, top: 270, width: 760, height: 420),
        TemplateShapeSeed(color: 0xFF2A2F3A, kind: 'rectangle', left: 960, top: 270, width: 760, height: 420),
        TemplateTextSeed(color: 0xFFB18AFF, x: 170, y: 300, text: 'Revenue'),
      ],
    ),
    ProjectTemplate(
      id: 'education',
      name: 'Education',
      description: 'Lesson outline with objectives and a content area.',
      iconName: 'menu_book',
      colorSeed: 0xFF63B7E8,
      canvasWidth: 1600,
      canvasHeight: 900,
      objectSeeds: [
        TemplateTextSeed(color: 0xFFFFFFFF, x: 100, y: 110, text: 'Lesson 1: Introduction'),
        TemplateTextSeed(color: 0xFF63B7E8, x: 100, y: 165, text: 'Learning objectives'),
        TemplateShapeSeed(color: 0xFF63B7E8, kind: 'rectangle', left: 100, top: 230, width: 640, height: 6),
        TemplateShapeSeed(color: 0xFF2A2F3A, kind: 'rectangle', left: 100, top: 290, width: 980, height: 420),
      ],
    ),
  ];
}

double _number(Object? value) => value is num ? value.toDouble() : 0;
