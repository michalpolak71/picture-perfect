import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import '../models/photo_data.dart';

class GoogleDriveService {
  static const String _rootFolderId =
      '10FYUR8tpncJX8mP5SQy1kghnWg2jmvV_';
  static const List<String> _scopes = [drive.DriveApi.driveScope];

  drive.DriveApi? _driveApi;

  Future<void> initialize() async {
    try {
      final jsonStr =
          await rootBundle.loadString('assets/service_account.json');
      final credentials =
          ServiceAccountCredentials.fromJson(json.decode(jsonStr));
      final client =
          await clientViaServiceAccount(credentials, _scopes);
      _driveApi = drive.DriveApi(client);
    } catch (e) {
      print('Drive init error: $e');
      rethrow;
    }
  }

  Future<String> _findOrCreateFolder(
      String name, String parentId) async {
    if (_driveApi == null) throw Exception('Drive not initialized');

    // Search for existing folder
    final query =
        "name='$name' and '$parentId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false";
    final result = await _driveApi!.files.list(q: query, $fields: 'files(id)');

    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id!;
    }

    // Create new folder
    final folder = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = [parentId];

    final created =
        await _driveApi!.files.create(folder, $fields: 'id');
    return created.id!;
  }

  Future<String?> _uploadFile(
      File file, String fileName, String folderId, String mimeType) async {
    if (_driveApi == null) return null;

    try {
      final driveFile = drive.File()
        ..name = fileName
        ..parents = [folderId];

      final media = drive.Media(file.openRead(), await file.length());
      final result = await _driveApi!.files.create(
        driveFile,
        uploadMedia: media,
        $fields: 'id, webViewLink',
      );

      // Make public
      final permission = drive.Permission()
        ..role = 'reader'
        ..type = 'anyone';
      await _driveApi!.permissions.create(permission, result.id!);

      return result.webViewLink;
    } catch (e) {
      print('Upload error: $e');
      return null;
    }
  }

  Future<Map<String, String?>> uploadReport({
    required File pdfFile,
    required String reportNumber,
    required String projectName,
    required String clientName,
    required List<PhotoData> photos,
  }) async {
    if (_driveApi == null) throw Exception('Drive not initialized');

    final now = DateTime.now();
    final months = [
      '', 'sty', 'lut', 'mar', 'kwi', 'maj', 'cze',
      'lip', 'sie', 'wrz', 'paz', 'lis', 'gru'
    ];
    final monthFolder =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${months[now.month]}';

    // Create month folder
    final monthFolderId =
        await _findOrCreateFolder(monthFolder, _rootFolderId);

    // Upload PDF
    final safeProject =
        projectName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final safeClient =
        clientName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final pdfName =
        'raport_${safeProject}_${safeClient}_${now.millisecondsSinceEpoch}.pdf';
    final pdfLink =
        await _uploadFile(pdfFile, pdfName, monthFolderId, 'application/pdf');

    // Create session folder for photos
    final sessionFolderName =
        'sesja_${safeProject}_${safeClient}_${now.day.toString().padLeft(2, '0')}${months[now.month]}${now.year}';
    final sessionFolderId =
        await _findOrCreateFolder(sessionFolderName, monthFolderId);

    // Upload photos
    for (int i = 0; i < photos.length; i++) {
      final photo = photos[i];
      final photoFile = File(photo.imagePath);
      if (await photoFile.exists()) {
        final photoName =
            'zdjecie_${(i + 1).toString().padLeft(2, '0')}.jpg';
        await _uploadFile(
            photoFile, photoName, sessionFolderId, 'image/jpeg');
      }
    }

    // Get session folder link
    String? sessionLink;
    try {
      final folderMeta = await _driveApi!.files
          .get(sessionFolderId, $fields: 'webViewLink') as drive.File;
      sessionLink = folderMeta.webViewLink;

      // Make session folder public
      final permission = drive.Permission()
        ..role = 'reader'
        ..type = 'anyone';
      await _driveApi!.permissions.create(permission, sessionFolderId);
    } catch (_) {}

    return {
      'pdfLink': pdfLink,
      'sessionLink': sessionLink,
    };
  }
}
