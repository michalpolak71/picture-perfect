import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:convert';
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
  final _customDocTypeController = TextEditingController();
  final List<Offset> _signaturePoints = [];
  final Set<int> _selectedPhotos = {};
  int _reportNumber = 1;
  bool _isSigningMode = false;
  final GlobalKey _signatureKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  String _selectedDocType = 'Raport';
  final List<String> _docTypes = ['Raport', 'Protokół', 'Inny'];

  @override
  void initState() {
    super.initState();
    _loadReportNumber();
    for (int i = 0; i < widget.photos.length; i++) {
      _selectedPhotos.add(i);
    }
  }

  String get _fullDocType {
    if (_selectedDocType == 'Inny') {
      final custom = _customDocTypeController.text.trim();
      return custom.isEmpty ? 'Inny' : custom;
    }
    return _selectedDocType;
  }

  Future<void> _loadReportNumber() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final counterFile = File('${directory.path}/report_counter.txt');
      if (await counterFile.exists()) {
        final content = await counterFile.readAsString();
        setState(() {
          _reportNumber = int.tryParse(content) ?? 1;
        });
      }
    } catch (e) {
      debugPrint('Error loading report number: $e');
    }
  }

  Future<void> _saveReportNumber() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final counterFile = File('${directory.path}/report_counter.txt');
      await counterFile.writeAsString((_reportNumber + 1).toString());
    } catch (e) {
      debugPrint('Error saving report number: $e');
    }
  }

  String _getReportNumber() {
    final now = DateTime.now();
    final months = [
      'sty', 'lut', 'mar', 'kwi', 'maj', 'cze',
      'lip', 'sie', 'wrz', 'paz', 'lis', 'gru'
    ];
    return 'Nr ${_reportNumber.toString().padLeft(3, '0')}/${now.day}/${months[now.month - 1]}/${now.year}';
  }

  Future<void> _generatePdf() async {
    if (_nameController.text.isEmpty ||
        _projectController.text.isEmpty ||
        _clientController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wypełnij imię/nazwisko, projekt i klienta')),
      );
      return;
    }

    if (_selectedPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wybierz przynajmniej jedno zdjęcie')),
      );
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final pdf = pw.Document();
      final logoData = await rootBundle.load('assets/logo.png');
      final logoBytes = logoData.buffer.asUint8List();
      final logo = pw.MemoryImage(logoBytes);

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
      final selectedPhotosList = _selectedPhotos.toList()..sort();
      final docTitle = _fullDocType.toUpperCase();

      pdf.addPage(
        pw.Page(
          theme: theme,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Image(logo, width: 200),
                pw.SizedBox(height: 40),
                pw.Text(docTitle,
                    style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.SizedBox(height: 20),
                pw.Text(reportNum,
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Text('Projekt: ${_projectController.text}',
                    style: const pw.TextStyle(fontSize: 16)),
                pw.SizedBox(height: 10),
                pw.Text('Klient: ${_clientController.text}',
                    style: const pw.TextStyle(fontSize: 16)),
                pw.SizedBox(height: 10),
                pw.Text(
                    'Data sporządzenia: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
                    style: const pw.TextStyle(fontSize: 16)),
                pw.SizedBox(height: 10),
                pw.Text('Sporządził: ${_nameController.text}',
                    style: const pw.TextStyle(fontSize: 16)),
                pw.SizedBox(height: 10),
                pw.Text('Liczba zdjęć: ${selectedPhotosList.length}',
                    style: const pw.TextStyle(fontSize: 16)),
                pw.Spacer(),
                _buildFooter(),
              ],
            );
          },
        ),
      );

      for (int i = 0; i < selectedPhotosList.length; i++) {
        final photoIndex = selectedPhotosList[i];
        final photo = widget.photos[photoIndex];
        final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);

        final imageFile = File(photo.imagePath);
        final imageBytes = await imageFile.readAsBytes();
        final image = pw.MemoryImage(imageBytes);

        pdf.addPage(
          pw.Page(
            theme: theme,
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Zdjęcie ${i + 1}/${selectedPhotosList.length}',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                          '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                          style: const pw.TextStyle(fontSize: 12)),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Expanded(child: pw.Image(image, fit: pw.BoxFit.contain)),
                  pw.SizedBox(height: 10),
                  if (photo.description.isNotEmpty) ...[
                    pw.Text('Opis:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(photo.description),
                    pw.SizedBox(height: 5),
                  ],
                  if (photo.hasLocation()) ...[
                    pw.Text('Lokalizacja GPS:',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.UrlLink(
                      destination:
                          'https://maps.google.com/?q=${photo.latitude},${photo.longitude}',
                      child: pw.Text(
                        '${photo.latitude!.toStringAsFixed(6)}, ${photo.longitude!.toStringAsFixed(6)}',
                        style: const pw.TextStyle(color: PdfColors.blue),
                      ),
                    ),
                  ],
                  pw.Spacer(),
                  _buildFooter(),
                ],
              );
            },
          ),
        );
      }

      pdf.addPage(
        pw.Page(
          theme: theme,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('PODSUMOWANIE',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 20),
                if (_summaryController.text.isNotEmpty) ...[
                  pw.Text(_summaryController.text),
                  pw.SizedBox(height: 30),
                ],
                pw.Spacer(),
                pw.Text('Podpis sporządzającego:',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                if (signatureImage != null)
                  pw.Container(
                    height: 100,
                    width: 300,
                    decoration: pw.BoxDecoration(border: pw.Border.all()),
                    child: pw.Image(signatureImage, fit: pw.BoxFit.contain),
                  )
                else
                  pw.Container(
                    height: 100,
                    width: 300,
                    decoration: pw.BoxDecoration(border: pw.Border.all()),
                  ),
                pw.SizedBox(height: 10),
                pw.Text('${_nameController.text}'),
                pw.Text(
                    'Data: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}'),
                pw.Spacer(),
                _buildFooter(),
              ],
            );
          },
        ),
      );

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final pdfPath =
          '${directory.path}/raport_${_reportNumber.toString().padLeft(3, "0")}_$timestamp.pdf';
      final file = File(pdfPath);
      await file.writeAsBytes(await pdf.save());

      final metaPath = pdfPath.replaceAll('.pdf', '.json');
      final meta = {
        'reportNumber': reportNum,
        'docType': _fullDocType,
        'project': _projectController.text,
        'client': _clientController.text,
        'author': _nameController.text,
        'photoCount': selectedPhotosList.length,
      };
      await File(metaPath).writeAsString(json.encode(meta));

      await _saveReportNumber();

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd generowania PDF: $e')),
        );
      }
    }
  }

  Future<void> _archiveAndSend() async {
    if (_nameController.text.isEmpty ||
        _projectController.text.isEmpty ||
        _clientController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wypełnij dane przed wysłaniem do chmury')),
      );
      return;
    }

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
      final directory = await getApplicationDocumentsDirectory();
      final allFiles = Directory(directory.path)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pdf'))
          .toList();
      allFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      if (allFiles.isEmpty) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Najpierw wygeneruj PDF (przycisk PDF)')),
        );
        return;
      }

      final pdfFile = allFiles.first;
      final fileName = pdfFile.path.split(Platform.pathSeparator).last;

      final driveService = GoogleDriveService();
      await driveService.initialize();
      final pdfLink = await driveService.uploadPdf(pdfFile, fileName);

      final sheetsService = GoogleSheetsService();
      await sheetsService.initialize();
      await sheetsService.addReportRow(
        date: DateTime.now(),
        reportNumber: _getReportNumber(),
        docType: _fullDocType,
        projectName: _projectController.text,
        clientName: _clientController.text,
        createdBy: _nameController.text,
        photoCount: _selectedPhotos.length,
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

  pw.Widget _buildFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Biuro Warszawa/Babice Nowe:',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          pw.Text('ul. Ogrodnicza 76, 05-082 Babice Nowe',
              style: const pw.TextStyle(fontSize: 8)),
          pw.Text(
              'b.drabicki@interklima.pl  |  kom. Bartłomiej Drabicki 608 651 538',
              style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  Future<pw.MemoryImage> _createSignatureImage() async {
    final RenderBox? renderBox =
        _signatureKey.currentContext?.findRenderObject() as RenderBox?;
    final padWidth = renderBox?.size.width ?? 300.0;
    final padHeight = renderBox?.size.height ?? 200.0;

    const pdfWidth = 300.0;
    const pdfHeight = 100.0;

    final scaleX = pdfWidth / padWidth;
    final scaleY = pdfHeight / padHeight;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, pdfWidth, pdfHeight));

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, pdfWidth, pdfHeight),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    final paint = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < _signaturePoints.length - 1; i++) {
      if (_signaturePoints[i] != Offset.zero &&
          _signaturePoints[i + 1] != Offset.zero) {
        final scaledStart = Offset(
            _signaturePoints[i].dx * scaleX, _signaturePoints[i].dy * scaleY);
        final scaledEnd = Offset(_signaturePoints[i + 1].dx * scaleX,
            _signaturePoints[i + 1].dy * scaleY);
        canvas.drawLine(scaledStart, scaledEnd, paint);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(pdfWidth.toInt(), pdfHeight.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return pw.MemoryImage(byteData!.buffer.asUint8List());
  }

  void _enterSigningMode() {
    setState(() => _isSigningMode = true);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_signatureKey.currentContext != null) {
        Scrollable.ensureVisible(
          _signatureKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
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
    _customDocTypeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nowy dokument'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Wyślij do Drive i Sheets',
            onPressed: _archiveAndSend,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Generuj PDF',
            onPressed: _generatePdf,
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
            Text('Numer: ${_getReportNumber()}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Typ dokumentu
            const Text('Typ dokumentu:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _docTypes.map((type) {
                final selected = _selectedDocType == type;
                return ChoiceChip(
                  label: Text(type),
                  selected: selected,
                  selectedColor: Colors.grey[900],
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.black87,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (_) => setState(() => _selectedDocType = type),
                );
              }).toList(),
            ),
            if (_selectedDocType == 'Inny') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customDocTypeController,
                decoration: InputDecoration(
                  labelText: 'Nazwa własna dokumentu',
                  hintText: 'np. Raport z wizji lokalnej',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.black87, width: 2),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 16),

            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Imię i nazwisko *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.black87, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _projectController,
              decoration: InputDecoration(
                labelText: 'Nazwa projektu *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.black87, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _clientController,
              decoration: InputDecoration(
                labelText: 'Klient *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.black87, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _summaryController,
              decoration: InputDecoration(
                labelText: 'Podsumowanie (opcjonalne)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.black87, width: 2),
                ),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 24),

            const Text('Wybierz zdjęcia:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...List.generate(widget.photos.length, (index) {
              final photo = widget.photos[index];
              final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
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
                subtitle: Text(
                    photo.description.isEmpty ? 'Bez opisu' : photo.description),
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

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Podpis cyfrowy:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (!_isSigningMode)
                  TextButton.icon(
                    onPressed: _enterSigningMode,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Podpisz'),
                    style: TextButton.styleFrom(foregroundColor: Colors.black87),
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
                child: Stack(
                  children: [
                    CustomPaint(
                      painter: SignaturePainter(_signaturePoints),
                      size: Size.infinite,
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Icon(Icons.lock, color: Colors.green[700], size: 20),
                    ),
                  ],
                ),
              ),

            if (_isSigningMode) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    Icon(Icons.info_outline, color: Colors.orange, size: 18),
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
                  onPanStart: (details) =>
                      setState(() => _signaturePoints.add(details.localPosition)),
                  onPanUpdate: (details) =>
                      setState(() => _signaturePoints.add(details.localPosition)),
                  onPanEnd: (details) =>
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
                    onPressed: () => setState(() => _signaturePoints.clear()),
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Wyczyść'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => setState(() {
                          _signaturePoints.clear();
                          _isSigningMode = false;
                        }),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[700],
                          side: BorderSide(color: Colors.grey[400]!),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Anuluj'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _signaturePoints.isEmpty
                            ? null
                            : () {
                                _exitSigningMode();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Row(children: [
                                      Icon(Icons.check_circle,
                                          color: Colors.white),
                                      SizedBox(width: 8),
                                      Text('Podpis zapisany'),
                                    ]),
                                    duration: Duration(seconds: 2),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Zatwierdź'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],

            if (!_isSigningMode && _signaturePoints.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _signaturePoints.clear());
                      _enterSigningMode();
                    },
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Popraw podpis'),
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.grey[700]),
                  ),
                  ElevatedButton.icon(
                    onPressed: _generatePdf,
                    icon: const Icon(Icons.picture_as_pdf, size: 18),
                    label: const Text('Generuj PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[900],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 40),
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
