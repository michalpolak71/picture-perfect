import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

class GoogleDriveService {
  static const _scopes = [drive.DriveApi.driveFileScope];
  static drive.DriveApi? _driveApi;
  static bool _initialized = false;

  static Future<bool> initialize() async {
    if (_initialized) return true;
    try {
      final jsonString = await rootBundle.loadString('assets/service_account.json');
      final accountCredentials =
          ServiceAccountCredentials.fromJson(json.decode(jsonString));
      final client = await clientViaServiceAccount(accountCredentials, _scopes);
      _driveApi = drive.DriveApi(client);
      _initialized = true;
      return true;
    } catch (e) {
      print('Error initializing Google Drive: $e');
      return false;
    }
  }

  static Future<String?> createFolder(String folderName, {String? parentId}) async {
    if (!_initialized) await initialize();
    if (_driveApi == null) return null;

    try {
      final query = parentId != null
          ? "name='$folderName' and '$parentId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
          : "name='$folderName' and mimeType='application/vnd.google-apps.folder' and trashed=false";

      final existing = await _driveApi!.files.list(q: query, spaces: 'drive');
      if (existing.files != null && existing.files!.isNotEmpty) {
        return existing.files!.first.id;
      }

      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';
      if (parentId != null) folder.parents = [parentId];

      final createdFolder = await _driveApi!.files.create(folder);
      return createdFolder.id;
    } catch (e) {
      print('Error creating folder: $e');
      return null;
    }
  }

  static Future<String?> uploadFile(
    File file,
    String fileName, {
    String? folderId,
    String? mimeType,
  }) async {
    if (!_initialized) await initialize();
    if (_driveApi == null) return null;

    try {
      final driveFile = drive.File()
        ..name = fileName
        ..mimeType = mimeType ?? 'application/octet-stream';
      if (folderId != null) driveFile.parents = [folderId];

      final media = drive.Media(file.openRead(), file.lengthSync());
      final response = await _driveApi!.files.create(driveFile, uploadMedia: media);

      await _driveApi!.permissions.create(
        drive.Permission()
          ..type = 'anyone'
          ..role = 'reader',
        response.id!,
      );

      return 'https://drive.google.com/file/d/${response.id}/view';
    } catch (e) {
      print('Error uploading file: $e');
      return null;
    }
  }

  static Future<Map<String, String?>> uploadReport({
    required File pdfFile,
    required String reportNumber,
    required String projectName,
    required String clientName,
    List<File>? photos,
  }) async {
    try {
      final rootFolderId = await createFolder('Interklima Raporty');
      if (rootFolderId == null) return {};

      final now = DateTime.now();
      final monthFolder =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final monthFolderId =
          await createFolder(monthFolder, parentId: rootFolderId);
      if (monthFolderId == null) return {};

      final pdfFileName =
          'raport_${reportNumber.replaceAll('/', '_')}.pdf';
      final pdfLink = await uploadFile(
        pdfFile,
        pdfFileName,
        folderId: monthFolderId,
        mimeType: 'application/pdf',
      );

      String? sessionFolderLink;

      if (photos != null && photos.isNotEmpty) {
        final sessionFolderName =
            'sesja_${projectName}_${clientName}_${reportNumber.replaceAll('/', '_')}';
        final sessionFolderId =
            await createFolder(sessionFolderName, parentId: monthFolderId);

        if (sessionFolderId != null) {
          sessionFolderLink =
              'https://drive.google.com/drive/folders/$sessionFolderId';
          for (int i = 0; i < photos.length; i++) {
            await uploadFile(
              photos[i],
              'zdjecie_${i + 1}.jpg',
              folderId: sessionFolderId,
              mimeType: 'image/jpeg',
            );
          }
        }
      }

      return {'pdfLink': pdfLink, 'sessionLink': sessionFolderLink};
    } catch (e) {
      print('Error uploading report: $e');
      return {};
    }
  }
}
