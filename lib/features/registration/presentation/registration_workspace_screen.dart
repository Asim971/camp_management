import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/bmd_button.dart';
import '../../../core/design_system/status_chip.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../domain/common/status.dart';
import '../application/registration_controller.dart';

/// Registration Workspace (W-06). Search Sales Eco master on the left, build a
/// registration basket on the right with eligibility warnings.
class RegistrationWorkspaceScreen extends ConsumerWidget {
  const RegistrationWorkspaceScreen({required this.campaignId, super.key});
  final String campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(registrationControllerProvider(campaignId));

    ref.listen(
      registrationControllerProvider(campaignId).select((s) => s.message),
      (_, msg) {
        if (msg != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
      },
    );

    final search = _SearchPanel(campaignId: campaignId, state: state);
    final basket = _BasketPanel(campaignId: campaignId, state: state);

    return AdaptiveScaffold(
      title: 'Registration',
      selectedIndex: 1,
      body: Breakpoint.of(context).isDesktopUp
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: search),
                const SizedBox(width: 24),
                SizedBox(width: 360, child: basket),
              ],
            )
          : ListView(
              children: [
                SizedBox(height: 420, child: search),
                const SizedBox(height: 16),
                basket,
              ],
            ),
    );
  }
}

class _SearchPanel extends ConsumerWidget {
  const _SearchPanel({required this.campaignId, required this.state});
  final String campaignId;
  final RegistrationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(registrationControllerProvider(campaignId).notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search carpenter master (name, ID, phone suffix)',
          ),
          onChanged: c.search,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: state.results.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('Search failed')),
            data: (list) => list.isEmpty
                ? _EmptySearch(campaignId: campaignId)
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final person = list[i];
                      final inBasket = state.basket.containsKey(person.id);
                      final blocked =
                          person.alreadyCaptured || !person.eligible;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: person.thumbnailUrl != null
                              ? NetworkImage(person.thumbnailUrl!)
                              : null,
                          child: person.thumbnailUrl == null
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(person.name),
                        subtitle: Text(
                          '${person.displayId} · ${person.territory} · •${person.phoneSuffix}',
                        ),
                        trailing: blocked
                            ? const StatusChip(
                                label: 'Ineligible',
                                tone: StatusTone.warning,
                              )
                            : IconButton(
                                icon: Icon(
                                  inBasket
                                      ? Icons.check
                                      : Icons.add_circle_outline,
                                ),
                                onPressed: inBasket
                                    ? null
                                    : () => c.addToBasket(person),
                              ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _EmptySearch extends ConsumerWidget {
  const _EmptySearch({required this.campaignId});
  final String campaignId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Empty-state distinguishes "no record" from "request a new profile" (§5.3).
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No matching carpenter in the master.'),
          const SizedBox(height: 8),
          BmdButton(
            label: 'Request new profile',
            variant: BmdButtonVariant.outlined,
            onPressed: () => _showRequestDialog(context, ref, campaignId),
          ),
        ],
      ),
    );
  }
}

Future<void> _showRequestDialog(
  BuildContext context,
  WidgetRef ref,
  String campaignId,
) async {
  final name = TextEditingController();
  final phone = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Request new Sales Eco profile'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          TextField(
            controller: phone,
            decoration: const InputDecoration(labelText: 'Phone'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Creates a Sales Eco request. The participant shows as '
            '"Pending profile sync" until reconciliation — no local record is created.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            ref
                .read(registrationControllerProvider(campaignId).notifier)
                .requestNewProfile(name.text, phone.text);
            Navigator.pop(ctx);
          },
          child: const Text('Submit request'),
        ),
      ],
    ),
  );
}

class _BasketPanel extends ConsumerWidget {
  const _BasketPanel({required this.campaignId, required this.state});
  final String campaignId;
  final RegistrationState state;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(registrationControllerProvider(campaignId).notifier);
    final items = state.basket.values.toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Registration basket (${items.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Add carpenters from search results.'),
              )
            else
              for (final p in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.name),
                  subtitle: Text(p.displayId),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => c.removeFromBasket(p.id),
                  ),
                ),
            const SizedBox(height: 12),
            BmdButton(
              label: 'Register ${items.length} participant(s)',
              loading: state.registering,
              onPressed: items.isEmpty ? null : c.registerBasket,
            ),
          ],
        ),
      ),
    );
  }
}
