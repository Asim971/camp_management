import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// The lineage rail — the chain of custody an attendance record moves through.
///
/// Two of the guideline's hardest requirements are about a record's *position
/// in a chain* rather than its final state: capture success is not upload
/// success (§8.11), and the machine's recommendation is not the human's
/// decision (§8.13). Both are lost when a record collapses to a single status
/// chip. So the chain itself is a component, and it renders identically on the
/// mobile queue, the CRM case, Carpenter 360 and the audit trail — a field
/// operator and a reviewer arguing about one record see the same picture.
///
/// Rules, deliberately narrow:
///  * solid node and solid connector mean this happened;
///  * a dashed connector with a hollow node means it has not happened yet —
///    a future step and a failed step are different facts;
///  * tone carries the outcome, and every node still names itself in text;
///  * the rail never wears brand red. Red is reserved for the primary action,
///    so the rail can never be mistaken for something you press.
enum LineageState {
  /// Completed successfully.
  done,

  /// Where the record is right now.
  current,

  /// Has not happened yet. Never rendered the same as a failure.
  pending,

  /// Attempted and failed. Recoverable — a retry is expected.
  failed,

  /// Could not proceed, and needs a different route (manual review, support).
  blocked,
}

@immutable
class LineageNode {
  const LineageNode({
    required this.label,
    required this.state,
    this.meta,
  });

  /// The step's own name. Always rendered — this is the greyscale channel.
  final String label;
  final LineageState state;

  /// Timestamp, retry count, actor — whatever makes the step reconstructable
  /// without opening the audit log.
  final String? meta;
}

class LineageRail extends StatelessWidget {
  const LineageRail({
    required this.nodes,
    this.axis = Axis.horizontal,
    super.key,
  });

  /// Horizontal for wide surfaces, vertical for narrow ones. Same semantics
  /// either way: nodes may be merged where a surface does not need the full
  /// chain, but the order is never rearranged and a link is never skipped.
  const LineageRail.vertical({required List<LineageNode> nodes, Key? key})
      : this(nodes: nodes, axis: Axis.vertical, key: key);

  final List<LineageNode> nodes;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    // Announced as an ordered list, so a screen-reader user gets the same
    // pending-versus-failed distinction the dashed connector gives everyone
    // else (§10.1).
    return Semantics(
      container: true,
      label: 'Record lineage, ${nodes.length} steps',
      child: axis == Axis.horizontal
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < nodes.length; i++)
                  Expanded(
                    child: _Node(
                      node: nodes[i],
                      isLast: i == nodes.length - 1,
                      axis: axis,
                    ),
                  ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < nodes.length; i++)
                  IntrinsicHeight(
                    child: _Node(
                      node: nodes[i],
                      isLast: i == nodes.length - 1,
                      axis: axis,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.node, required this.isLast, required this.axis});

  final LineageNode node;
  final bool isLast;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;
    final color = _colorFor(node.state, bmd);
    final labelColor = switch (node.state) {
      LineageState.pending => bmd.textFaint,
      LineageState.failed => bmd.error,
      LineageState.blocked => bmd.warning,
      _ => bmd.textPrimary,
    };

    final semantics = switch (node.state) {
      LineageState.done => 'completed',
      LineageState.current => 'in progress',
      LineageState.pending => 'not started',
      LineageState.failed => 'failed',
      LineageState.blocked => 'blocked',
    };

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          node.label,
          style: theme.textTheme.labelMedium?.copyWith(color: labelColor),
        ),
        if (node.meta != null) ...[
          const SizedBox(height: 2),
          Text(node.meta!, style: theme.textTheme.bodySmall),
        ],
      ],
    );

    final marker = _Marker(state: node.state, color: color, bmd: bmd);
    final connector = isLast
        ? const SizedBox.shrink()
        : _Connector(state: node.state, color: color, bmd: bmd, axis: axis);

    return Semantics(
      label:
          '${node.label}, $semantics${node.meta == null ? '' : ', ${node.meta}'}',
      excludeSemantics: true,
      child: axis == Axis.horizontal
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [marker, Expanded(child: connector)]),
                const SizedBox(height: BmdSpace.s1),
                Padding(
                  padding: const EdgeInsets.only(right: BmdSpace.s2),
                  child: text,
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    marker,
                    if (!isLast)
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 20),
                          child: connector,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: BmdSpace.s3),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: BmdSpace.s3),
                    child: text,
                  ),
                ),
              ],
            ),
    );
  }

  static Color _colorFor(LineageState state, BmdTokens bmd) => switch (state) {
        LineageState.done => bmd.success,
        LineageState.current => bmd.info,
        LineageState.pending => bmd.borderStrong,
        LineageState.failed => bmd.error,
        LineageState.blocked => bmd.warning,
      };
}

class _Marker extends StatelessWidget {
  const _Marker({required this.state, required this.color, required this.bmd});

  final LineageState state;
  final Color color;
  final BmdTokens bmd;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final isPending = state == LineageState.pending;

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isPending ? surface : color,
        border:
            isPending ? Border.all(color: bmd.borderStrong, width: 2) : null,
        boxShadow: [
          BoxShadow(color: surface, spreadRadius: 2),
          if (state == LineageState.current)
            BoxShadow(color: bmd.tintInfo, spreadRadius: 5),
        ],
      ),
    );
  }
}

/// Solid where the step has happened; dashed where it has not. This is the one
/// distinction the whole component exists to make.
class _Connector extends StatelessWidget {
  const _Connector({
    required this.state,
    required this.color,
    required this.bmd,
    required this.axis,
  });

  final LineageState state;
  final Color color;
  final BmdTokens bmd;
  final Axis axis;

  bool get _isDashed =>
      state == LineageState.current || state == LineageState.pending;

  @override
  Widget build(BuildContext context) {
    if (!_isDashed) {
      return axis == Axis.horizontal
          ? Container(height: 2, color: color)
          : Container(width: 2, color: color);
    }
    return CustomPaint(
      painter: _DashPainter(color: bmd.borderStrong, axis: axis),
      child: axis == Axis.horizontal
          ? const SizedBox(height: 2, width: double.infinity)
          : const SizedBox(width: 2, height: double.infinity),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter({required this.color, required this.axis});

  final Color color;
  final Axis axis;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 3.0;
    const gap = 3.0;
    final extent = axis == Axis.horizontal ? size.width : size.height;
    var pos = 0.0;
    while (pos < extent) {
      final end = (pos + dash).clamp(0.0, extent);
      canvas.drawLine(
        axis == Axis.horizontal ? Offset(pos, 1) : Offset(1, pos),
        axis == Axis.horizontal ? Offset(end, 1) : Offset(1, end),
        paint,
      );
      pos += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) =>
      old.color != color || old.axis != axis;
}
