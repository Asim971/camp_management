# E2E fixtures

`sample_face.jpg` is the image returned by `FakeCaptureSource` during Maestro
runs (E2E build only). The capture pipeline treats it as opaque bytes — quality
is decided by `E2EQualityChecker`, not the image — so any file works for flow
testing. Replace with a real, consented sample face if you later exercise the
ML Kit quality path locally. Never commit a real person's photo.
