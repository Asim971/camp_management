import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Abstraction over the camera so the capture flow is deterministic under E2E.
/// Production uses [CameraCaptureSource] (real hardware); Maestro runs use
/// [FakeCaptureSource], which returns a bundled asset and a placeholder preview
/// so tests don't depend on emulator camera behavior (TESTING_MAESTRO.md §3.2).
abstract interface class CaptureSource {
  Future<void> initialize();
  bool get isReady;
  Widget buildPreview();
  Future<List<int>> takePicture();
  Future<void> dispose();
}

class CameraCaptureSource implements CaptureSource {
  CameraController? _controller;

  @override
  bool get isReady => _controller?.value.isInitialized ?? false;

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final controller =
        CameraController(front, ResolutionPreset.medium, enableAudio: false);
    await controller.initialize();
    _controller = controller;
  }

  @override
  Widget buildPreview() =>
      isReady ? CameraPreview(_controller!) : const SizedBox.shrink();

  @override
  Future<List<int>> takePicture() async {
    final file = await _controller!.takePicture();
    return file.readAsBytes();
  }

  @override
  Future<void> dispose() async => _controller?.dispose();
}

/// Test double: no real camera. Returns a bundled image and a labelled preview.
class FakeCaptureSource implements CaptureSource {
  @override
  bool get isReady => true;

  @override
  Future<void> initialize() async {}

  @override
  Widget buildPreview() => ColoredBox(
        color: Colors.black26,
        child: Center(
          child: Semantics(
            identifier: 'e2e_camera_preview',
            child: const Text('E2E camera'),
          ),
        ),
      );

  @override
  Future<List<int>> takePicture() async {
    final data = await rootBundle.load('assets/e2e/sample_face.jpg');
    return data.buffer.asUint8List();
  }

  @override
  Future<void> dispose() async {}
}
