import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/agap_colors.dart';

class KycUploadZone extends StatelessWidget {
  const KycUploadZone({
    super.key,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.fileName,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final String? fileName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hasFile = fileName != null && fileName!.isNotEmpty;
    final r = compact ? 14.0 : 16.0;
    return Material(
      color: const Color(0xFFE8F4FC),
      borderRadius: BorderRadius.circular(r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(r),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            border: Border.all(
              color: hasFile ? AgapColors.primary.withValues(alpha: 0.45) : const Color(0xFF93C5FD),
              width: 1.6,
            ),
          ),
          padding: EdgeInsets.symmetric(vertical: compact ? 18 : 28, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasFile ? Icons.check_circle_rounded : Icons.cloud_upload_outlined,
                size: compact ? 32 : 40,
                color: hasFile ? AgapColors.primary : const Color(0xFF3B82F6),
              ),
              SizedBox(height: compact ? 8 : 12),
              Text(
                hasFile ? fileName! : title,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 13 : 14,
                  color: const Color(0xFF1E3A5F),
                ),
              ),
              if (!hasFile && subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12, color: AgapColors.textMuted),
                ),
              ],
              if (!hasFile) ...[
                const SizedBox(height: 8),
                Text(
                  'PDF, JPG, PNG (max. 10MB)',
                  style: GoogleFonts.inter(fontSize: 11, color: AgapColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Display name for UI / payloads (not necessarily unique).
String kycFileLabel(PlatformFile f) {
  if (f.name.isNotEmpty) return f.name;
  if (f.path != null && f.path!.isNotEmpty) {
    final i = f.path!.replaceAll(r'\', '/').lastIndexOf('/');
    if (i >= 0 && i < f.path!.length - 1) return f.path!.substring(i + 1);
  }
  return 'Uploaded file';
}

/// Picks a document; [withData] ensures bytes on web and many mobile pickers.
Future<PlatformFile?> pickKycDocumentFile() async {
  FilePickerResult? r;
  try {
    r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
  } catch (_) {
    r = null;
  }
  if (r != null && r.files.isNotEmpty) return r.files.single;

  try {
    r = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
  } catch (_) {
    r = null;
  }
  if (r != null && r.files.isNotEmpty) return r.files.single;

  try {
    r = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
  } catch (_) {
    return null;
  }
  if (r != null && r.files.isNotEmpty) return r.files.single;
  return null;
}

/// Selfie / liveness: prefer images; fall back to any.
Future<PlatformFile?> pickKycSelfieImageFile() async {
  FilePickerResult? r;
  try {
    r = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
  } catch (_) {
    r = null;
  }
  if (r != null && r.files.isNotEmpty) return r.files.single;

  try {
    r = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
  } catch (_) {
    return null;
  }
  if (r != null && r.files.isNotEmpty) return r.files.single;
  return null;
}

/// Picks a document; falls back to any file type if the filtered picker fails (common on web/desktop).
Future<String?> pickKycDocument() async {
  final f = await pickKycDocumentFile();
  return f == null ? null : kycFileLabel(f);
}

/// Selfie / liveness: prefer images; fall back to any.
Future<String?> pickKycSelfieImage() async {
  final f = await pickKycSelfieImageFile();
  return f == null ? null : kycFileLabel(f);
}
