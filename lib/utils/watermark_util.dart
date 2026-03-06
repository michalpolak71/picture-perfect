import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class WatermarkUtil {
  static Future<String> addWatermark(
    String imagePath, {
    double? latitude,
    double? longitude,
    double? altitude,
    String? floorLabel,
    double? relativeHeight,
  }) async {
    try {
      final imageBytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(imageBytes);
      if (image == null) return imagePath;

      // Load logo
      final ByteData logoData = await rootBundle.load('assets/logo.png');
      final Uint8List logoBytes = logoData.buffer.asUint8List();
      final logo = img.decodeImage(logoBytes);
      if (logo != null) {
        final logoWidth = (image.width * 0.2).round();
        final logoHeight = (logo.height * logoWidth / logo.width).round();
        final resizedLogo = img.copyResize(logo, width: logoWidth, height: logoHeight);
        img.compositeImage(image, resizedLogo, dstX: 20, dstY: 20);
      }

      // Date/time
      final now = DateTime.now();
      final dateText =
          '${now.day}.${now.month}.${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';

      int yPos = image.height - 120;

      img.drawString(
        image,
        dateText,
        font: img.arial24,
        x: 20,
        y: yPos,
        color: img.ColorRgb8(255, 255, 255),
      );
      yPos += 30;

      // GPS
      if (latitude != null && longitude != null) {
        final gpsText =
            'GPS: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
        img.drawString(
          image,
          gpsText,
          font: img.arial24,
          x: 20,
          y: yPos,
          color: img.ColorRgb8(255, 255, 255),
        );
        yPos += 30;
      }

      // V9: Floor/height
      if (floorLabel != null) {
        String heightStr = 'Kondygnacja: $floorLabel';
        if (relativeHeight != null) {
          heightStr +=
              ' (${relativeHeight >= 0 ? '+' : ''}${relativeHeight.toStringAsFixed(2)}m)';
        }
        img.drawString(
          image,
          heightStr,
          font: img.arial24,
          x: 20,
          y: yPos,
          color: img.ColorRgb8(100, 220, 255),
        );
        yPos += 30;
      }

      if (altitude != null) {
        final altStr = 'Wys. n.p.m.: ${altitude.toStringAsFixed(1)}m';
        img.drawString(
          image,
          altStr,
          font: img.arial24,
          x: 20,
          y: yPos,
          color: img.ColorRgb8(255, 200, 100),
        );
      }

      final modifiedBytes = img.encodeJpg(image, quality: 95);
      await File(imagePath).writeAsBytes(modifiedBytes);

      return imagePath;
    } catch (e) {
      print('Error adding watermark: $e');
      return imagePath;
    }
  }
}
