import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// A standards-compliant ticket QR. The previous decorative glyph looked like
/// a QR code but could not be decoded by a camera scanner.
class BoardPassQr extends StatelessWidget {
  final String seed;
  final double size;

  const BoardPassQr({super.key, required this.seed, this.size = 168});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: QrImageView(
        data: seed,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF0B0B0D),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF0B0B0D),
        ),
      ),
    );
  }
}
