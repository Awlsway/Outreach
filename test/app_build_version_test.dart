import 'package:ansvk_outreach/app_build_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(AppBuildVersion.channel, null),
  );
  test(
    'installed version and build overrides are returned unchanged',
    () async {
      for (final version in ['0.9.10+25', '0.9.11+26']) {
        messenger.setMockMethodCallHandler(AppBuildVersion.channel, (
          call,
        ) async {
          expect(call.method, 'read');
          return version;
        });
        expect(await AppBuildVersion.read(), version);
      }
    },
  );
  test(
    'malformed installed metadata fails instead of reporting a stale version',
    () async {
      messenger.setMockMethodCallHandler(
        AppBuildVersion.channel,
        (_) async => '',
      );
      await expectLater(AppBuildVersion.read(), throwsFormatException);
    },
  );
}
