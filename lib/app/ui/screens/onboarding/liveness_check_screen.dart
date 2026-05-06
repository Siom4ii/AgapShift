import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
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

  _FaceState _faceState = _FaceState.none;
  String _faceMessage = 'No face detected';

  _LivenessStep _step = _LivenessStep.blink;
  bool _sawEyesOpen = false;

  Timer? _throttle;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _throttle?.cancel();
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

      final bytes = _concatenatePlanes(image.planes);
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _rotationFor(cam.description.sensorOrientation),
          format: InputImageFormat.yuv420,
          bytesPerRow: image.planes.first.bytesPerRow,
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

  static Uint8List _concatenatePlanes(List<Plane> planes) {
    final all = BytesBuilder(copy: false);
    for (final p in planes) {
      all.add(p.bytes);
    }
    return all.takeBytes();
  }

  static InputImageRotation _rotationFor(int sensorOrientation) {
    return switch (sensorOrientation) {
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
        _LivenessStep.done => 'Great! Tap “Capture selfie”.',
      };

  double get _progress => switch (_step) {
        _LivenessStep.blink => 0.33,
        _LivenessStep.turnLeft => 0.55,
        _LivenessStep.turnRight => 0.77,
        _LivenessStep.done => 1.0,
      };

  bool get _canCapture => _step == _LivenessStep.done && !_busy;

  bool get _canProceed => _faceState == _FaceState.single;

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
                          FilledButton.icon(
                            onPressed: (_canProceed && _canCapture && !_busy)
                                ? _capture
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(Icons.camera_alt_rounded, size: 18),
                            label: _busy
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Capture selfie',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                          ),
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

