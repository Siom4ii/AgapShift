import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_config.dart';
import 'kyc_platform_file_bytes.dart';

/// Uploads KYC binaries to Supabase Storage and inserts a row in [kyc_documents]
/// for admin review (join path + bucket with Storage API or signed URLs).
abstract final class KycStorageService {
  static const bucketId = 'kyc-documents';
  static const maxBytes = 10 * 1024 * 1024;

  /// Adds `*_file`, and when [storagePath] is set also `*_storage_bucket` / `*_storage_path`.
  static void putFileRef(
    Map<String, dynamic> map,
    String baseKey,
    String? label,
    String? storagePath,
  ) {
    map['${baseKey}_file'] = label;
    if (storagePath != null && storagePath.isNotEmpty) {
      map['${baseKey}_storage_bucket'] = bucketId;
      map['${baseKey}_storage_path'] = storagePath;
    }
  }

  /// Returns storage path, or null if Supabase is off / user not signed in / no bytes.
  static Future<String?> upload({
    required PlatformFile file,
    required String flow,
    required String documentType,
  }) async {
    if (!SupabaseConfig.isConfigured) return null;
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return null;

    final bytes = await readPlatformFileBytes(file);
    if (bytes == null || bytes.isEmpty) return null;
    if (bytes.length > maxBytes) {
      throw KycUploadTooLargeException();
    }

    final ext = _extensionForFilename(file.name);
    final unique =
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 30)}';
    final objectPath =
        '$uid/$flow/${_slug(documentType)}/${unique}_${_sanitizeBasename(file.name)}$ext';
    final contentType = contentTypeForFilename(file.name);

    await client.storage.from(bucketId).uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: false,
          ),
        );

    await client.from('kyc_documents').insert(<String, dynamic>{
      'user_id': uid,
      'flow': flow,
      'document_type': documentType,
      'bucket_id': bucketId,
      'storage_path': objectPath,
      'original_filename': file.name.isNotEmpty ? file.name : 'upload',
      'content_type': contentType,
      'file_size': bytes.length,
    });

    return objectPath;
  }
}

class KycUploadTooLargeException implements Exception {
  @override
  String toString() => 'File must be 10MB or smaller.';
}

String contentTypeForFilename(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'application/octet-stream';
}

String _slug(String documentType) {
  final s = documentType.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
  return s.isEmpty ? 'doc' : s.toLowerCase();
}

String _sanitizeBasename(String name) {
  final i = name.replaceAll(r'\', '/').lastIndexOf('/');
  final base = i >= 0 && i < name.length - 1 ? name.substring(i + 1) : name;
  final noExt = base.replaceAll(RegExp(r'\.[^.]+$'), '');
  final cleaned = noExt.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  if (cleaned.isEmpty) return 'file';
  return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
}

String _extensionForFilename(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return '.pdf';
  if (lower.endsWith('.png')) return '.png';
  if (lower.endsWith('.jpg')) return '.jpg';
  if (lower.endsWith('.jpeg')) return '.jpeg';
  if (lower.endsWith('.webp')) return '.webp';
  return '';
}
