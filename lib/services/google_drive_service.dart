import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';

class GoogleDriveService {
  static const String _rootFolderName = 'Interklima Raporty';
  static const List<String> _scopes = [drive.DriveApi.driveScope];

  drive.DriveApi? _driveApi;

  Future<void> initialize() async {
    final jsonStr = await rootBundle.loadString('assets/service_account.json');
    final credentials = ServiceAccountCredentials.fromJson(json.decode(jsonStr));
    final client = await clientViaServiceAccount(credentials, _scopes);
    _driveApi = drive.DriveApi(client);
  }

  Future<String> _findOrCreateFolder(String name, {String? parentId}) async {
    String query = "name='$name' and mimeType='application/vnd.google-apps.folder' and trashed=false";
    if (parentId != null) {
      query = "name='$name' and '$parentId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false";
    }

    final result = await _driveApi!.files.list(q: query, $fields: 'files(id)');
    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id!;
    }

    final folder = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder';
    if (parentId != null) folder.parents = [parentId];

    final created = await _driveApi!.files.create(folder, $fields: 'id');
    return created.id!;
  }

  Future<String?> uploadPdf(File pdfFile, String fileName) async {
    if (_driveApi == null) throw Exception('Drive not initialized');

    final now = DateTime.now();
    final months = ['', 'sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paz', 'lis', 'gru'];

    // Root folder
    final rootId = await _findOrCreateFolder(_rootFolderName);

    // Month subfolder
    final monthName = '${now.year}-${now.month.toString().padLeft(2, '0')}-${months[now.month]}';
    final monthId = await _findOrCreateFolder(monthName, parentId: rootId);

    // Upload PDF
    final driveFile = drive.File()
      ..name = fileName
      ..parents = [monthId];

    final media = drive.Media(pdfFile.openRead(), await pdfFile.length());
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
  }
}
