import 'package:ansvk_outreach/sync/synthetic_review_export.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'test export is gated and preserves exact UTF8 body without secrets',
    () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('org.ansvk.outreach/synthetic_review');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'export' ? '/private/test-file.json' : null;
          });
      const body = '{"name":"စမ်းသပ်", "value":1.0}\n';
      if (SyntheticReviewExport.enabled) {
        await SyntheticReviewExport.write(body);
        expect(calls.single.method, 'export');
        expect(calls.single.arguments, {'body': body});
        await SyntheticReviewExport.clear();
        expect(calls.last.method, 'clear');
      } else {
        await expectLater(SyntheticReviewExport.write(body), throwsStateError);
        await SyntheticReviewExport.clear();
        expect(calls, isEmpty);
      }
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
