import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../application/templates_controller.dart';

class TemplatesPage extends ConsumerWidget {
  const TemplatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider);
    final apply = ref.read(applyTemplateProvider);
    return Padding(
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
                    onTap: () => apply(template),
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
                              color: template.color.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              template.icon,
                              color: template.color,
                              size: 19,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            template.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            template.description,
                            style: const TextStyle(
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
}
