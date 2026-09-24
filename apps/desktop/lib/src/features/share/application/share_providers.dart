import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/share_provider.dart';
import '../data/share_destinations.dart';

const _destinations = <ShareDestination>[
  CopyImageDestination(),
  SaveImageDestination(),
  CopyPathDestination(),
  OpenContainingFolderDestination(),
];

final shareDestinationsProvider = Provider<List<ShareDestination>>(
  (ref) => _destinations,
);

Future<void> runShare(
  BuildContext context,
  ShareDestination destination,
  SharePayload payload,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await destination.share(payload);
  messenger.showSnackBar(SnackBar(content: Text(result.message)));
}
