import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/google_drive_service.dart';
import '../services/google_sheets_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<File> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    final directory = await getApplicationDocumentsDirectory();
    final files = Directory(directory.path)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf'))
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    setState(() {
      _reports = files;
      _loading = false;
    });
  }

  String _fileName(File f) => f.path.split(Platform.pathSeparator).last;

  String _fileDate(File f) {
    final d = f.lastModifiedSync();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}  ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<Map<String, dynamic>> _loadMeta(File f) async {
    try {
      final metaPath = f.path.replaceAll('.pdf', '.json');
      final metaFile = File(metaPath);
      if (await metaFile.exists()) {
        return json.decode(await metaFile.readAsString());
      }
    } catch (_) {}
    return {};
  }

  Future<void> _shareByEmail(File f) async {
    await Share.shareXFiles([XFile(f.path)], subject: _fileName(f));
  }

  Future<void> _uploadToCloud(File f) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Text('Wysyłanie do chmury...'),
        ]),
      ),
    );

    try {
      final meta = await _loadMeta(f);

      final driveService = GoogleDriveService();
      await driveService.initialize();
      final pdfLink = await driveService.uploadPdf(f, _fileName(f));

      final sheetsService = GoogleSheetsService();
      await sheetsService.initialize();
      await sheetsService.addReportRow(
        date: f.lastModifiedSync(),
        reportNumber: meta['reportNumber'] ?? _fileName(f),
        docType: meta['docType'] ?? 'Raport',
        projectName: meta['project'] ?? '-',
        clientName: meta['client'] ?? '-',
        createdBy: meta['author'] ?? '-',
        photoCount: meta['photoCount'] ?? 0,
        pdfLink: pdfLink,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Wysłano do Drive i Sheets!'),
            ]),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd wysyłania: $e')),
        );
      }
    }
  }

  Future<void> _deleteReport(File f) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usuń raport'),
        content: Text('Usunąć ${_fileName(f)}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Anuluj')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Usuń', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await f.delete();
      final metaFile = File(f.path.replaceAll('.pdf', '.json'));
      if (await metaFile.exists()) await metaFile.delete();
      _loadReports();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raporty PDF'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadReports),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Brak raportów',
                          style: TextStyle(fontSize: 18, color: Colors.grey)),
                      SizedBox(height: 8),
                      Text('Wygeneruj raport w sekcji Sesje',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _reports.length,
                  itemBuilder: (context, index) {
                    final f = _reports[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const Icon(Icons.picture_as_pdf,
                            color: Colors.red, size: 40),
                        title: Text(_fileName(f),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(_fileDate(f)),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'email') _shareByEmail(f);
                            if (value == 'cloud') _uploadToCloud(f);
                            if (value == 'delete') _deleteReport(f);
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'email',
                              child: Row(children: [
                                Icon(Icons.email, size: 20),
                                SizedBox(width: 8),
                                Text('Wyślij e-mail'),
                              ]),
                            ),
                            const PopupMenuItem(
                              value: 'cloud',
                              child: Row(children: [
                                Icon(Icons.cloud_upload, size: 20),
                                SizedBox(width: 8),
                                Text('Wyślij do chmury'),
                              ]),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(children: [
                                Icon(Icons.delete, size: 20, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Usuń',
                                    style: TextStyle(color: Colors.red)),
                              ]),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
