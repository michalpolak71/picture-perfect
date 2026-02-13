import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class WatermarkUtil {
  static Future<String> addWatermark(String imagePath, {double? latitude, double? longitude}) async {
    try {
      // Load image
      final imageBytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(imageBytes);
      if (image == null) return imagePath;

      // Load logo
      final ByteData logoData = await rootBundle.load('assets/logo.png');
      final Uint8List logoBytes = logoData.buffer.asUint8List();
      final logo = img.decodeImage(logoBytes);
      if (logo == null) return imagePath;

      // Resize logo to 20% of image width
      final logoWidth = (image.width * 0.2).round();
      final logoHeight = (logo.height * logoWidth / logo.width).round();
      final resizedLogo = img.copyResize(logo, width: logoWidth, height: logoHeight);

      // Position: top-left with padding
      img.compositeImage(image, resizedLogo, dstX: 20, dstY: 20);

      // Add date/time text at bottom left
      final now = DateTime.now();
      final dateText = '${now.day}.${now.month}.${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
      
      img.drawString(
        image,
        dateText,
        font: img.arial24,
        x: 20,
        y: image.height - 80,
        color: img.ColorRgb8(255, 255, 255),
      );

      // Add GPS text at bottom left if available
      if (latitude != null && longitude != null) {
        final gpsText = 'GPS: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
        
        // Draw background for GPS text
        final textWidth = gpsText.length * 10;
        img.fillRect(
          image,
          x1: 15,
          y1: image.height - 55,
          x2: textWidth + 25,
          y2: image.height - 25,
          color: img.ColorRgb8(0, 128, 0),
        );
        
        img.drawString(
          image,
          gpsText,
          font: img.arial24,
          x: 20,
          y: image.height - 50,
          color: img.ColorRgb8(255, 255, 255),
        );
      }

      // Save image
      final modifiedBytes = img.encodeJpg(image, quality: 95);
      await File(imagePath).writeAsBytes(modifiedBytes);

      return imagePath;
    } catch (e) {
      print('Error adding watermark: $e');
      return imagePath;
    }
  }
}
