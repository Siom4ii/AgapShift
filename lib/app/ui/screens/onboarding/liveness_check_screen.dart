import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../theme/agap_colors.dart';

enum _LivenessStep { blink, turnLeft, turnRight, done }

enum _FaceState { none, multiple, single }

/// Basic real liveness check using on-device face detection:
/// - detect a face
/// - require a blink
/// - require a head turn left + right
/// Then capture a selfie image for KYC upload.
class LivenessCheckScreen extends StatefulWidget {
  const LivenessCheckScreen({super.key});

  @override
  State<LivenessCheckScreen> createState() => _LivenessCheckScreenState();
}

class _LivenessCheckScreenState extends State<LivenessCheckScreen> {
  CameraController? _camera;
  FaceDetector? _detector;
  bool _busy = false;
  bool _analyzing = false;
  String? _error;
  bool _captured = false;

  _FaceState _faceState = _FaceState.none;
  String _faceMessage = 'No face detected';

  _LivenessStep _step = _LivenessStep.blink;
  bool _sawEyesOpen = false;

  Timer? _throttle;
  Timer? _autoCaptureTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _throttle?.cancel();
    _autoCaptureTimer?.cancel();
    _camera?.dispose();
    _detector?.close();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final cam = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await cam.initialize();
      await cam.setFlashMode(FlashMode.off);

