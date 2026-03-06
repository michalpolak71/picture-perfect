import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

class GoogleSheetsService {
  static const _scopes = [sheets.SheetsApi.spreadsheetsScope];
  static sheets.SheetsApi? _sheetsApi;
  static bool _initialized = false;

  // ⚠️ Wpisz swoje ID arkusza po konfiguracji Google Cloud
  static const String spreadsheetId = 'YOUR_SPREADSHEET_ID_HERE';
  static const String sheetName = 'Raporty';

  static Future<bool> initialize() async {
    if (_initialized) return true;
    try {
      final jsonString =
          await rootBundle.loadString('assets/service_account.json');
      final accountCredentials =
          ServiceAccountCredentials.fromJson(json.decode(jsonString));
      final client =
          await clientViaServiceAccount(accountCredentials, _scopes);
      _sheetsApi = sheets.SheetsApi(client);
      _initialized = true;
      return true;
    } catch (e) {
      print('Error initializing Google Sheets: $e');
      return false;
    }
  }

  static Future<bool> addReportRow({
    required String date,
    required String reportNumber,
    required String project,
    required String client,
    required String createdBy,
    required int photoCount,
    String? pdfLink,
    String? sessionLink,
    String? floorInfo,
  }) async {
    if (!_initialized) await initialize();
    if (_sheetsApi == null) return false;

    try {
      final rowData = [
        date,
        reportNumber,
        project,
        client,
        createdBy,
        photoCount.toString(),
        floorInfo ?? '',
        pdfLink ?? '',
        sessionLink ?? '',
        '✓',
      ];

      final valueRange = sheets.ValueRange()..values = [rowData];

      await _sheetsApi!.spreadsheets.values.append(
        valueRange,
        spreadsheetId,
        '$sheetName!A:J',
        valueInputOption: 'RAW',
      );

      return true;
    } catch (e) {
      print('Error adding row to sheet: $e');
      return false;
    }
  }

  static Future<bool> createSheetStructure() async {
    if (!_initialized) await initialize();
    if (_sheetsApi == null) return false;

    try {
      final headers = [
        'Data',
        'Nr raportu',
        'Projekt',
        'Klient',
        'Sporządził',
        'Liczba zdjęć',
        'Kondygnacje',
        'Link PDF',
        'Link Sesja',
        'Status',
      ];

      final valueRange = sheets.ValueRange()..values = [headers];

      await _sheetsApi!.spreadsheets.values.update(
        valueRange,
        spreadsheetId,
        '$sheetName!A1:J1',
        valueInputOption: 'RAW',
      );

      return true;
    } catch (e) {
      print('Error creating sheet structure: $e');
      return false;
    }
  }
}
