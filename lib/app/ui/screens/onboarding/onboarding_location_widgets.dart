import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/agap_colors.dart';

/// Bottom sheet with search, used for municipality / barangay / bank lists.
Future<String?> showLocationOptionPicker({
  required BuildContext context,
  required String title,
  required List<String> options,
  String? selected,
  Color focusedBorderColor = AgapColors.brandWordmarkBlue,
}) async {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _LocationPickerSheet(
      title: title,
      options: options,
      selected: selected,
      focusedBorderColor: focusedBorderColor,
    ),
  );
}

class _LocationPickerSheet extends StatefulWidget {
  const _LocationPickerSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.focusedBorderColor,
  });

  final String title;
  final List<String> options;
  final String? selected;
  final Color focusedBorderColor;

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  late final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.options
        : widget.options.where((o) => o.toLowerCase().contains(q)).toList();
    final maxHeight = MediaQuery.of(context).size.height * 0.78;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: 'Search…',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFB6BFCB),
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: widget.focusedBorderColor,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: Text(
                          'No results',
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 2),
                      itemBuilder: (context, i) {
                        final option = filtered[i];
                        final isSelected = option == widget.selected;
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          tileColor: isSelected
                              ? widget.focusedBorderColor.withValues(
                                  alpha: 0.08,
                                )
                              : null,
                          title: Text(
                            option,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                              color: isSelected
                                  ? widget.focusedBorderColor
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: widget.focusedBorderColor,
                                  size: 20,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(option),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

/// Dropdown-styled field for province / municipality / barangay (and similar).
class OnboardingLocationSelectField extends StatelessWidget {
  const OnboardingLocationSelectField({
    super.key,
    required this.value,
    required this.hint,
    required this.enabled,
    required this.icon,
    this.onTap,
    this.focusAccentColor = AgapColors.brandWordmarkBlue,
  });

  final String? value;
  final String hint;
  final bool enabled;
  final IconData icon;
  final VoidCallback? onTap;
  final Color focusAccentColor;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    final bg = enabled ? Colors.white : const Color(0xFFF1F5F9);
    const borderColor = Color(0xFFE2E8F0);
    final textColor = !enabled
        ? const Color(0xFF64748B)
        : hasValue
        ? const Color(0xFF0F172A)
        : const Color(0xFF94A3B8);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: enabled
                    ? const Color(0xFF64748B)
                    : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasValue ? value! : hint,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: hasValue ? FontWeight.w700 : FontWeight.w600,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (enabled)
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: focusAccentColor.withValues(alpha: 0.85),
                )
              else
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: Color(0xFFB6BFCB),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
