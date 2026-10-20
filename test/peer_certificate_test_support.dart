import 'package:ansvk_outreach/sync/peer_certificate_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> installPeerCertificateMock({List<String>? ipSans}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final metadata = <String, Object?>{
    'notBefore': DateTime.utc(2020).millisecondsSinceEpoch,
    'notAfter': DateTime.utc(2040).millisecondsSinceEpoch,
    'ipSans': ipSans ?? ['192.168.1.50', '127.0.0.1'],
  };
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(PeerCertificateVerifier.channel, (call) async {
        expect(call.method, 'parse');
        expect(call.arguments['der'], isNotEmpty);
        return metadata;
      });
  return metadata;
}

void clearPeerCertificateMock() => TestDefaultBinaryMessengerBinding
    .instance
    .defaultBinaryMessenger
    .setMockMethodCallHandler(PeerCertificateVerifier.channel, null);
