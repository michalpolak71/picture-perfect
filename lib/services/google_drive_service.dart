import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';

class GoogleDriveService {
  static const String _rootFolderId = '10FYUR8tpncJX8mP5SQy1kghnWg2jmvV_';
  static const List<String> _scopes = [drive.DriveApi.driveScope];

  drive.DriveApi? _driveApi;

  Future<void> initialize() async {
    final jsonStr = await rootBundle.loadString('assets/service_account.json');
    final credentials = ServiceAccountCredentials.fromJson(json.decode(jsonStr));
    final client = await clientViaServiceAccount(credentials, _scopes);
    _driveApi = drive.DriveApi(client);
  }

  Future<String> _findOrCreateSubfolder(String name) async {
    final query =
        "name='$name' and '$_rootFolderId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false";
    final result = await _driveApi!.files.list(
      q: query,
      $fields: 'files(id)',
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    );

    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id!;
    }

    final folder = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = [_rootFolderId];

    final created = await _driveApi!.files.create(
      folder,
      $fields: 'id',
      supportsAllDrives: true,
    );
    return created.id!;
  }

  Future<String?> uploadPdf(File pdfFile, String fileName) async {
    if (_driveApi == null) throw Exception('Drive not initialized');

    final now = DateTime.now();
    final months = [
      '', 'sty', 'lut', 'mar', 'kwi', 'maj', 'cze',
      'lip', 'sie', 'wrz', 'paz', 'lis', 'gru'
    ];

    final monthName =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${months[now.month]}';
    final monthId = await _findOrCreateSubfolder(monthName);

    final driveFile = drive.File()
      ..name = fileName
      ..parents = [monthId];

    final media = drive.Media(pdfFile.openRead(), await pdfFile.length());
    final result = await _driveApi!.files.create(
      driveFile,
      uploadMedia: media,
      $fields: 'id, webViewLink',
      supportsAllDrives: true,
    );

    // Udostępnij publicznie
    final permission = drive.Permission()
      ..role = 'reader'
      ..type = 'anyone';
    await _driveApi!.permissions.create(
      permission,
      result.id!,
      supportsAllDrives: true,
    );

    return result.webViewLink;
  }
}
