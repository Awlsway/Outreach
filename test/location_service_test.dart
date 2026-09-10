import 'dart:async';
import 'package:ansvk_outreach/hotspots/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'hotspot_test_support.dart';

void main() {
  test('captures coordinates when permission is granted', () async {
    final gateway = TestLocationGateway();
    final result = await HotspotLocationService(gateway: gateway).capture();
    expect(result.latitude, 16.8);
    expect(result.longitude, 96.1);
    expect(gateway.requests, 0);
    expect(gateway.positions, 1);
  });
  test(
    'disabled service and denied or blocked permissions return empty coordinates',
    () async {
      final gateway = TestLocationGateway()..serviceEnabled = false;
      final service = HotspotLocationService(gateway: gateway);
      expect((await service.capture()).available, isFalse);
      expect(gateway.positions, 0);
      gateway
        ..serviceEnabled = true
        ..permissionValue = LocationPermission.denied;
      final denied = await service.capture();
      expect(denied.latitude, isNull);
      expect(denied.longitude, isNull);
      expect(gateway.requests, 1);
      gateway.permissionValue = LocationPermission.deniedForever;
      expect((await service.capture()).reason, contains('blocked'));
      expect(gateway.requests, 1);
      expect(gateway.positions, 0);
      gateway
        ..permissionValue = LocationPermission.denied
        ..requestedValue = LocationPermission.whileInUse;
      expect((await service.capture()).available, isTrue);
    },
  );
  test('platform errors and invalid coordinates safely fall back', () async {
    final gateway = TestLocationGateway()..error = StateError('GPS error');
    final service = HotspotLocationService(gateway: gateway);
    expect((await service.capture()).available, isFalse);
    gateway
      ..error = null
      ..result = const LocationCapture.available(91, 0);
    expect((await service.capture()).available, isFalse);
  });
  testWidgets('a stalled location attempt times out after twenty seconds', (
    tester,
  ) async {
    final gateway = TestLocationGateway()
      ..pending = Completer<LocationCapture>();
    LocationCapture? result;
    HotspotLocationService(
      gateway: gateway,
    ).capture().then((value) => result = value);
    await tester.pump();
    await tester.pump(const Duration(seconds: 19));
    expect(result, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(result?.available, isFalse);
    expect(result?.reason, contains('20 seconds'));
    gateway.pending!.complete(const LocationCapture.available(16, 96));
    await tester.pump();
    expect(result?.available, isFalse);
  });
}
