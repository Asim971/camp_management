import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/di/providers.dart';
import '../../../core/trace/trace_id.dart';
import '../../../domain/campaign/campaign_draft.dart';

class WizardState {
  const WizardState({
    this.step = 0,
    this.draft = const CampaignDraft(),
    this.savedId,
    this.saving = false,
    this.submitting = false,
    this.showErrors = false,
    this.submittedId,
    this.error,
  });

  final int step; // 0..4
  final CampaignDraft draft;
  final String? savedId; // set after first successful draft save
  final bool saving;
  final bool submitting;
  final bool showErrors; // reveal inline errors after a blocked Continue/Submit
  final String? submittedId; // set on successful submit-for-approval
  final String? error;

  static const lastStep = 4;

  WizardState copyWith({
    int? step,
    CampaignDraft? draft,
    String? savedId,
    bool? saving,
    bool? submitting,
    bool? showErrors,
    String? submittedId,
    String? error,
  }) => WizardState(
    step: step ?? this.step,
    draft: draft ?? this.draft,
    savedId: savedId ?? this.savedId,
    saving: saving ?? this.saving,
    submitting: submitting ?? this.submitting,
    showErrors: showErrors ?? this.showErrors,
    submittedId: submittedId ?? this.submittedId,
    error: error,
  );
}

/// Drives the 5-step Create Campaign wizard (W-03). Holds the draft, validates
/// per step, persists drafts, and submits for approval only when every step is
/// valid.
class WizardController extends AutoDisposeNotifier<WizardState> {
  static const _uuid = Uuid();

  @override
  WizardState build() => const WizardState();

  void edit(CampaignDraft Function(CampaignDraft) mutate) =>
      state = state.copyWith(draft: mutate(state.draft), showErrors: false);

  void addSession() => edit(
    (d) => d.copyWith(
      sessions: [
        ...d.sessions,
        CampaignSessionDraft(id: _uuid.v4()),
      ],
    ),
  );

  void removeSession(String id) => edit(
    (d) => d.copyWith(sessions: d.sessions.where((s) => s.id != id).toList()),
  );

  void updateSession(CampaignSessionDraft session) => edit(
    (d) => d.copyWith(
      sessions: d.sessions
          .map((s) => s.id == session.id ? session : s)
          .toList(),
    ),
  );

  void back() {
    if (state.step > 0) state = state.copyWith(step: state.step - 1);
  }

  /// Advance only if the current step validates; otherwise reveal errors.
  void next() {
    if (state.draft.validate(state.step).isNotEmpty) {
      state = state.copyWith(showErrors: true);
      return;
    }
    if (state.step < WizardState.lastStep) {
      state = state.copyWith(step: state.step + 1, showErrors: false);
    }
  }

  Future<void> saveDraft() async {
    state = state.copyWith(saving: true, error: null);
    final repo = ref.read(campaignRepositoryProvider);
    final result = state.savedId == null
        ? await repo.createDraft(state.draft, trace: TraceId.generate())
        : await repo.updateDraft(state.savedId!, state.draft);
    state = result.fold(
      (c) => state.copyWith(saving: false, savedId: c.id),
      (f) => state.copyWith(saving: false, error: f.message ?? 'Save failed'),
    );
  }

  Future<void> submit() async {
    if (!state.draft.isValid) {
      state = state.copyWith(showErrors: true);
      return;
    }
    state = state.copyWith(submitting: true, error: null);
    final repo = ref.read(campaignRepositoryProvider);

    // Save-then-submit is a single user action, so both calls share one trace.
    final trace = TraceId.generate();

    // Ensure a persisted draft, then submit it.
    final saved = state.savedId == null
        ? await repo.createDraft(state.draft, trace: trace)
        : await repo.updateDraft(state.savedId!, state.draft);

    await saved.fold(
      (campaign) async {
        final submitted = await repo.submitForApproval(
          campaign.id,
          trace: trace,
        );
        state = submitted.fold(
          (c) => state.copyWith(submitting: false, submittedId: c.id),
          (f) => state.copyWith(
            submitting: false,
            savedId: campaign.id,
            error: f.message ?? 'Submit failed',
          ),
        );
      },
      (f) async => state = state.copyWith(
        submitting: false,
        error: f.message ?? 'Save failed',
      ),
    );
  }
}

final wizardControllerProvider =
    AutoDisposeNotifierProvider<WizardController, WizardState>(
      WizardController.new,
    );
