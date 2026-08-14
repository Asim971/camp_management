import 'package:acsl_campaign/core/motion/motion_tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('durations ascend fast<base<slow', () {
    expect(MotionDur.fast < MotionDur.base, isTrue);
    expect(MotionDur.base < MotionDur.slow, isTrue);
  });

  testWidgets('reduced() zeroes a duration when animations are disabled', (
    tester,
  ) async {
    late Duration got;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (c) {
            got = reduced(c, MotionDur.base);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(got, Duration.zero);
  });

  testWidgets('reduced() keeps the duration when animations are enabled', (
    tester,
  ) async {
    late Duration got;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: false),
        child: Builder(
          builder: (c) {
            got = reduced(c, MotionDur.base);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(got, MotionDur.base);
  });
}
