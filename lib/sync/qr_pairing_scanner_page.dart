import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera-only page that returns one scanned QR string to its caller.
///
/// QR validation and pairing happen outside this page so the camera never
/// handles credentials or network requests itself.
class QrPairingScannerPage extends StatefulWidget {
  const QrPairingScannerPage({super.key});

  @override
  State<QrPairingScannerPage> createState() => _QrPairingScannerPageState();
}

class _QrPairingScannerPageState extends State<QrPairingScannerPage> {
  final _controller = MobileScannerController();
  bool _found = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_found) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (value == null || value.isEmpty) return;
    _found = true;
    await _controller.stop();
    if (mounted) Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan dashboard QR')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            minimum: const EdgeInsets.all(24),
            child: Card(
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Point the camera at the QR code shown by the data assistant on the dashboard.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
