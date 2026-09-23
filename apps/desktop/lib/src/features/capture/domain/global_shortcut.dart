import 'package:postcraft/src/rust/lib.dart';

/// Stable identifiers the Rust portal registers and the UI maps to actions.
class ShortcutIds {
  const ShortcutIds._();
  static const region = 'postcraft.region';
  static const screen = 'postcraft.screen';
}

/// The bindings PostCraft requests. Trigger syntax follows the portal's
/// preferred-trigger format (`<Ctrl><Shift>A`).
List<ShortcutBinding> defaultShortcutBindings() => const [
  ShortcutBinding(
    id: ShortcutIds.region,
    preferredTrigger: '<Ctrl><Shift>A',
    description: 'Capture a screen region',
  ),
  ShortcutBinding(
    id: ShortcutIds.screen,
    preferredTrigger: '<Ctrl><Shift>F',
    description: 'Capture the full screen',
  ),
];
