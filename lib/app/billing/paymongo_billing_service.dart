import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../supabase/supabase_config.dart';

enum BillingProduct { workerSub, employerSub, gigBoost }

extension on BillingProduct {
  String get apiValue => switch (this) {
        BillingProduct.workerSub => 'worker_sub',
        BillingProduct.employerSub => 'employer_sub',
        BillingProduct.gigBoost => 'gig_boost',
      };
}

abstract final class PaymongoBillingService {
  static Future<Uri?> startCheckout({
    required BillingProduct product,
    String? gigId,
  }) async {
    if (!SupabaseConfig.isConfigured) return null;
    final client = Supabase.instance.client;

    final payload = <String, dynamic>{
      'product': product.apiValue,
      if (gigId != null) 'gig_id': gigId,
    };

    final res = await client.functions.invoke(
      'paymongo_create_checkout',
      body: payload,
    );
    final data = res.data;
    if (data is! Map) return null;
    final url = data['checkout_url']?.toString();
    if (url == null || url.isEmpty) return null;
    return Uri.tryParse(url);
  }

  static Future<bool> openCheckoutUrl(Uri url) async {
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }

  /// Fallback if webhooks are delayed: ask server to reconcile latest checkout.
  static Future<bool> reconcileLatest() async {
    if (!SupabaseConfig.isConfigured) return false;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'paymongo_reconcile',
        body: const {},
      );
      final data = res.data;
      if (data is! Map) return false;
      return data['reconciled'] == true;
    } catch (_) {
      return false;
    }
  }
}

