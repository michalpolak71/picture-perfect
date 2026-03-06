import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import '../models/photo_data.dart';
import '../services/google_drive_service.dart';
import '../services/google_sheets_service.dart';

class PdfReportScreen extends StatefulWidget {
  final List<PhotoData> photos;
  final String sessionName;

  const PdfReportScreen({
    super.key,
    required this.photos,
    required this.sessionName,
  });

  @override
  State<PdfReportScreen> createState() => _PdfReportScreenState();
}

class _PdfReportScreenState extends State<PdfReportScreen> {
  final _nameController = TextEditingController();
  final _projectController = TextEditingController();
  final _clientController = TextEditingController();
  final _notesController = TextEditingController();
  final List<Offset> _signaturePoints = [];
  bool _isSigningMode = false;
  bool _isGenerating = false;
  final GlobalKey _signatureKey = GlobalKey();
  int _reportNumber = 1;
  late List<bool> _selectedPhotos;

  @override
  void initState() {
    super.initState();
    _selectedPhotos = List.filled(widget.photos.length, true);
    _projectController.text = widget.sessionName;
    _loadReportNumber();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _projectController.dispose();
    _clientController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadReportNumber() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/report_counter.txt');
    if (await file.exists()) {
      final content = await file.readAsString();
      setState(() => _reportNumber = int.tryParse(content.trim()) ?? 1);
    }
  }

