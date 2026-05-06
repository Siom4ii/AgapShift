import 'package:flutter/services.dart';

/// BIR TIN is commonly entered as 12 digits grouped `###-###-###-###`.
class PhilippineTinInputFormatter extends TextInputFormatter {
  const PhilippineTinInputFormatter();

  static const int digitCount = 12;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final truncated =
        digits.length > digitCount ? digits.substring(0, digitCount) : digits;
    final buf = StringBuffer();
    for (var i = 0; i < truncated.length; i++) {
      if (i == 3 || i == 6 || i == 9) buf.write('-');
      buf.write(truncated[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// `true` when exactly 12 digits are present (with or without dashes).
bool isPhilippineTinComplete(String formatted) {
  final d = formatted.replaceAll(RegExp(r'[^0-9]'), '');
  return d.length == PhilippineTinInputFormatter.digitCount;
}
