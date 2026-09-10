import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:ansvk_outreach/auth/password_hasher.dart';

/// Fast, deliberately unsuitable-for-production hasher for UI/service tests.
class TestHasher implements PasswordHasher {
  @override
  Future<PasswordDigest> hash(String password) async => PasswordDigest(
    'test-salt',
    base64Encode((await Sha256().hash(utf8.encode(password))).bytes),
    600000,
  );

  @override
  Future<bool> verify(String password, PasswordDigest digest) async =>
      (await hash(password)).verifier == digest.verifier;
}
