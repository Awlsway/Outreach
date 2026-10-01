import 'dart:io';
import 'package:ansvk_outreach/sync/peer_certificate_verifier.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the production Java parser on real DER; not an Android bridge substitute.
class JvmCertificateReader {
  JvmCertificateReader._(this.directory);
  final Directory directory;
  int _sequence = 0;
  static Future<JvmCertificateReader> create() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // These are real loopback TLS tests, not mocked widget HTTP requests.
    HttpOverrides.global = null;
    final directory = await Directory.systemTemp.createTemp(
      'outreach-x509-jvm-',
    );
    try {
      final main = File('${directory.path}/CertificateReaderMain.java');
      await main.writeAsString('''
import org.ansvk.ansvk_outreach.PeerCertificateMetadata;
import java.nio.file.*;
import java.util.*;
public class CertificateReaderMain {
  public static void main(String[] args) throws Exception {
    Map<String,Object> m = PeerCertificateMetadata.parse(Files.readAllBytes(Paths.get(args[0])));
    System.out.println(m.get("notBefore"));
    System.out.println(m.get("notAfter"));
    for(Object ip : (List<?>)m.get("ipSans")) System.out.println(ip);
  }
}
''');
      final compiled = await Process.run('javac', [
        '-d',
        directory.path,
        'android/app/src/main/java/org/ansvk/ansvk_outreach/PeerCertificateMetadata.java',
        main.path,
      ]);
      if (compiled.exitCode != 0) {
        throw StateError(
          'JVM certificate parser compilation failed: ${compiled.stderr}',
        );
      }
      return JvmCertificateReader._(directory);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PeerCertificateVerifier.channel, (
          call,
        ) async {
          final file = File('${directory.path}/peer-${++_sequence}.der');
          await file.writeAsBytes(List<int>.from(call.arguments['der']));
          try {
            final result = await Process.run('java', [
              '-cp',
              directory.path,
              'CertificateReaderMain',
              file.path,
            ]);
            if (result.exitCode != 0) {
              throw PlatformException(code: 'invalid_certificate');
            }
            final lines = (result.stdout as String).trim().split(
              RegExp(r'\r?\n'),
            );
            return <String, Object?>{
              'notBefore': int.parse(lines[0]),
              'notAfter': int.parse(lines[1]),
              'ipSans': lines.skip(2).toList(),
            };
          } finally {
            await file.delete();
          }
        });
  }

  Future<void> close() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PeerCertificateVerifier.channel, null);
    await directory.delete(recursive: true);
  }
}
