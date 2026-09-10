import 'dart:async';
import 'package:ansvk_outreach/hotspots/location_service.dart';
import 'package:geolocator/geolocator.dart';

class TestLocationGateway implements LocationGateway {
  bool serviceEnabled = true;
  LocationPermission permissionValue = LocationPermission.whileInUse;
  LocationPermission requestedValue = LocationPermission.denied;
  int requests = 0;
  int positions = 0;
  LocationCapture result = const LocationCapture.available(
    16.8,
    96.1,
    accuracy: 8,
  );
  Object? error;
  Completer<LocationCapture>? pending;
  @override
  Future<bool> enabled() async => serviceEnabled;
  @override
  Future<LocationPermission> permission() async => permissionValue;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return requestedValue;
  }

  @override
  Future<LocationCapture> position(Duration timeLimit) async {
    positions++;
    if (error != null) throw error!;
    return pending != null ? pending!.future : result;
  }
}
