import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/status_chip.dart';
import '../../../domain/registration/registration.dart';
import '../application/carpenter_search_controller.dart';

/// Carpenter search & selection (M-02). Helps the operator pick the correct
/// registered carpenter quickly and safely: name/ID/phone-suffix search, photo
/// as one cue only, and a required second identity confirmation before capture.
class CarpenterSearchScreen extends ConsumerStatefulWidget {
  const CarpenterSearchScreen({required this.sessionId, super.key});
  final String sessionId;

  @override
  ConsumerState<CarpenterSearchScreen> createState() =>
      _CarpenterSearchScreenState();
}

class _CarpenterSearchScreenState extends ConsumerState<CarpenterSearchScreen> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(carpenterSearchProvider(widget.sessionId));

    return Scaffold(
      appBar: AppBar(toolbarHeight: 56, title: const Text('Find carpenter')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Semantics(
              identifier: 'search_field',
              child: TextField(
                controller: _field,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (q) => ref
                    .read(carpenterSearchProvider(widget.sessionId).notifier)
                    .search(q),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Name, ID or phone suffix',
                  helperText: 'Type at least 2 characters',
                ),
              ),
            ),
          ),
          Expanded(
            child: results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('Search unavailable')),
              data: (list) => list.isEmpty
                  ? const Center(
                      child: Text('No matching registered carpenter.'),
                    )
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _ResultTile(
                        c: list[i],
                        // Similar-name results warrant extra care (§8.9).
                        similarName: _hasSimilarName(list, i),
                        onSelect: () => _confirm(list[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasSimilarName(List<RegisteredCarpenter> list, int i) {
    final name = list[i].name.toLowerCase();
    return list.where((c) => c.name.toLowerCase() == name).length > 1;
  }

  Future<void> _confirm(RegisteredCarpenter c) async {
    if (c.alreadyCaptured || !c.eligible) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConfirmSheet(c: c),
    );
    if ((confirmed ?? false) && mounted) {
      context.push('/capture/${widget.sessionId}/${c.id}');
    }
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.c,
    required this.similarName,
    required this.onSelect,
  });
  final RegisteredCarpenter c;
  final bool similarName;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final disabled = c.alreadyCaptured || !c.eligible;
    return Semantics(
      identifier: 'search_result',
      child: ListTile(
        enabled: !disabled,
        leading: CircleAvatar(
          backgroundImage:
              c.thumbnailUrl != null ? NetworkImage(c.thumbnailUrl!) : null,
          child: c.thumbnailUrl == null ? const Icon(Icons.person) : null,
        ),
        title: Row(
          children: [
            Flexible(child: Text(c.name)),
            if (similarName) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Similar name in results — confirm carefully',
                child: Icon(Icons.warning_amber,
                    size: 16, color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        subtitle: Text('${c.displayId} · ${c.territory} · •${c.phoneSuffix}'),
        trailing: c.alreadyCaptured
            ? StatusChip.attendance(c.attendanceState, label: 'Captured')
            : const Icon(Icons.chevron_right),
        onTap: disabled ? null : onSelect,
      ),
    );
  }
}

class _ConfirmSheet extends StatefulWidget {
  const _ConfirmSheet({required this.c});
  final RegisteredCarpenter c;
  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundImage:
                  c.thumbnailUrl != null ? NetworkImage(c.thumbnailUrl!) : null,
              child: c.thumbnailUrl == null
                  ? const Icon(Icons.person, size: 40)
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Text(c.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('${c.displayId} · ${c.territory} · phone •${c.phoneSuffix}',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          // Second identity cue is mandatory before capture (§8.9).
          Semantics(
            identifier: 'confirm_ack',
            child: CheckboxListTile(
              value: _acknowledged,
              onChanged: (v) => setState(() => _acknowledged = v ?? false),
              title: const Text('I confirmed this is the correct carpenter'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: Semantics(
              identifier: 'confirm_continue',
              child: FilledButton(
                onPressed:
                    _acknowledged ? () => Navigator.pop(context, true) : null,
                child: const Text('Continue to capture'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