  Future<void> _incrementReportNumber() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/report_counter.txt');
    await file.writeAsString((_reportNumber + 1).toString());
    setState(() => _reportNumber++);
  }

  String get _reportNumberString {
    final now = DateTime.now();
    final months = [
      '', 'sty', 'lut', 'mar', 'kwi', 'maj', 'cze',
      'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'
    ];
    return 'Nr ${_reportNumber.toString().padLeft(3, '0')}/${now.day}/${months[now.month]}/${now.year}';
  }

  List<PhotoData> get _selectedPhotoList {
    final list = <PhotoData>[];
    for (int i = 0; i < widget.photos.length; i++) {
      if (_selectedPhotos[i]) list.add(widget.photos[i]);
    }
    return list;
  }

  Future<pw.MemoryImage?> _createSignatureImage() async {
    if (_signaturePoints.isEmpty) return null;
    try {
      final RenderBox? renderBox =
          _signatureKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return null;

      final padWidth = renderBox.size.width;
      final padHeight = renderBox.size.height;
      const pdfWidth = 300.0;
      const pdfHeight = 100.0;
      final scaleX = pdfWidth / padWidth;
      final scaleY = pdfHeight / padHeight;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
          recorder, const Rect.fromLTWH(0, 0, pdfWidth, pdfHeight));

      canvas.drawRect(
        const Rect.fromLTWH(0, 0, pdfWidth, pdfHeight),
        Paint()..color = const Color(0xFFFFFFFF),
      );

      final paint = Paint()
        ..color = const Color(0xFF000000)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;

      for (int i = 0; i < _signaturePoints.length - 1; i++) {
        if (_signaturePoints[i] != Offset.zero &&
            _signaturePoints[i + 1] != Offset.zero) {
          canvas.drawLine(
            Offset(_signaturePoints[i].dx * scaleX,
                _signaturePoints[i].dy * scaleY),
            Offset(_signaturePoints[i + 1].dx * scaleX,
                _signaturePoints[i + 1].dy * scaleY),
            paint,
          );
        }
      }

      final picture = recorder.endRecording();
      final img =
          await picture.toImage(pdfWidth.toInt(), pdfHeight.toInt());
      final byteData =
          await img.toByteData(format: ui.ImageByteFormat.png);
      return pw.MemoryImage(byteData!.buffer.asUint8List());
    } catch (e) {
      print('Signature error: $e');
      return null;
    }
  }

  Future<File?> _generatePdf({bool silent = false}) async {
    final selected = _selectedPhotoList;
    if (selected.isEmpty) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wybierz co najmniej jedno zdjęcie')),
        );
      }
      return null;
    }

    try {
      final pdf = pw.Document();
      final now = DateTime.now();

      pw.MemoryImage? signatureImage;
      if (_signaturePoints.isNotEmpty) {
        signatureImage = await _createSignatureImage();
      }

      // Load logo
      pw.MemoryImage? logoImage;
      try {
        final logoData = await rootBundle.load('assets/logo.png');
        logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
      } catch (_) {}

      // Title page
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  if (logoImage != null) pw.Image(logoImage!, width: 120, height: 40)
                  else
                    pw.Text('INTERKLIMA',
                        style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900)),
                  pw.Text(
                    '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}',
                    style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
                  ),
                ],
              ),
              pw.SizedBox(height: 30),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue900,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('RAPORT ZDJĘCIOWY',
                        style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white)),
                    pw.SizedBox(height: 8),
                    pw.Text(_reportNumberString,
                        style: const pw.TextStyle(
                            fontSize: 13, color: PdfColors.blue100)),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),
              _pdfInfoRow('Projekt:', _projectController.text),
              _pdfInfoRow('Klient:', _clientController.text),
              _pdfInfoRow('Sporządził:', _nameController.text),
              _pdfInfoRow('Liczba zdjęć:', '${selected.length}'),
              if (_notesController.text.isNotEmpty) ...[
                pw.SizedBox(height: 16),
                pw.Text('Uwagi:',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.SizedBox(height: 4),
                pw.Text(_notesController.text,
                    style: const pw.TextStyle(fontSize: 11)),
              ],
              pw.Spacer(),
              if (signatureImage != null) ...[
                pw.Divider(),
                pw.SizedBox(height: 8),
                pw.Text('Podpis sporządzającego:',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey600)),
                pw.SizedBox(height: 6),
                pw.Image(signatureImage, width: 200, height: 70),
                pw.Text(_nameController.text,
                    style: const pw.TextStyle(fontSize: 10)),
              ],
            ],
          );
        },
      ));

      // Photo pages
      for (int i = 0; i < selected.length; i++) {
        final photo = selected[i];
        final photoDate =
            DateTime.fromMillisecondsSinceEpoch(photo.timestamp);

        pw.MemoryImage? photoImage;
        try {
          final bytes = await File(photo.imagePath).readAsBytes();
          photoImage = pw.MemoryImage(bytes);
        } catch (_) {
          continue;
        }

        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Zdjęcie ${i + 1} / ${selected.length}',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 12,
                            color: PdfColors.blue900)),
                    pw.Text(
                      '${photoDate.day.toString().padLeft(2, '0')}.${photoDate.month.toString().padLeft(2, '0')}.${photoDate.year}  '
                      '${photoDate.hour.toString().padLeft(2, '0')}:${photoDate.minute.toString().padLeft(2, '0')}',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey600),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),

                // Photo
                pw.Image(photoImage!,
                    width: double.infinity,
                    height: 380,
                    fit: pw.BoxFit.contain),
                pw.SizedBox(height: 10),

                // Description
                if (photo.description.isNotEmpty) ...[
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(photo.description,
                        style: const pw.TextStyle(fontSize: 11)),
                  ),
                  pw.SizedBox(height: 8),
                ],

                // GPS
                if (photo.hasLocation())
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.green50,
                      border: pw.Border.all(color: PdfColors.green200),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('GPS:',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                                color: PdfColors.green800)),
                        pw.Text(
                          '${photo.latitude!.toStringAsFixed(6)}, ${photo.longitude!.toStringAsFixed(6)}',
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.green800),
                        ),
                        if (photo.altitude != null)
                          pw.Text(
                            'Wysokość: ${photo.altitude!.toStringAsFixed(1)}m n.p.m.',
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.green700),
                          ),
                      ],
                    ),
                  ),

                pw.Spacer(),
                pw.Divider(color: PdfColors.grey300),
                pw.Text(_reportNumberString,
                    style: const pw.TextStyle(
                        fontSize: 8, color: PdfColors.grey400)),
              ],
            );
          },
        ));
      }

      final directory = await getApplicationDocumentsDirectory();
      final pdfPath =
          '${directory.path}/raport_${_reportNumber.toString().padLeft(3, '0')}_${now.millisecondsSinceEpoch}.pdf';
      final file = File(pdfPath);
      await file.writeAsBytes(await pdf.save());
      return file;
    } catch (e) {
      print('PDF error: $e');
      return null;
    }
  }

  pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(label,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 11)),
          ),
          pw.Expanded(
            child: pw.Text(
                value.isEmpty ? '—' : value,
                style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Future<void> _shareOnly() async {
    setState(() => _isGenerating = true);
    try {
      final file = await _generatePdf();
      if (file != null && mounted) {
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Raport - ${_projectController.text}',
          text: 'Raport zdjęciowy: ${_projectController.text}',
        );
        await _incrementReportNumber();
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _archiveAndSend() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wpisz imię i nazwisko sporządzającego')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    // Step 1: Generate PDF
    _showProgress('Generowanie PDF...');
    final pdfFile = await _generatePdf(silent: true);
    if (!mounted) return;
    Navigator.pop(context); // close dialog

    if (pdfFile == null) {
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Błąd generowania PDF')),
      );
      return;
    }

    // Step 2: Upload to Drive
    _showProgress('Wysyłanie na Google Drive...');
    Map<String, String?> driveResult = {};
    String? driveError;
    try {
      final driveService = GoogleDriveService();
      await driveService.initialize();
      driveResult = await driveService.uploadReport(
        pdfFile: pdfFile,
        reportNumber: _reportNumberString,
        projectName: _projectController.text,
        clientName: _clientController.text,
        photos: _selectedPhotoList,
      );
    } catch (e) {
      driveError = e.toString();
      print('Drive error: $e');
    }
    if (!mounted) return;
    Navigator.pop(context);

    // Step 3: Add to Sheets
    _showProgress('Dodawanie do arkusza...');
    String? sheetsError;
    try {
      final sheetsService = GoogleSheetsService();
      await sheetsService.initialize();
      await sheetsService.addReportRow(
        date: DateTime.now(),
        reportNumber: _reportNumberString,
        projectName: _projectController.text,
        clientName: _clientController.text,
        createdBy: _nameController.text,
        photoCount: _selectedPhotoList.length,
        pdfLink: driveResult['pdfLink'],
        sessionLink: driveResult['sessionLink'],
      );
    } catch (e) {
      sheetsError = e.toString();
      print('Sheets error: $e');
    }
    if (!mounted) return;
    Navigator.pop(context);

    await _incrementReportNumber();
    setState(() => _isGenerating = false);

    // Show result
    _showResultDialog(
      pdfFile: pdfFile,
      driveResult: driveResult,
      driveError: driveError,
      sheetsError: sheetsError,
    );
  }

  void _showProgress(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(message),
          ],
        ),
      ),
    );
  }

  void _showResultDialog({
    required File pdfFile,
    required Map<String, String?> driveResult,
    String? driveError,
    String? sheetsError,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Raport wysłany'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _resultRow('PDF wygenerowany', true),
            _resultRow('Google Drive', driveError == null),
            _resultRow('Google Sheets', sheetsError == null),
            if (driveError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Drive: $driveError',
                    style: const TextStyle(fontSize: 10, color: Colors.red)),
              ),
            if (sheetsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Sheets: $sheetsError',
                    style: const TextStyle(fontSize: 10, color: Colors.red)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zamknij'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await Share.shareXFiles(
                [XFile(pdfFile.path)],
                subject: 'Raport - ${_projectController.text}',
              );
            },
            icon: const Icon(Icons.share),
            label: const Text('Udostępnij PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0066CC),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, bool success) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            success ? Icons.check_circle : Icons.error,
            color: success ? Colors.green : Colors.red,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0066CC),
        foregroundColor: Colors.white,
        title: const Text('Raport PDF'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Udostępnij PDF',
            onPressed: _isGenerating ? null : _shareOnly,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Report info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_reportNumberString,
                        style: const TextStyle(
                            color: Color(0xFF0066CC),
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Imię i nazwisko *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _projectController,
                      decoration: const InputDecoration(
                        labelText: 'Nazwa projektu',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.work),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _clientController,
                      decoration: const InputDecoration(
                        labelText: 'Klient',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.business),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Uwagi',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.notes),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Photo selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Zdjęcia do raportu',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(
                          '${_selectedPhotos.where((s) => s).length}/${widget.photos.length}',
                          style: const TextStyle(color: Color(0xFF0066CC)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(widget.photos.length, (i) {
                      final photo = widget.photos[i];
                      final date = DateTime.fromMillisecondsSinceEpoch(
                          photo.timestamp);
                      return CheckboxListTile(
                        value: _selectedPhotos[i],
                        onChanged: (val) =>
                            setState(() => _selectedPhotos[i] = val ?? false),
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          photo.description.isEmpty
                              ? 'Zdjęcie ${i + 1}'
                              : photo.description,
                          style: const TextStyle(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Row(
                          children: [
                            Icon(
                              photo.hasLocation()
                                  ? Icons.location_on
                                  : Icons.location_off,
                              size: 12,
                              color: photo.hasLocation()
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${date.day}.${date.month}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                        secondary: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.file(
                            File(photo.imagePath),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.broken_image),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Signature
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Podpis',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        if (!_isSigningMode)
                          ElevatedButton(
                            onPressed: () {
                              setState(() => _isSigningMode = true);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0066CC),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Podpisz'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (!_isSigningMode && _signaturePoints.isEmpty)
                      Container(
                        key: _signatureKey,
                        width: double.infinity,
                        height: 100,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[50],
                        ),
                        child: Center(
                          child: Text('Brak podpisu',
                              style: TextStyle(color: Colors.grey[400])),
                        ),
                      ),

                    if (!_isSigningMode && _signaturePoints.isNotEmpty)
                      Container(
                        key: _signatureKey,
                        width: double.infinity,
                        height: 100,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.green),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: CustomPaint(
                          painter: SignaturePainter(_signaturePoints),
                        ),
                      ),

                    if (_isSigningMode) ...[
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF0066CC), width: 2),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: GestureDetector(
                          onPanUpdate: (d) => setState(
                              () => _signaturePoints.add(d.localPosition)),
                          onPanEnd: (_) => setState(
                              () => _signaturePoints.add(Offset.zero)),
                          child: CustomPaint(
                            key: _signatureKey,
                            painter: SignaturePainter(_signaturePoints),
                            child: Container(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: () => setState(() {
                              _signaturePoints.clear();
                            }),
                            child: const Text('Wyczyść'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () =>
                                setState(() => _isSigningMode = false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0066CC),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Gotowe'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isGenerating ? null : _shareOnly,
                    icon: const Icon(Icons.share),
                    label: const Text('Udostępnij PDF'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isGenerating ? null : _archiveAndSend,
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: const Text('Archiwizuj i wyślij'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0066CC),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class SignaturePainter extends CustomPainter {
  final List<Offset> points;

  SignaturePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != Offset.zero && points[i + 1] != Offset.zero) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}


