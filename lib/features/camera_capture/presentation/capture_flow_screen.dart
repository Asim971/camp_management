import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/consent/notice.dart';
import '../../../core/design_system/bmd_button.dart';
import '../../../core/l10n/locale_controller.dart';
import '../../../core/media/capture_source.dart';
import '../../../core/media/face_quality.dart';
import '../application/capture_controller.dart';

/// Purpose notice + camera capture (M-03). Camera-only — the gallery is never
/// offered. Neutral framing guidance; red is reserved for explicit capture
/// failure, not normal framing (§8.10). No match score is ever shown here.
class CaptureFlowScreen extends ConsumerStatefulWidget {
  const CaptureFlowScreen({
    required this.sessionId,
    required this.carpenterId,
    super.key,
  });

  final String sessionId;
  final String carpenterId;

  @override
  ConsumerState<CaptureFlowScreen> createState() => _CaptureFlowScreenState();
}

class _CaptureFlowScreenState extends ConsumerState<CaptureFlowScreen> {
  /// Read in [initState], NOT as a lazy `late final` initializer. `dispose()`
  /// calls `_source.dispose()`, which on a screen the user left before reaching
  /// the camera would be the FIRST touch of the field — running `ref.read`
  /// after the widget was disposed, which throws `Bad state: Cannot use "ref"
  /// after the widget was disposed`. Backing out of the notice step is the
  /// ordinary case, not an edge one.
  late final CaptureSource _source;
  Future<void>? _cameraInit;

  CaptureArgs get _args =>
      CaptureArgs(sessionId: widget.sessionId, carpenterId: widget.carpenterId);

  @override
  void initState() {
    super.initState();
    _source = ref.read(captureSourceProvider);
    // The notice has to be resolved before it can be shown, let alone accepted.
    unawaited(
      ref
          .read(captureControllerProvider(_args).notifier)
          .loadNotice(_defaultNoticeLanguage()),
    );
  }

  /// The app locale is only the DEFAULT notice language (T-2.3.3) — the carpenter
  /// picks their own on the notice step.
  ///
  /// Falls back to `'en'` rather than the device locale on purpose: an
  /// unsupported device language (say `fr`) has no notice to resolve, and
  /// consent fails closed, so reading the raw platform locale would block every
  /// capture on that phone. `localeControllerProvider` only ever holds a locale
  /// the app actually ships.
  String _defaultNoticeLanguage() =>
      ref.read(localeControllerProvider)?.languageCode ?? 'en';

  Future<void> _initCamera() async {
    await _source.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (!_source.isReady) return;
    final bytes = await _source.takePicture();
    await ref.read(captureControllerProvider(_args).notifier).onCaptured(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(captureControllerProvider(_args));
    final controller = ref.read(captureControllerProvider(_args).notifier);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        title: const Text('Capture attendance'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: switch (state.step) {
            CaptureStep.purposeNotice => _PurposeNotice(
              notice: state.notice,
              blocked: state.noticeBlocked,
              onSelectLanguage: controller.selectNoticeLanguage,
              onAccept: controller.acceptNotice,
            ),
            CaptureStep.positioning => _Positioning(
              onReady: () {
                controller.beginCamera();
                _cameraInit ??= _initCamera();
              },
            ),
            CaptureStep.liveCamera => _LiveCamera(
              init: _cameraInit,
              source: _source,
              onCapture: _capture,
            ),
            CaptureStep.qualityResult => _QualityResult(
              quality: state.quality!,
              submitting: state.submitting,
              error: state.error,
              onSubmit: controller.submit,
              onRecapture: controller.recapture,
            ),
            CaptureStep.captured => _Captured(
              attendanceId: state.attendanceId!,
            ),
          },
        ),
      ),
    );
  }
}

/// The notice step. Renders the notice the repository RESOLVED — never
/// hardcoded text, because the consent record stores a hash of what was shown
/// and hardcoded text would make that hash prove the wrong thing.
///
/// Stateless: the selected language is the resolved notice's own
/// [ConsentNotice.language], so the toggle cannot disagree with the text under
/// it. A local `_lang` field would be a second source of truth for the one fact
/// that has to be single.
class _PurposeNotice extends StatelessWidget {
  const _PurposeNotice({
    required this.notice,
    required this.blocked,
    required this.onSelectLanguage,
    required this.onAccept,
  });

  final ConsentNotice? notice;

  /// No notice resolved (spec D7). Nothing below offers a route to the camera.
  final bool blocked;

