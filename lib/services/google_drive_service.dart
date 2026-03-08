import 'package:googleapis/storage/v1.dart' as gcs;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';

class GoogleDriveService {
  static const String _bucketName = 'interklima-raporty-pdf';
  static const List<String> _scopes = [gcs.StorageApi.devstorageFullControlScope];

  gcs.StorageApi? _storageApi;

  Future<void> initialize() async {
    final jsonStr = await rootBundle.loadString('assets/service_account.json');
    final credentials = ServiceAccountCredentials.fromJson(json.decode(jsonStr));
    final client = await clientViaServiceAccount(credentials, _scopes);
    _storageApi = gcs.StorageApi(client);
  }

  Future<String?> uploadPdf(File pdfFile, String fileName) async {
    if (_storageApi == null) throw Exception('Storage not initialized');

    final now = DateTime.now();
    final months = [
      '', 'sty', 'lut', 'mar', 'kwi', 'maj', 'cze',
      'lip', 'sie', 'wrz', 'paz', 'lis', 'gru'
    ];
    final folder =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${months[now.month]}';
    final objectName = '$folder/$fileName';

    final object = gcs.Object()
      ..name = objectName
      ..contentType = 'application/pdf';

    final media = gcs.Media(pdfFile.openRead(), await pdfFile.length());

    await _storageApi!.objects.insert(
      object,
      _bucketName,
      uploadMedia: media,
      predefinedAcl: 'publicRead',
    );

    return 'https://storage.googleapis.com/$_bucketName/$objectName';
  }
}