      final detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableLandmarks: false,
          enableContours: false,
          enableTracking: true,
          performanceMode: FaceDetectorMode.fast,
        ),
      );

      if (!mounted) return;
      _camera = cam;
      _detector = detector;
      setState(() => _busy = false);

      await cam.startImageStream(_onFrame);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  void _onFrame(CameraImage image) {
    if (!mounted) return;
    if (_detector == null) return;
    if (_analyzing) return;
    if (_throttle != null) return;
    _throttle = Timer(const Duration(milliseconds: 250), () {
      _throttle?.cancel();
      _throttle = null;
    });
    _analyzing = true;
    unawaited(_analyze(image));
  }

  Future<void> _analyze(CameraImage image) async {
    try {
      final cam = _camera;
      final detector = _detector;
      if (cam == null || detector == null) return;
      if (_captured) return;

      // ML Kit expects NV21 bytes on Android for YUV420 stream frames.
      final bytes = _yuv420ToNv21(image);
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _rotationForController(cam),
          format: InputImageFormat.nv21,
          // For NV21 we construct a tight buffer with row stride = width.
          bytesPerRow: image.width,
        ),
      );

      final faces = await detector.processImage(inputImage);
      if (!mounted) return;
      if (faces.isEmpty) {
        if (_faceState != _FaceState.none) {
          setState(() {
            _faceState = _FaceState.none;
            _faceMessage = 'No face detected';
          });
        }
        return;
      }
      if (faces.length > 1) {
        if (_faceState != _FaceState.multiple) {
          setState(() {
            _faceState = _FaceState.multiple;
            _faceMessage = 'Multiple faces detected';
          });
        }
        return;
      }

      if (_faceState != _FaceState.single) {
        setState(() {
          _faceState = _FaceState.single;
          _faceMessage = 'Face detected';
        });
      }
      final face = faces.first;

      final left = face.leftEyeOpenProbability ?? 1.0;
      final right = face.rightEyeOpenProbability ?? 1.0;
      final eyesOpen = left > 0.65 && right > 0.65;
      final blinked = left < 0.25 || right < 0.25;
      final yaw = face.headEulerAngleY ?? 0.0; // +left, -right (device dependent)
      final pitch = face.headEulerAngleX ?? 0.0;
      final roll = face.headEulerAngleZ ?? 0.0;

      _maybeScheduleAutoCapture(yaw: yaw, pitch: pitch, roll: roll);

      setState(() {
        // Only evaluate liveness steps when exactly one face is present.
        if (_faceState != _FaceState.single) return;
        if (_step == _LivenessStep.blink) {
          if (eyesOpen) _sawEyesOpen = true;
          if (_sawEyesOpen && blinked) {
            _step = _LivenessStep.turnLeft;
          }
        } else if (_step == _LivenessStep.turnLeft) {
          // Accept either sign as "left" depending on device.
          if (yaw.abs() > 18 && yaw > 0) {
            _step = _LivenessStep.turnRight;
          }
        } else if (_step == _LivenessStep.turnRight) {
          if (yaw.abs() > 18 && yaw < 0) {
            _step = _LivenessStep.done;
          }
        }
      });
    } catch (_) {
      // Ignore transient frame errors.
    } finally {
      _analyzing = false;
    }
  }

  static Uint8List _yuv420ToNv21(CameraImage image) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final width = image.width;
    final height = image.height;
    final ySize = width * height;
    final uvSize = width * height ~/ 2;
    final out = Uint8List(ySize + uvSize);

    // Copy Y respecting rowStride (Android often pads each row).
    final yRowStride = yPlane.bytesPerRow;
    final yPixelStride = yPlane.bytesPerPixel ?? 1;
    var outIndex = 0;
    for (var row = 0; row < height; row++) {
      var yRow = row * yRowStride;
      for (var col = 0; col < width; col++) {
        out[outIndex++] = yBytes[yRow + col * yPixelStride];
      }
    }

    // Interleave VU for NV21.
    final uRowStride = uPlane.bytesPerRow;
    final vRowStride = vPlane.bytesPerRow;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;
    outIndex = ySize;
    for (var row = 0; row < height ~/ 2; row++) {
      final uRow = row * uRowStride;
      final vRow = row * vRowStride;
      for (var col = 0; col < width ~/ 2; col++) {
        final uIndex = uRow + col * uPixelStride;
        final vIndex = vRow + col * vPixelStride;
        out[outIndex++] = vBytes[vIndex];
        out[outIndex++] = uBytes[uIndex];
      }
    }

    return out;
  }

  static InputImageRotation _rotationForController(CameraController cam) {
    final sensorOrientation = cam.description.sensorOrientation;
    final deviceOrientation = cam.value.deviceOrientation;
    final deviceDegrees = switch (deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };

    final rotationDegrees = cam.description.lensDirection == CameraLensDirection.front
        ? (sensorOrientation + deviceDegrees) % 360
        : (sensorOrientation - deviceDegrees + 360) % 360;

    return switch (rotationDegrees) {
      90 => InputImageRotation.rotation90deg,
      180 => InputImageRotation.rotation180deg,
      270 => InputImageRotation.rotation270deg,
      _ => InputImageRotation.rotation0deg,
    };
  }

  String get _instruction => switch (_step) {
        _LivenessStep.blink => 'Look at the camera and blink once.',
        _LivenessStep.turnLeft => 'Turn your head to the left.',
        _LivenessStep.turnRight => 'Turn your head to the right.',
        _LivenessStep.done => 'Hold still facing the camera…',
      };

  double get _progress => switch (_step) {
        _LivenessStep.blink => 0.33,
        _LivenessStep.turnLeft => 0.55,
        _LivenessStep.turnRight => 0.77,
        _LivenessStep.done => 1.0,
      };

  bool get _canProceed => _faceState == _FaceState.single;

  bool get _shouldAutoCapture =>
      _step == _LivenessStep.done && _faceState == _FaceState.single && !_busy && !_captured;

  void _maybeScheduleAutoCapture({
    required double yaw,
    required double pitch,
    required double roll,
  }) {
    // Only capture when the user holds still, facing forward.
    if (!_shouldAutoCapture) {
      _autoCaptureTimer?.cancel();
      _autoCaptureTimer = null;
      return;
    }
    final frontFacing = yaw.abs() < 8 && pitch.abs() < 8 && roll.abs() < 10;
    if (!frontFacing) {
      _autoCaptureTimer?.cancel();
      _autoCaptureTimer = null;
      return;
    }
    if (_autoCaptureTimer != null) return;
    _autoCaptureTimer = Timer(const Duration(milliseconds: 700), () {
      _autoCaptureTimer?.cancel();
      _autoCaptureTimer = null;
      if (!mounted) return;
      if (_shouldAutoCapture) {
        _captured = true;
        _capture();
      }
    });
  }

  Color get _statusColor => switch (_faceState) {
        _FaceState.single => const Color(0xFF16A34A),
        _FaceState.multiple => const Color(0xFFEF4444),
        _FaceState.none => const Color(0xFF64748B),
      };

  IconData get _statusIcon => switch (_faceState) {
        _FaceState.single => Icons.check_circle_rounded,
        _FaceState.multiple => Icons.error_outline_rounded,
        _FaceState.none => Icons.face_retouching_off_rounded,
      };

  Future<void> _capture() async {
    final cam = _camera;
    if (cam == null) return;
    setState(() => _busy = true);
    try {
      await cam.stopImageStream();
      final file = await cam.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).pop<Uint8List>(bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not capture selfie: $e';
        _captured = false;
      });
      try {
        await cam.startImageStream(_onFrame);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    final accent = AgapColors.brandWordmarkBlue;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          'Liveness check',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
      ),
      body: _busy && cam == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              fit: StackFit.expand,
              children: [
                if (cam != null) CameraPreview(cam),
                // Subtle overlay if camera isn't ready / errored.
                if (cam == null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1220).withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.camera_alt_rounded, color: accent, size: 28),
                            const SizedBox(height: 10),
                            Text(
                              'Camera unavailable',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _error ?? 'Please allow camera permission and try again.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.00),
                          Colors.black.withValues(alpha: 0.70),
                          Colors.black.withValues(alpha: 0.92),
                        ],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _statusColor.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: _statusColor.withValues(alpha: 0.25),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(_statusIcon, size: 16, color: _statusColor),
                                          const SizedBox(width: 6),
                                          Text(
                                            _faceMessage,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${(_progress * 100).round()}%',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white.withValues(alpha: 0.92),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: _progress,
                                    minHeight: 7,
                                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _instruction,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.25,
                                  ),
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFFCA5A5),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_step == _LivenessStep.done && _canProceed) ...[
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: _busy
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        'Auto-capturing…',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: Colors.white.withValues(alpha: 0.92),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