  final void Function(String language) onSelectLanguage;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final shown = notice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Language choice BEFORE acceptance (§10.3). Kept available while
        // blocked as well: the other language may resolve, and offering it is a
        // way forward that is not a way to the camera.
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'en', label: Text('English')),
            ButtonSegment(value: 'bn', label: Text('বাংলা')),
          ],
          selected: {shown?.language == 'bn' ? 'bn' : 'en'},
          onSelectionChanged: (s) => onSelectLanguage(s.first),
        ),
        const SizedBox(height: 16),
        Expanded(child: _body(context, shown)),
        const SizedBox(height: 16),
        // The accept affordance exists ONLY when there is resolved text to
        // accept — an accepted blank notice is the defect this guards.
        if (!blocked && shown != null) ...[
          BmdButton(
            label: 'Accept and continue',
            identifier: 'capture_accept',
            onPressed: onAccept,
          ),
          const SizedBox(height: 8),
        ],
        BmdButton(
          label: 'Use manual route',
          variant: BmdButtonVariant.text,
          onPressed: () {
            /* policy-gated manual path */
          },
        ),
      ],
    );
  }

  Widget _body(BuildContext context, ConsentNotice? shown) {
    if (blocked) {
      return Column(
        key: const Key('capture_notice_blocked'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.gpp_maybe_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            'The consent notice could not be shown',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'This capture cannot continue until the notice is available. Try '
            'the other language, or record this attendance through the manual '
            'route.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    // Still resolving. Deliberately not the blocking message: "unavailable" is
    // a claim about a finished attempt, not about one still in flight.
    if (shown == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Scrollable: a real legal notice is longer than any phone screen, and the
    // person consenting has to be able to read all of it.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(shown.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(shown.body),
        ],
      ),
    );
  }
}

class _Positioning extends StatelessWidget {
  const _Positioning({required this.onReady});
  final VoidCallback onReady;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        const Icon(Icons.face_retouching_natural, size: 96),
        const SizedBox(height: 16),
        Text(
          'Position the face inside the guide, with even lighting.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const Spacer(),
        BmdButton(
          label: "I'm ready",
          identifier: 'capture_ready',
          onPressed: onReady,
        ),
      ],
    );
  }
}

class _LiveCamera extends StatelessWidget {
  const _LiveCamera({
    required this.init,
    required this.source,
    required this.onCapture,
  });
  final Future<void>? init;
  final CaptureSource source;
  final Future<void> Function() onCapture;
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: init,
      builder: (context, snap) {
        final ready = source.isReady;
        return Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ready
                    ? source.buildPreview()
                    : const ColoredBox(
                        color: Colors.black12,
                        child: Center(child: CircularProgressIndicator()),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 56, // 52–56px confirmation control (§3.2)
              child: BmdButton(
                label: 'Capture',
                icon: Icons.camera_alt_outlined,
                identifier: 'capture_shutter',
                onPressed: ready ? () => onCapture() : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QualityResult extends StatelessWidget {
  const _QualityResult({
    required this.quality,
    required this.submitting,
    required this.error,
    required this.onSubmit,
    required this.onRecapture,
  });
  final FaceQuality quality;
  final bool submitting;
  final String? error;
  final Future<void> Function() onSubmit;
  final VoidCallback onRecapture;

  String _label(QualityIssue i) => switch (i) {
    QualityIssue.noFace => 'No face detected',
    QualityIssue.multipleFaces => 'More than one face detected',
    QualityIssue.blur => 'Image is blurry',
    QualityIssue.poorLight => 'Lighting is too low',
    QualityIssue.orientation => 'Straighten the device',
  };

  @override
  Widget build(BuildContext context) {
    final passes = quality.passes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          passes ? Icons.check_circle_outline : Icons.info_outline,
          size: 64,
          color: passes ? null : Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 12),
        Text(
          passes ? 'Capture looks good' : 'Review required before submitting',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final issue in quality.issues)
          ListTile(
            dense: true,
            leading: const Icon(Icons.error_outline),
            title: Text(_label(issue)),
          ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const Spacer(),
        if (passes)
          BmdButton(
            label: 'Submit',
            identifier: 'capture_submit',
            loading: submitting,
            onPressed: onSubmit,
          ),
        const SizedBox(height: 8),
        BmdButton(
          label: 'Recapture',
          variant: BmdButtonVariant.outlined,
          identifier: 'capture_recapture',
          onPressed: submitting ? null : onRecapture,
        ),
      ],
    );
  }
}

class _Captured extends StatelessWidget {
  const _Captured({required this.attendanceId});
  final String attendanceId;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        const Icon(Icons.cloud_queue, size: 72),
        const SizedBox(height: 16),
        Text(
          'Attendance captured and queued',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Your capture is saved on this device and will sync automatically. '
          'You do not need to recapture if sync is delayed.',
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        BmdButton(
          label: 'Done',
          identifier: 'capture_done',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
