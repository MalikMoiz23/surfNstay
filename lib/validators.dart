/// Shared input validation. Returns `null` when the value is acceptable, or a
/// user-facing error message when it is not.
class Validators {
  Validators._();

  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  /// Pakistani mobile numbers: 03XXXXXXXXX, +923XXXXXXXXX or 00923XXXXXXXXX.
  static final RegExp _phone = RegExp(r'^(?:\+92|0092|0)3\d{9}$');

  static String? required(String value, String fieldName) {
    if (value.trim().isEmpty) return '$fieldName is required';
    return null;
  }

  static String? email(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Email is required';
    if (!_email.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  static String? phone(String value) {
    final v = value.replaceAll(RegExp(r'[\s-]'), '');
    if (v.isEmpty) return 'Phone number is required';
    if (!_phone.hasMatch(v)) {
      return 'Enter a valid Pakistani mobile number (e.g. 03001234567)';
    }
    return null;
  }

  /// Supabase rejects passwords under 6 characters by default; we require a
  /// letter and a digit on top of that so accounts are not trivially guessable.
  static String? password(String value) {
    if (value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(value)) {
      return 'Password must contain at least one letter';
    }
    if (!RegExp(r'\d').hasMatch(value)) {
      return 'Password must contain at least one number';
    }
    return null;
  }

  static String? confirmPassword(String password, String confirmation) {
    if (confirmation.isEmpty) return 'Please confirm your password';
    if (password != confirmation) return 'Passwords do not match';
    return null;
  }

  /// Normalises a phone number to +92XXXXXXXXXX for storage.
  static String normalisePhone(String value) {
    final v = value.replaceAll(RegExp(r'[\s-]'), '');
    if (v.startsWith('+92')) return v;
    if (v.startsWith('0092')) return '+${v.substring(2)}';
    if (v.startsWith('0')) return '+92${v.substring(1)}';
    return v;
  }
}
