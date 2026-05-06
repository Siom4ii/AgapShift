import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../onboarding/kyc_storage_service.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/kyc_upload_zone.dart';

class WorkerIdentityVerificationScreen extends StatefulWidget {
  const WorkerIdentityVerificationScreen({
    super.key,
    required this.onBack,
    required this.onSubmit,
  });

  final VoidCallback onBack;
  final Future<void> Function() onSubmit;

  @override
  State<WorkerIdentityVerificationScreen> createState() => _WorkerIdentityVerificationScreenState();
}

class _WorkerIdentityVerificationScreenState extends State<WorkerIdentityVerificationScreen> {
  String? _idFront;
  String? _idBack;
  bool _selfieDone = false;
  bool _submitting = false;
  bool _uploadBusy = false;

  double get _progress {
    var p = 0.12;
    if (_idFront != null) p += 0.28;
    if (_idBack != null) p += 0.28;
    if (_selfieDone) p += 0.32;
    return p.clamp(0.0, 1.0);
  }

  bool get _canContinue => _idFront != null && _idBack != null && _selfieDone;

  Future<void> _pickIdSide({required bool front}) async {
    if (_uploadBusy) return;
    final file = await pickKycDocumentFile();
    if (!mounted) return;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No file selected. Picker may be unavailable on this device.'),
        ),
      );
      return;
    }

    final label = kycFileLabel(file);
    if (!SupabaseConfig.isConfigured) {
      setState(() {
        if (front) {
          _idFront = label;
        } else {
          _idBack = label;
        }
      });
      return;
    }

    setState(() => _uploadBusy = true);
    try {
      await KycStorageService.upload(
        file: file,
        flow: 'worker',
        documentType: front ? 'government_id_front' : 'government_id_back',
      );
      if (!mounted) return;
      setState(() {
        if (front) {
          _idFront = label;
        } else {
          _idBack = label;
        }
      });
    } on KycUploadTooLargeException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File must be 10MB or smaller.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not upload ID: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadBusy = false);
    }
  }

  Future<void> _captureSelfie() async {
    if (_uploadBusy) return;
    final file = await pickKycSelfieImageFile();
    if (!mounted) return;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No photo selected.'),
        ),
      );
      return;
    }

    if (!SupabaseConfig.isConfigured) {
      setState(() => _selfieDone = true);
      return;
    }

    setState(() => _uploadBusy = true);
    try {
      await KycStorageService.upload(
        file: file,
        flow: 'worker',
        documentType: 'selfie',
      );
      if (!mounted) return;
      setState(() => _selfieDone = true);
    } on KycUploadTooLargeException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File must be 10MB or smaller.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not upload selfie: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadBusy = false);
    }
  }

  Future<void> _submit() async {
    if (!_canContinue) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final idComplete = _idFront != null && _idBack != null;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: widget.onBack,
        ),
        title: Text(
          'Identity Verification',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(Icons.lock_outline_rounded, color: AgapColors.primaryBright, size: 22),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
            value: _progress,
            minHeight: 3,
            backgroundColor: AgapColors.borderSubtle,
            color: AgapColors.primary,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: AbsorbPointer(
              absorbing: _uploadBusy,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Let's verify it's you",
                    style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800, color: const Color(0xFF111827)),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'To ensure a safe environment for everyone, we need to verify your identity. '
                    'This process takes less than 2 minutes.',
                    style: GoogleFonts.inter(fontSize: 14, height: 1.45, color: AgapColors.textMuted),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F4FC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_rounded, color: AgapColors.primaryBright, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your data is securely encrypted using bank-level security and is never shared publicly on your profile.',
                            style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: const Color(0xFF1E3A5F)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _IdStepCard(
                    active: true,
                    idFront: _idFront,
                    idBack: _idBack,
                    onFront: () => _pickIdSide(front: true),
                    onBack: () => _pickIdSide(front: false),
                  ),
                  const SizedBox(height: 16),
                  _LivenessCard(
                    enabled: idComplete,
                    selfieDone: _selfieDone,
                    onSelfie: idComplete ? _captureSelfie : null,
                  ),
                  const SizedBox(height: 24),
                  Text.rich(
                    TextSpan(
                      style: GoogleFonts.inter(fontSize: 13, color: AgapColors.textMuted),
                      children: [
                        const TextSpan(text: 'Having trouble with verification? '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: GestureDetector(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Support: support@agapshift.demo')),
                              );
                            },
                            child: Text(
                              'Contact Support',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AgapColors.primaryBright,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _canContinue && !_submitting ? AgapColors.primary : AgapColors.textMuted.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: (_canContinue && !_submitting) ? _submit : null,
                  child: _submitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Continue', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdStepCard extends StatelessWidget {
  const _IdStepCard({
    required this.active,
    required this.idFront,
    required this.idBack,
    required this.onFront,
    required this.onBack,
  });

  final bool active;
  final String? idFront;
  final String? idBack;
  final VoidCallback onFront;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final inProgress = idFront == null || idBack == null;
    return Opacity(
      opacity: active ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AgapColors.borderSubtle),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _orb('1', AgapColors.mintSurface, AgapColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Government ID', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDBEAFE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    inProgress ? 'In Progress' : 'Complete',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF1D4ED8)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Upload a clear photo of your driver\'s license, passport, or national ID. '
              'Ensure all text is readable with no glare.',
              style: GoogleFonts.inter(fontSize: 13, height: 1.45, color: AgapColors.textMuted),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: KycUploadZone(
                    title: 'Front of ID',
                    subtitle: 'Tap to capture or upload',
                    fileName: idFront,
                    onTap: onFront,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: KycUploadZone(
                    title: 'Back of ID',
                    subtitle: 'Tap to capture or upload',
                    fileName: idBack,
                    onTap: onBack,
                    compact: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LivenessCard extends StatelessWidget {
  const _LivenessCard({
    required this.enabled,
    required this.selfieDone,
    required this.onSelfie,
  });

  final bool enabled;
  final bool selfieDone;
  final VoidCallback? onSelfie;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AgapColors.borderSubtle),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _orb('2', const Color(0xFFE8F4FC), const Color(0xFF2563EB)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Liveness Check', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    selfieDone ? 'Done' : 'Pending',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: AgapColors.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'We need to match your face with the ID provided. Use a well-lit area and remove hats or sunglasses.',
              style: GoogleFonts.inter(fontSize: 13, height: 1.45, color: AgapColors.textMuted),
            ),
            const SizedBox(height: 12),
            _livenessCheckRow('Look directly at the camera'),
            _livenessCheckRow('Keep your face fully visible'),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDBEAFE),
                  foregroundColor: const Color(0xFF1E40AF),
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                  disabledForegroundColor: AgapColors.textMuted,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: enabled && !selfieDone ? onSelfie : null,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(selfieDone ? 'Selfie captured' : 'Take Selfie', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

Widget _livenessCheckRow(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(Icons.check_circle_rounded, size: 18, color: AgapColors.primaryBright),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600))),
      ],
    ),
  );
}

Widget _orb(String label, Color bg, Color fg) {
  return Container(
    width: 28,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
    child: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: fg, fontSize: 13)),
  );
}
