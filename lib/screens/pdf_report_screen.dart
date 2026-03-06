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

  const PdfReportScreen({super.key, required this.photos});

  @override
  State<PdfReportScreen> createState() => _PdfReportScreenState();
}

class _PdfReportScreenState extends State<PdfReportScreen> {
  final _nameController = TextEditingController();
  final _projectController = TextEditingController();
  final _clientController = TextEditingController();
  final _summaryController = TextEditingController();
  final List<Offset> _signaturePoints = [];
  final Set<int> _selectedPhotos = {};
  int _reportNumber = 1;
  bool _isSigningMode = false;
  bool _isArchiving = false;
  final GlobalKey _signatureKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  File? _generatedPdfFile;
  String? _lastReportNum;

  @override
  void initState() {
    super.initState();
    _loadReportNumber();
    for (int i = 0; i < widget.photos.length; i++) {
      _selectedPhotos.add(i);
    }
  }

  Future<void> _loadReportNumber() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final counterFile = File('${directory.path}/report_counter.txt');
      if (await counterFile.exists()) {
        final content = await counterFile.readAsString();
        setState(() => _reportNumber = int.tryParse(content) ?? 1);
      }
    } catch (e) {
      print('Error loading report number: $e');
    }
  }

  Future<void> _saveReportNumber() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final counterFile = File('${directory.path}/report_counter.txt');
      await counterFile.writeAsString((_reportNumber + 1).toString());
    } catch (e) {
      print('Error saving report number: $e');
    }
  }

  String _getReportNumber() {
    final now = DateTime.now();
    final months = [
      'sty', 'lut', 'mar', 'kwi', 'maj', 'cze',
      'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'
    ];
    return 'Nr ${_reportNumber.toString().padLeft(3, '0')}/${now.day}/${months[now.month - 1]}/${now.year}';
  }

  // Collect unique floor info from selected photos
  String _getFloorInfo() {
    final selectedList = _selectedPhotos.toList()..sort();
    final floors = <String>{};
    for (final i in selectedList) {
      final photo = widget.photos[i];
      if (photo.floorLabel != null) floors.add(photo.floorLabel!);
    }
    return floors.isEmpty ? '' : floors.join(', ');
  }

  Future<File?> _generatePdf({bool silent = false}) async {
    if (_nameController.text.isEmpty ||
        _projectController.text.isEmpty ||
        _clientController.text.isEmpty) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Wypełnij imię/nazwisko, projekt i klienta')),
        );
      }
      return null;
    }

    if (_selectedPhotos.isEmpty) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wybierz przynajmniej jedno zdjęcie')),
        );
      }
      return null;
    }

    try {
      final pdf = pw.Document();
      final logoData = await rootBundle.load('assets/logo.png');
      final logo = pw.MemoryImage(logoData.buffer.asUint8List());

      final fontData = await rootBundle.load('fonts/Roboto-Regular.ttf');
      final ttf = pw.Font.ttf(fontData);
      final fontBoldData = await rootBundle.load('fonts/Roboto-Bold.ttf');
      final ttfBold = pw.Font.ttf(fontBoldData);
      final theme = pw.ThemeData.withFont(base: ttf, bold: ttfBold);

      pw.MemoryImage? signatureImage;
      if (_signaturePoints.isNotEmpty) {
        signatureImage = await _createSignatureImage();
      }

      final reportNum = _getReportNumber();
      _lastReportNum = reportNum;
      final selectedPhotosList = _selectedPhotos.toList()..sort();
      final now = DateTime.now();

      // Title page
      pdf.addPage(pw.Page(
        theme: theme,
        build: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Image(logo, width: 200),
            pw.SizedBox(height: 40),
            pw.Text('RAPORT Z DOKUMENTACJI',
                style: pw.TextStyle(
                    fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 20),
            pw.Text(reportNum,
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Text('Projekt: ${_projectController.text}',
                style: const pw.TextStyle(fontSize: 16)),
            pw.SizedBox(height: 8),
            pw.Text('Klient: ${_clientController.text}',
                style: const pw.TextStyle(fontSize: 16)),
            pw.SizedBox(height: 8),
            pw.Text(
                'Data sporządzenia: ${now.day}.${now.month}.${now.year}',
                style: const pw.TextStyle(fontSize: 16)),
            pw.SizedBox(height: 8),
            pw.Text('Sporządził: ${_nameController.text}',
                style: const pw.TextStyle(fontSize: 16)),
            pw.SizedBox(height: 8),
            pw.Text(
                'Liczba zdjęć: ${selectedPhotosList.length}',
                style: const pw.TextStyle(fontSize: 16)),
            // V9: Floor info on title page
            if (_getFloorInfo().isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text('Kondygnacje: ${_getFloorInfo()}',
                  style: const pw.TextStyle(fontSize: 16)),
            ],
            pw.Spacer(),
            _buildFooter(),
          ],
        ),
      ));

      // Photo pages
      for (int i = 0; i < selectedPhotosList.length; i++) {
        final photoIndex = selectedPhotosList[i];
        final photo = widget.photos[photoIndex];
        final date =
            DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
        final imageBytes =
            await File(photo.imagePath).readAsBytes();
        final image = pw.MemoryImage(imageBytes);

        pdf.addPage(pw.Page(
          theme: theme,
          build: (pw.Context ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                      'Zdjęcie ${i + 1}/${selectedPhotosList.length}',
                      style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                      '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                      style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Expanded(
                  child: pw.Image(image, fit: pw.BoxFit.contain)),
              pw.SizedBox(height: 10),
              if (photo.description.isNotEmpty) ...[
                pw.Text('Opis:',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold)),
                pw.Text(photo.description),
                pw.SizedBox(height: 5),
              ],
              // V9: Floor info in photo page
              if (photo.floorLabel != null) ...[
                pw.Text('Kondygnacja:',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold)),
                pw.Text(
                    '${photo.floorLabel}${photo.relativeHeight != null ? ' (${photo.relativeHeight! >= 0 ? '+' : ''}${photo.relativeHeight!.toStringAsFixed(2)}m)' : ''}'),
                pw.SizedBox(height: 5),
              ],
              if (photo.hasLocation()) ...[
                pw.Text('Lokalizacja GPS:',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold)),
                pw.UrlLink(
                  destination:
                      'https://maps.google.com/?q=${photo.latitude},${photo.longitude}',
                  child: pw.Text(
                    '${photo.latitude!.toStringAsFixed(6)}, ${photo.longitude!.toStringAsFixed(6)}',
                    style:
                        const pw.TextStyle(color: PdfColors.blue),
                  ),
                ),
              ],
              if (photo.altitude != null) ...[
                pw.SizedBox(height: 3),
                pw.Text(
                    'Wysokość n.p.m.: ${photo.altitude!.toStringAsFixed(1)}m',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey700)),
              ],
              pw.Spacer(),
              _buildFooter(),
            ],
          ),
        ));
      }

      // Summary page
      pdf.addPage(pw.Page(
        theme: theme,
        build: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('PODSUMOWANIE',
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
            if (_summaryController.text.isNotEmpty) ...[
              pw.Text(_summaryController.text),
              pw.SizedBox(height: 30),
            ],
            pw.Spacer(),
            pw.Text('Podpis sporządzającego:',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            if (signatureImage != null)
              pw.Container(
                height: 100,
                width: 300,
                decoration: pw.BoxDecoration(
                    border: pw.Border.all()),
                child: pw.Image(signatureImage,
                    fit: pw.BoxFit.contain),
              )
            else
              pw.Container(
                height: 100,
                width: 300,
                decoration: pw.BoxDecoration(
                    border: pw.Border.all()),
              ),
            pw.SizedBox(height: 10),
            pw.Text(_nameController.text),
            pw.Text(
                'Data: ${now.day}.${now.month}.${now.year}'),
            pw.Spacer(),
            _buildFooter(),
          ],
        ),
      ));

      final directory = await getApplicationDocumentsDirectory();
      final pdfPath =
          '${directory.path}/raport_${_reportNumber.toString().padLeft(3, '0')}_${now.millisecondsSinceEpoch}.pdf';
      final file = File(pdfPath);
      await file.writeAsBytes(await pdf.save());
      await _saveReportNumber();

      return file;
    } catch (e) {
      print('Error generating PDF: $e');
      return null;
    }
  }

  Future<void> _generateAndShare() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator()),
    );

    final file = await _generatePdf();

    if (mounted) Navigator.pop(context);

    if (file == null) return;

    setState(() => _generatedPdfFile = file);

    if (mounted) {
      Navigator.pop(context);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject:
            'Raport Interklima ${_lastReportNum ?? ''} - ${_projectController.text}',
      );
    }
  }

  // V9: Archiwizuj i wyślij - Upload to Drive + add row to Sheets
  Future<void> _archiveAndSend() async {
    if (_nameController.text.isEmpty ||
        _projectController.text.isEmpty ||
        _clientController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Wypełnij imię/nazwisko, projekt i klienta')),
      );
      return;
    }

    setState(() => _isArchiving = true);

    try {
      // Step 1: Generate PDF
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Generowanie PDF...'),
            ],
          ),
        ),
      );

      final pdfFile = await _generatePdf(silent: true);
      if (mounted) Navigator.pop(context);

      if (pdfFile == null) {
        setState(() => _isArchiving = false);
        return;
      }

      // Step 2: Upload to Google Drive
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Wysyłanie na Google Drive...'),
            ],
          ),
        ),
      );

      final selectedPhotosList = _selectedPhotos.toList()..sort();
      final photos = selectedPhotosList
          .map((i) => File(widget.photos[i].imagePath))
          .where((f) => f.existsSync())
          .toList();

      final driveResult = await GoogleDriveService.uploadReport(
        pdfFile: pdfFile,
        reportNumber: _lastReportNum ?? _getReportNumber(),
        projectName: _projectController.text,
        clientName: _clientController.text,
        photos: photos,
      );

      if (mounted) Navigator.pop(context);

      // Step 3: Add row to Google Sheets
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Dodawanie do arkusza...'),
            ],
          ),
        ),
      );

      final now = DateTime.now();
      final date =
          '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

      await GoogleSheetsService.addReportRow(
        date: date,
        reportNumber: _lastReportNum ?? _getReportNumber(),
        project: _projectController.text,
        client: _clientController.text,
        createdBy: _nameController.text,
        photoCount: selectedPhotosList.length,
        pdfLink: driveResult['pdfLink'],
        sessionLink: driveResult['sessionLink'],
        floorInfo: _getFloorInfo(),
      );

      if (mounted) Navigator.pop(context);

      setState(() => _isArchiving = false);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Zarchiwizowano!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (driveResult['pdfLink'] != null)
                  Text('✅ PDF: Google Drive',
                      style: TextStyle(color: Colors.green[700])),
                if (driveResult['sessionLink'] != null)
                  Text('✅ Zdjęcia: Google Drive',
                      style: TextStyle(color: Colors.green[700])),
                const Text('✅ Wiersz: Google Sheets',
                    style: TextStyle(color: Colors.green)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await Share.shareXFiles(
                    [XFile(pdfFile.path)],
                    subject:
                        'Raport Interklima ${_lastReportNum ?? ''} - ${_projectController.text}',
                  );
                },
                icon: const Icon(Icons.share),
                label: const Text('Udostępnij PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[900],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd archiwizacji: $e')),
        );
      }
      setState(() => _isArchiving = false);
    }
  }

  pw.Widget _buildFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            top: pw.BorderSide(color: PdfColors.grey400)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Biuro Warszawa/Babice Nowe:',
              style: pw.TextStyle(
                  fontSize: 8, fontWeight: pw.FontWeight.bold)),
          pw.Text(
              'ul. Ogrodnicza 76, 05-082 Babice Nowe',
              style: const pw.TextStyle(fontSize: 8)),
          pw.Text(
              'b.drabicki@interklima.pl  |  kom. Bartłomiej Drabicki 608 651 538',
              style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  Future<pw.MemoryImage> _createSignatureImage() async {
    final RenderBox? renderBox = _signatureKey.currentContext
        ?.findRenderObject() as RenderBox?;
    final padWidth = renderBox?.size.width ?? 300.0;
    final padHeight = renderBox?.size.height ?? 200.0;
    const pdfWidth = 300.0;
    const pdfHeight = 100.0;
    final scaleX = pdfWidth / padWidth;
    final scaleY = pdfHeight / padHeight;

    final recorder = ui.PictureRecorder();
    final canvas =
        Canvas(recorder, const Rect.fromLTWH(0, 0, pdfWidth, pdfHeight));
    canvas.drawRect(
        const Rect.fromLTWH(0, 0, pdfWidth, pdfHeight),
        Paint()..color = const Color(0xFFFFFFFF));

    final paint = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 3.0
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
    final img = await picture.toImage(
        pdfWidth.toInt(), pdfHeight.toInt());
    final byteData =
        await img.toByteData(format: ui.ImageByteFormat.png);
    return pw.MemoryImage(byteData!.buffer.asUint8List());
  }

  void _enterSigningMode() {
    setState(() => _isSigningMode = true);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_signatureKey.currentContext != null) {
        Scrollable.ensureVisible(_signatureKey.currentContext!,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut);
      }
    });
  }

  void _exitSigningMode() => setState(() => _isSigningMode = false);

  @override
  void dispose() {
    _nameController.dispose();
    _projectController.dispose();
    _clientController.dispose();
    _summaryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raport PDF'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Generuj i udostępnij',
            onPressed: _generateAndShare,
          ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        physics: _isSigningMode
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Numer raportu: ${_getReportNumber()}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Form fields
            _buildTextField(_nameController, 'Imię i nazwisko *'),
            const SizedBox(height: 16),
            _buildTextField(_projectController, 'Nazwa projektu *'),
            const SizedBox(height: 16),
            _buildTextField(_clientController, 'Klient *'),
            const SizedBox(height: 16),
            _buildTextField(_summaryController, 'Podsumowanie (opcjonalne)',
                maxLines: 4),
            const SizedBox(height: 24),

            // Photo selection
            const Text('Wybierz zdjęcia:',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...List.generate(widget.photos.length, (index) {
              final photo = widget.photos[index];
              final date =
                  DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
              return CheckboxListTile(
                value: _selectedPhotos.contains(index),
                activeColor: Colors.black87,
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
                      _selectedPhotos.add(index);
                    } else {
                      _selectedPhotos.remove(index);
                    }
                  });
                },
                title: Text(
                    '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(photo.description.isEmpty
                        ? 'Bez opisu'
                        : photo.description),
                    // V9: Show floor info in checkbox
                    if (photo.floorLabel != null)
                      Row(
                        children: [
                          const Icon(Icons.layers,
                              size: 12, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text(photo.floorLabel!,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.blue)),
                        ],
                      ),
                  ],
                ),
                secondary: File(photo.imagePath).existsSync()
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(photo.imagePath),
                            width: 60, height: 60, fit: BoxFit.cover),
                      )
                    : null,
              );
            }),

            const SizedBox(height: 24),

            // Signature section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Podpis cyfrowy:',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                if (!_isSigningMode)
                  TextButton.icon(
                    onPressed: _enterSigningMode,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Podpisz'),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.black87),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (!_isSigningMode && _signaturePoints.isEmpty)
              Container(
                key: _signatureKey,
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[50],
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.draw, color: Colors.grey, size: 32),
                      SizedBox(height: 8),
                      Text('Kliknij "Podpisz" aby złożyć podpis',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),

            if (!_isSigningMode && _signaturePoints.isNotEmpty)
              Container(
                key: _signatureKey,
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 2),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.green[50],
                ),
                child: CustomPaint(
                  painter: SignaturePainter(_signaturePoints),
                  size: Size.infinite,
                ),
              ),

            if (_isSigningMode) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                  border: Border.all(color: Colors.orange, width: 2),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.orange, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ekran zablokowany - pisz palcem po polu poniżej',
                        style: TextStyle(
                            color: Colors.orange,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                key: _signatureKey,
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.orange, width: 2),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                  color: Colors.white,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => setState(
                      () => _signaturePoints.add(d.localPosition)),
                  onPanUpdate: (d) => setState(
                      () => _signaturePoints.add(d.localPosition)),
                  onPanEnd: (_) =>
                      setState(() => _signaturePoints.add(Offset.zero)),
                  child: CustomPaint(
                    painter: SignaturePainter(_signaturePoints),
                    size: Size.infinite,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _signaturePoints.clear()),
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Wyczyść'),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.red),
                  ),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => setState(() {
                          _signaturePoints.clear();
                          _isSigningMode = false;
                        }),
                        child: const Text('Anuluj'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _signaturePoints.isEmpty
                            ? null
                            : () {
                                _exitSigningMode();
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                  content: Text('Podpis zapisany ✓'),
                                  backgroundColor: Colors.green,
                                ));
                              },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Zatwierdź'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),

            // V9: Action buttons row
            Row(
              children: [
                // Share PDF
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _generateAndShare,
                    icon: const Icon(Icons.share),
                    label: const Text('Udostępnij PDF'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // V9: Archiwizuj i wyślij
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isArchiving ? null : _archiveAndSend,
                    icon: _isArchiving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(
                        _isArchiving ? 'Wysyłanie...' : 'Archiwizuj i wyślij'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label,
      {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: Colors.black87, width: 2),
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
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != Offset.zero && points[i + 1] != Offset.zero) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
