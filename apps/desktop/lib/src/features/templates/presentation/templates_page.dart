import 'package:flutter/material.dart';

import '../../../app/theme.dart';

class TemplatesPage extends StatelessWidget {
  const TemplatesPage({super.key});

  static const templates = [
    ('Developer', Icons.code_rounded, Color(0xFF6E8AFF)),
    ('Tutorial', Icons.school_outlined, Color(0xFF62C9B1)),
    ('Bug report', Icons.bug_report_outlined, Color(0xFFFF7787)),
    ('Feature request', Icons.lightbulb_outline_rounded, Color(0xFFFFBE62)),
    ('Business', Icons.business_center_outlined, Color(0xFFB18AFF)),
    ('Education', Icons.menu_book_outlined, Color(0xFF63B7E8)),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Start with a template',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'A polished starting point for whatever you are creating.',
          style: TextStyle(color: PostCraftTheme.muted),
        ),
        const SizedBox(height: 25),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final template in templates)
              SizedBox(
                width: 220,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.all(17),
                    decoration: BoxDecoration(
                      color: PostCraftTheme.panel,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .06),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: template.$3.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            template.$2,
                            color: template.$3,
                            size: 19,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          template.$1,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Clean, ready-to-customize layout',
                          style: TextStyle(
                            color: PostCraftTheme.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
