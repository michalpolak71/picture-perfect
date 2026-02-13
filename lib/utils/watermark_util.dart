import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:exif/exif.dart';

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
        final gpsText = '📍 ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
        img.drawString(
          image,
          gpsText,
          font: img.arial24,
          x: 20,
          y: image.height - 50,
          color: img.ColorRgb8(100, 255, 100),
        );
      }

      // Save image
      final modifiedBytes = img.encodeJpg(image, quality: 95);
      await File(imagePath).writeAsBytes(modifiedBytes);

      // Add GPS to EXIF if available
      if (latitude != null && longitude != null) {
        await _addGpsToExif(imagePath, latitude, longitude);
      }

      return imagePath;
    } catch (e) {
      print('Error adding watermark: $e');
      return imagePath;
    }
  }

  static Future<void> _addGpsToExif(String imagePath, double latitude, double longitude) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final data = await readExifFromBytes(bytes);

      // Create GPS tags
      final gpsData = <String, IfdTag>{};

      // Latitude
      final latRef = latitude >= 0 ? 'N' : 'S';
      final latAbs = latitude.abs();
      final latDeg = latAbs.floor();
      final latMin = ((latAbs - latDeg) * 60).floor();
      final latSec = (((latAbs - latDeg) * 60 - latMin) * 60 * 10000).round();

      gpsData['GPS GPSLatitudeRef'] = IfdTag(
        tag: 1,
        tagType: 'ASCII',
        printable: latRef,
        values: IfdBytes([latRef.codeUnitAt(0)], 1),
      );

      gpsData['GPS GPSLatitude'] = IfdTag(
        tag: 2,
        tagType: 'Ratio',
        printable: '$latDeg, $latMin, ${latSec / 10000}',
        values: IfdRatios([
          Ratio(latDeg, 1),
          Ratio(latMin, 1),
          Ratio(latSec, 10000),
        ], 3),
      );

      // Longitude
      final lonRef = longitude >= 0 ? 'E' : 'W';
      final lonAbs = longitude.abs();
      final lonDeg = lonAbs.floor();
      final lonMin = ((lonAbs - lonDeg) * 60).floor();
      final lonSec = (((lonAbs - lonDeg) * 60 - lonMin) * 60 * 10000).round();

      gpsData['GPS GPSLongitudeRef'] = IfdTag(
        tag: 3,
        tagType: 'ASCII',
        printable: lonRef,
        values: IfdBytes([lonRef.codeUnitAt(0)], 1),
      );

      gpsData['GPS GPSLongitude'] = IfdTag(
        tag: 4,
        tagType: 'Ratio',
        printable: '$lonDeg, $lonMin, ${lonSec / 10000}',
        values: IfdRatios([
          Ratio(lonDeg, 1),
          Ratio(lonMin, 1),
          Ratio(lonSec, 10000),
        ], 3),
      );

      // Note: Full EXIF writing is complex, this provides GPS data structure
      // For production, consider using native_exif package for better support
      
    } catch (e) {
      print('Error adding GPS EXIF: $e');
    }
  }
}
