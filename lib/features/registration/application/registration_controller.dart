import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/trace/trace_id.dart';
import '../../../domain/registration/registration.dart';

class RegistrationState {
  const RegistrationState({
    this.results = const AsyncData([]),
    this.basket = const {},
    this.registering = false,
    this.message,
  });

  final AsyncValue<List<RegisteredCarpenter>> results;
  final Map<String, RegisteredCarpenter> basket; // keyed by id (dedup)
  final bool registering;
  final String? message;

  RegistrationState copyWith({
    AsyncValue<List<RegisteredCarpenter>>? results,
    Map<String, RegisteredCarpenter>? basket,
    bool? registering,
    String? message,
  }) => RegistrationState(
    results: results ?? this.results,
    basket: basket ?? this.basket,
    registering: registering ?? this.registering,
    message: message,
  );
}

/// Registration Workspace (W-06). Resolves participants against the
/// campaign service's carpenter master and builds a registration basket.
///
/// Since D1 (foundation spec, 2026-08-10) the master is OURS: a missing
/// profile becomes a profile request that immediately creates a local
/// provisional carpenter (spec 2a.D1) — returned by the server and added
/// straight to the basket below, so request → basket → register completes
/// in one visit. Ratification/merge against BMD Sales is sub-project 8's
/// adjudication queue, not something this workspace waits for.
class RegistrationController
    extends AutoDisposeFamilyNotifier<RegistrationState, String> {
  @override
  RegistrationState build(String campaignId) => const RegistrationState();

  Future<void> search(String query) async {
    if (query.trim().length < 2) {
      state = state.copyWith(results: const AsyncData([]));
      return;
    }
    state = state.copyWith(results: const AsyncLoading());
    final res = await ref
        .read(registrationRepositoryProvider)
        .searchMaster(query);
    state = state.copyWith(
      results: res.fold(
        AsyncData.new,
        (f) => AsyncError(f, StackTrace.current),
      ),
    );
  }

  void addToBasket(RegisteredCarpenter c) {
    if (state.basket.containsKey(c.id)) return;
    state = state.copyWith(basket: {...state.basket, c.id: c});
  }

  void removeFromBasket(String id) {
    final next = {...state.basket}..remove(id);
    state = state.copyWith(basket: next);
  }

  Future<void> registerBasket() async {
    if (state.basket.isEmpty) return;
    state = state.copyWith(registering: true, message: null);
    final res = await ref
        .read(registrationRepositoryProvider)
        .register(arg, state.basket.keys.toList(), trace: TraceId.generate());
    state = res.fold(
      (_) => state.copyWith(
        registering: false,
        basket: {},
        message: 'Registered ${state.basket.length} participant(s)',
      ),
      (f) => state.copyWith(
        registering: false,
        message: f.message ?? 'Registration failed',
      ),
    );
  }

  Future<void> requestNewProfile(String name, String phone) async {
    final res = await ref
        .read(registrationRepositoryProvider)
        .requestNewProfile(arg, name, phone);
    state = res.fold(
      (carpenter) => state.copyWith(
        basket: {...state.basket, carpenter.id: carpenter},
        message: 'Profile request submitted — pending sync',
      ),
      (f) => state.copyWith(message: f.message ?? 'Request failed'),
    );
  }
}

final registrationControllerProvider = NotifierProvider.autoDispose
    .family<RegistrationController, RegistrationState, String>(
      RegistrationController.new,
    );
