class MockAuthService {
  Future<void> sendOtp({required String email}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  Future<bool> verifyOtp({required String email, required String code}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return code.trim().length == 6;
  }
}

