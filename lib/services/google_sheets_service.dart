import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class GoogleSheetsService {
  static const String spreadsheetId =
      '1RmrAKaeHcq1GAcfogJfRGAprmiciPy6XERJhKprIkqk';
  static const String sheetName = 'Raporty';
  static const List<String> _scopes = [sheets.SheetsApi.spreadsheetsScope];

  sheets.SheetsApi? _sheetsApi;

  Future<void> initialize() async {
    try {
      final jsonStr =
          await rootBundle.loadString('assets/service_account.json');
      final credentials =
          ServiceAccountCredentials.fromJson(json.decode(jsonStr));
      final client =
          await clientViaServiceAccount(credentials, _scopes);
      _sheetsApi = sheets.SheetsApi(client);
    } catch (e) {
      print('Sheets init error: $e');
      rethrow;
    }
  }

  Future<void> addReportRow({
    required DateTime date,
    required String reportNumber,
    required String projectName,
    required String clientName,
    required String createdBy,
    required int photoCount,
    String? pdfLink,
    String? sessionLink,
  }) async {
    if (_sheetsApi == null) throw Exception('Sheets not initialized');

    final dateStr =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

    final row = [
      dateStr,
      reportNumber,
      projectName,
      clientName,
      createdBy,
      photoCount.toString(),
      pdfLink ?? '',
      sessionLink ?? '',
      '✓',
    ];

    final valueRange = sheets.ValueRange(values: [row]);

    await _sheetsApi!.spreadsheets.values.append(
      valueRange,
      spreadsheetId,
      '$sheetName!A:I',
      valueInputOption: 'RAW',
    );
  }
}
