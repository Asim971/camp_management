import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_shell.dart';
import '../../../core/l10n/locale_controller.dart';

/// Language preference (spec D4 — per device, not per user).
///
/// Each option is labelled in its OWN language ("English", "বাংলা") rather
/// than translated into the current one: a user who has landed in a language
/// they cannot read must still be able to find their way out. That is also why
/// the follow-the-system option shows both scripts instead of an English-only
/// sentence, and why none of these labels come from the ARB files — a
/// translated label renders in the very language the user is trying to escape.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const AppShell(title: 'Language', body: LanguageScreenBody());
}

/// The picker itself, without the shell — so it can be tested without a
/// router ancestor.
class LanguageScreenBody extends ConsumerWidget {
  const LanguageScreenBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeControllerProvider);
    final controller = ref.read(localeControllerProvider.notifier);

    return ListView(
      children: [
        // One RadioGroup around bare tiles: RadioListTile's per-tile
        // groupValue/onChanged are deprecated on Flutter 3.44 and
        // `flutter analyze --fatal-infos` treats that info as an error. The
        // group value is the language code (null = follow the system), which
        // `current?.languageCode` yields directly.
        RadioGroup<String?>(
          groupValue: current?.languageCode,
          // A single callback for the whole group, so the selected code is
          // mapped back to a Locale here rather than in three per-tile
          // closures. select() applies the choice immediately (app.dart watches
          // the controller) and persists it; a write failure still applies for
          // the session, so nothing here needs to await the result.
          onChanged: (code) =>
              unawaited(controller.select(code == null ? null : Locale(code))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in _languageOptions)
                // Both a Key (for widget tests) and a Semantics identifier:
                // Maestro targets by `id:`, which maps to
                // Semantics(identifier:) and NOT to Key, so a Key-only tile is
                // untappable from the E2E flows.
                Semantics(
                  identifier: option.id,
                  child: RadioListTile<String?>(
                    key: Key(option.id),
                    value: option.code,
                    title: Text(option.label),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LanguageOption {
  const _LanguageOption({
    required this.code,
    required this.id,
    required this.label,
  });

  /// The language code to apply, or null for "follow the system".
  final String? code;

  /// Stable test id, used for both the Flutter [Key] and the Maestro
  /// `Semantics(identifier:)`.
  final String id;

  final String label;
}

const List<_LanguageOption> _languageOptions = [
  _LanguageOption(
    code: null,
    id: 'locale_system',
    // No single "own language" exists for this option, so show both.
    label: 'Use device language · ডিভাইসের ভাষা ব্যবহার করুন',
  ),
  _LanguageOption(code: 'en', id: 'locale_en', label: 'English'),
  _LanguageOption(code: 'bn', id: 'locale_bn', label: 'বাংলা'),
];
