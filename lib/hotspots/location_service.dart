import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationCapture {
  const LocationCapture.available(
    this.latitude,
    this.longitude, {
    this.accuracy,
  }) : reason = null;
  const LocationCapture.unavailable(this.reason)
    : latitude = null,
      longitude = null,
      accuracy = null;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final String? reason;
  bool get available => latitude != null && longitude != null;
}

abstract interface class LocationGateway {
  Future<bool> enabled();
  Future<LocationPermission> permission();
  Future<LocationPermission> requestPermission();
  Future<LocationCapture> position(Duration timeLimit);
}

class AndroidLocationGateway implements LocationGateway {
  @override
  Future<bool> enabled() => Geolocator.isLocationServiceEnabled();
  @override
  Future<LocationPermission> permission() => Geolocator.checkPermission();
  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();
  @override
  Future<LocationCapture> position(Duration timeLimit) async {
    final result = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeLimit,
      ),
    );
    return LocationCapture.available(
      result.latitude,
      result.longitude,
      accuracy: result.accuracy,
    );
  }
}

class HotspotLocationService {
  HotspotLocationService({LocationGateway? gateway})
    : _gateway = gateway ?? AndroidLocationGateway();
  final LocationGateway _gateway;
  static const timeout = Duration(seconds: 20);

  Future<LocationCapture> capture() async {
    final elapsed = Stopwatch()..start();
    Duration remaining() {
      final time = timeout - elapsed.elapsed;
      if (time <= Duration.zero) throw TimeoutException('Location timed out');
      return time;
    }

    try {
      if (!await _gateway.enabled().timeout(remaining())) {
        return const LocationCapture.unavailable(
          'Phone location is turned off. You can still save this hotspot.',
        );
      }
      var permission = await _gateway.permission().timeout(remaining());
      if (permission == LocationPermission.denied) {
        permission = await _gateway.requestPermission().timeout(remaining());
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return LocationCapture.unavailable(
          permission == LocationPermission.deniedForever
              ? 'Location permission is blocked. Allow it in the phone app settings to retry, or save without GPS.'
              : 'Location permission was not granted. You can still save this hotspot.',
        );
      }
      final limit = remaining();
      final result = await _gateway.position(limit).timeout(limit);
      final lat = result.latitude;
      final lon = result.longitude;
      if (lat == null ||
          lon == null ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat.abs() > 90 ||
          lon.abs() > 180) {
        return const LocationCapture.unavailable(
          'A valid position could not be obtained. You can still save.',
        );
      }
      return result;
    } on TimeoutException {
      return const LocationCapture.unavailable(
        'No position received within 20 seconds. You can retry or save without GPS.',
      );
    } catch (_) {
      return const LocationCapture.unavailable(
        'Location could not be obtained. You can retry or save without GPS.',
      );
    } finally {
      elapsed.stop();
    }
  }
}
