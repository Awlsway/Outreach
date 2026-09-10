import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

class PasswordDigest {
  const PasswordDigest(this.salt, this.verifier, this.iterations);
  final String salt;
  final String verifier;
  final int iterations;
}

abstract interface class PasswordHasher {
  Future<PasswordDigest> hash(String password);
  Future<bool> verify(String password, PasswordDigest digest);
}

class Pbkdf2PasswordHasher implements PasswordHasher {
  static const iterations = 600000;

  @override
  Future<PasswordDigest> hash(String password) async {
    final random = Random.secure();
    final salt = base64Encode(List.generate(32, (_) => random.nextInt(256)));
    return PasswordDigest(
      salt,
      await _derive(password, salt, iterations),
      iterations,
    );
  }

  @override
  Future<bool> verify(String password, PasswordDigest digest) async {
    if (digest.iterations < iterations || digest.iterations > 2000000) {
      throw StateError('Unsupported password work factor');
    }
    final actual = base64Decode(
      await _derive(password, digest.salt, digest.iterations),
    );
    final expected = base64Decode(digest.verifier);
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual[i] ^ expected[i];
    }
    return difference == 0;
  }

  Future<String> _derive(String password, String salt, int count) =>
      compute(_deriveInBackground, (password, salt, count));
}

Future<String> _deriveInBackground((String, String, int) input) async {
  final algorithm = Pbkdf2.hmacSha256(iterations: input.$3, bits: 256);
  final key = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(input.$1)),
    nonce: base64Decode(input.$2),
  );
  return base64Encode(await key.extractBytes());
}
