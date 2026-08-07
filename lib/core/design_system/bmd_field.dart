import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../responsive/breakpoints.dart';

/// The single form-control renderer (Guideline §5.2).
///
/// `inputDecorationTheme` already supplies the outlined border, the persistent
/// label and the error styling. This wrapper adds what a theme cannot express:
/// the responsive control height, the textarea minimum, an accessible required
/// marker, and a masked variant for sensitive values.
class BmdField extends StatelessWidget {
  const BmdField({
    required this.label,
    this.controller,
    this.initialValue,
    this.helper,
    this.errorText,
    this.validator,
    this.hint,
    this.keyboardType,
    this.enabled = true,
    this.required = false,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines = 1,
    this.identifier,
    this.onChanged,
    super.key,
  }) : maskedValue = null,
       onReveal = null;

  /// A textarea. Minimum 96px tall (§5.2) so a reason or objective is drafted
  /// in a box the user can actually read back.
  const BmdField.multiline({
    required this.label,
    this.controller,
    this.initialValue,
    this.helper,
    this.errorText,
    this.validator,
    this.hint,
    this.enabled = true,
    this.required = false,
    this.minLines = 3,
    this.maxLines = 6,
    this.identifier,
    this.onChanged,
    super.key,
  }) : keyboardType = TextInputType.multiline,
       obscureText = false,
       maskedValue = null,
       onReveal = null;

  /// A sensitive value under permission-gated reveal (§5.2, §10.2).
  ///
  /// This widget never holds the unmasked value. [maskedValue] is already
  /// masked by the caller, and [onReveal] — which the caller implements — owns
  /// the permission check and the audit write, so nothing here depends on RBAC
  /// or the audit emitter. When the caller cannot reveal it passes null and the
  /// affordance is *absent*: a disabled reveal button advertises data the user
  /// may not have.
  const BmdField.masked({
    required this.label,
    required String this.maskedValue,
    this.onReveal,
    this.helper,
    this.identifier,
    super.key,
  }) : controller = null,
       initialValue = null,
       errorText = null,
       validator = null,
       hint = null,
       keyboardType = null,
       enabled = true,
       required = false,
       obscureText = false,
       maxLines = 1,
       minLines = 1,
       onChanged = null;

  final String label;
  final TextEditingController? controller;
  final String? initialValue;

  /// Format, policy or privacy information (§5.2).
  final String? helper;

  /// An externally driven error. Wins over [validator] when non-null, so an
  /// async server rejection can override a synchronous local verdict.
  final String? errorText;

  final String? Function(String?)? validator;
  final String? hint;
  final TextInputType? keyboardType;
  final bool enabled;
  final bool required;

  /// Masks typed input (passwords). Distinct from [BmdField.masked], which
  /// reveals a stored value on demand rather than hiding what is being typed.
  final bool obscureText;
  final int maxLines;
  final int minLines;

  /// Stable a11y identifier for automated tests, matching [BmdButton].
  final String? identifier;

  final ValueChanged<String>? onChanged;

  final String? maskedValue;
  final Future<String?> Function()? onReveal;

  bool get _isMasked => maskedValue != null;

  @override
  Widget build(BuildContext context) {
    final built = _isMasked
        ? _MaskedField(
            label: label,
            maskedValue: maskedValue!,
            onReveal: onReveal,
            helper: helper,
            minHeight: _minHeight(context),
          )
        : _build(context);

    return identifier == null
        ? built
        : Semantics(identifier: identifier, child: built);
  }

  double _minHeight(BuildContext context) {
    if (minLines > 1) return BmdSize.textareaMin;
    return Breakpoint.of(context).isMobile
        ? BmdSize.controlHeightMobile
        : BmdSize.controlHeightWeb;
  }

  Widget _build(BuildContext context) {
    final field = TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      enabled: enabled,
      keyboardType: keyboardType,
      obscureText: obscureText,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      // errorText already renders the message; running the validator too would
      // let the local verdict replace the authoritative one on the next
      // rebuild.
      validator: errorText == null ? validator : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        errorText: errorText,
        constraints: BoxConstraints(minHeight: _minHeight(context)),
      ),
    );

    // The label carries the requirement, so a screen reader announces it. An
    // asterisk glyph alone is decoration.
    return required
        ? Semantics(label: '$label, required', child: field)
        : field;
  }
}

/// The masked variant. Read-only by construction: the field is a display of an
/// already-masked string, never an editor of a sensitive one.
class _MaskedField extends StatefulWidget {
  const _MaskedField({
    required this.label,
    required this.maskedValue,
    required this.onReveal,
    required this.helper,
    required this.minHeight,
  });

  final String label;
  final String maskedValue;
  final Future<String?> Function()? onReveal;
  final String? helper;
  final double minHeight;

  @override
  State<_MaskedField> createState() => _MaskedFieldState();
}

class _MaskedFieldState extends State<_MaskedField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.maskedValue,
  );
  String? _revealed;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reveal() async {
    if (_busy || widget.onReveal == null) return;
    setState(() => _busy = true);
    final value = await widget.onReveal!();
    if (!mounted) return;
    setState(() {
      _revealed = value;
      _busy = false;
      _controller.text = _revealed ?? widget.maskedValue;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      readOnly: true,
      enableInteractiveSelection: _revealed != null,
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        constraints: BoxConstraints(minHeight: widget.minHeight),
        suffixIcon: widget.onReveal == null || _revealed != null
            ? null
            : IconButton(
                tooltip: 'Reveal — this access is recorded',
                icon: const Icon(Icons.visibility_outlined),
                onPressed: _busy ? null : _reveal,
              ),
      ),
    );
  }
}

/// Debounced search with a permanently visible scope (Guideline §5.3).
///
/// [scopeLabel] is required and non-nullable: §5.3 says the search scope must
/// be visible, and a type enforces that better than a QA checklist.
class BmdSearchField extends StatefulWidget {
  const BmdSearchField({
    required this.onQueryChanged,
    required this.scopeLabel,
    this.debounce = const Duration(milliseconds: 300),
    this.hint,
    this.initialQuery,
    this.identifier,
    this.label = 'Search',
    super.key,
  });

  final ValueChanged<String> onQueryChanged;

  /// What this search actually matches — "Searches name, carpenter ID, phone
  /// suffix". Rendered as persistent helper text.
  final String scopeLabel;

  final Duration debounce;
  final String? hint;
  final String? initialQuery;
  final String? identifier;
  final String label;

  @override
  State<BmdSearchField> createState() => _BmdSearchFieldState();
}

class _BmdSearchFieldState extends State<BmdSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  Timer? _timer;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = (widget.initialQuery ?? '').isNotEmpty;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _hasText = value.isNotEmpty);
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => widget.onQueryChanged(value));
  }

  void _clear() {
    // No debounce on clear: a delayed clear reads as a broken control.
    _timer?.cancel();
    _controller.clear();
    setState(() => _hasText = false);
    widget.onQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final height = Breakpoint.of(context).isMobile
        ? BmdSize.controlHeightMobile
        : BmdSize.controlHeightWeb;

    final field = TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      onChanged: _onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.scopeLabel,
        prefixIcon: const Icon(Icons.search),
        constraints: BoxConstraints(minHeight: height),
        suffixIcon: _hasText
            ? IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: _clear,
              )
            : null,
      ),
    );

    return widget.identifier == null
        ? field
        : Semantics(identifier: widget.identifier, child: field);
  }
}
