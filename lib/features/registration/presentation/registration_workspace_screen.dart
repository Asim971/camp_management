import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_shell.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/design_system/bmd_button.dart';
import '../../../core/design_system/bmd_field.dart';
import '../../../core/design_system/bmd_overlays.dart';
import '../../../core/design_system/status_chip.dart';
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
      },
    );

    final search = _SearchPanel(campaignId: campaignId, state: state);
    final basket = _BasketPanel(campaignId: campaignId, state: state);

    return AppShell(
      title: 'Registration',
      breadcrumb: const ['Campaigns'],
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
        BmdSearchField(
          identifier: 'registration_search',
          label: 'Search carpenter master',
          scopeLabel: 'Searches name, carpenter ID and phone suffix',
          onQueryChanged: c.search,
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
                            : Semantics(
                                identifier: 'registration_add_${person.id}',
                                enabled: !inBasket,
                                child: IconButton(
                                  icon: Icon(
                                    inBasket
                                        ? Icons.check
                                        : Icons.add_circle_outline,
                                  ),
                                  onPressed: inBasket
                                      ? null
                                      : () => c.addToBasket(person),
                                ),
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
            identifier: 'registration_request_profile',
            label: 'Request new profile',
            variant: BmdButtonVariant.outlined,
            onPressed: () => _showRequestProfileSheet(context, ref, campaignId),
          ),
        ],
      ),
    );
  }
}

Future<void> _showRequestProfileSheet(
  BuildContext context,
  WidgetRef ref,
  String campaignId,
) async {
  final name = TextEditingController();
  final phone = TextEditingController();

  await showBmdSideSheet<void>(
    context: context,
    title: 'Request new carpenter profile',
    builder: (_) => _ProfileRequestFields(name: name, phone: phone),
    actions: [
      Builder(
        builder: (sheetContext) => BmdButton(
          identifier: 'profile_submit',
          label: 'Submit request',
          onPressed: () {
            ref
                .read(registrationControllerProvider(campaignId).notifier)
                .requestNewProfile(name.text, phone.text);
            Navigator.pop(sheetContext);
          },
        ),
      ),
    ],
  );
}

/// Owns [name]/[phone] for exactly as long as the sheet's fields are in the
/// tree.
///
/// Disposing them right after `showBmdSideSheet`'s `await` (as this used to)
/// is too early: that Future resolves the instant `Navigator.pop` runs —
/// `Route.didPop` completes it synchronously — while the sheet's own exit
/// transition is still animating and its [BmdField]s are still mounted and
/// listening. A later frame of that animation then touches the already
/// disposed controller (`ChangeNotifier.debugAssertNotDisposed` inside
/// `_AnimatedState.didUpdateWidget`, reached from the [TextFormField] this
/// widget renders), which aborts that frame's element-tree walk partway and
/// leaves an ancestor `InheritedElement` with a dependent that never got to
/// remove itself — surfacing several frames later as framework.dart's
/// `'_dependents.isEmpty': is not true` red screen when the sheet's route is
/// finally torn down.
///
/// Disposing from [State.dispose] instead ties their lifetime to this
/// widget's own: the framework only calls it once this element actually
/// unmounts, which for a route happens after its exit animation completes —
/// the same idiom `_BmdConfirmDialog` above already uses for its reason
/// field.
class _ProfileRequestFields extends StatefulWidget {
  const _ProfileRequestFields({required this.name, required this.phone});

  final TextEditingController name;
  final TextEditingController phone;

  @override
  State<_ProfileRequestFields> createState() => _ProfileRequestFieldsState();
}

class _ProfileRequestFieldsState extends State<_ProfileRequestFields> {
  @override
  void dispose() {
    widget.name.dispose();
    widget.phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        BmdField(
          identifier: 'profile_name',
          label: 'Full name',
          controller: widget.name,
          required: true,
        ),
        const SizedBox(height: BmdSpace.s3),
        BmdField(
          identifier: 'profile_phone',
          label: 'Phone',
          controller: widget.phone,
          keyboardType: TextInputType.phone,
          required: true,
        ),
        const SizedBox(height: BmdSpace.s3),
        const Text(
          'Creates a local profile pending ratification and adds the '
          'participant to your basket.',
        ),
      ],
    );
  }
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
              identifier: 'registration_submit',
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
