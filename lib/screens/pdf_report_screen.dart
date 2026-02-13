import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import '../models/photo_data.dart';

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

  @override
  void initState() {
    super.initState();
    _loadReportNumber();
    // Select all photos by default
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
        setState(() {
          _reportNumber = int.tryParse(content) ?? 1;
        });
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
    final months = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];
    return 'Nr ${_reportNumber.toString().padLeft(3, '0')}/${now.day}/${months[now.month - 1]}/${now.year}';
  }

  Future<void> _generatePdf() async {
    if (_nameController.text.isEmpty || _projectController.text.isEmpty || _clientController.text.isEmpty) {
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

      // Create signature image if exists
      pw.MemoryImage? signatureImage;
      if (_signaturePoints.isNotEmpty) {
        signatureImage = await _createSignatureImage();
      }

      final reportNum = _getReportNumber();
      final selectedPhotosList = _selectedPhotos.toList()..sort();

      // Title page
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Image(logo, width: 200),
                pw.SizedBox(height: 40),
                pw.Text(
                  'RAPORT Z DOKUMENTACJI',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.SizedBox(height: 20),
                pw.Text(reportNum, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Text('Projekt: ${_projectController.text}', style: const pw.TextStyle(fontSize: 16)),
                pw.SizedBox(height: 10),
                pw.Text('Klient: ${_clientController.text}', style: const pw.TextStyle(fontSize: 16)),
                pw.SizedBox(height: 10),
                pw.Text('Data sporządzenia: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
                    style: const pw.TextStyle(fontSize: 16)),
                pw.SizedBox(height: 10),
                pw.Text('Sporządził: ${_nameController.text}', style: const pw.TextStyle(fontSize: 16)),
                pw.SizedBox(height: 10),
                pw.Text('Liczba zdjęć: ${selectedPhotosList.length}', style: const pw.TextStyle(fontSize: 16)),
                pw.Spacer(),
                _buildFooter(),
              ],
            );
          },
        ),
      );

      // Photo pages
      for (int i = 0; i < selectedPhotosList.length; i++) {
        final photoIndex = selectedPhotosList[i];
        final photo = widget.photos[photoIndex];
        final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
        
        final imageFile = File(photo.imagePath);
        final imageBytes = await imageFile.readAsBytes();
        final image = pw.MemoryImage(imageBytes);

        pdf.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Zdjęcie ${i + 1}/${selectedPhotosList.length}',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.Text('${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                          style: const pw.TextStyle(fontSize: 12)),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Expanded(
                    child: pw.Image(image, fit: pw.BoxFit.contain),
                  ),
                  pw.SizedBox(height: 10),
                  if (photo.description.isNotEmpty) ...[
                    pw.Text('Opis:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(photo.description),
                    pw.SizedBox(height: 5),
                  ],
                  if (photo.hasLocation()) ...[
                    pw.Text('Lokalizacja GPS:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.UrlLink(
                      destination: 'https://maps.google.com/?q=${photo.latitude},${photo.longitude}',
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

      // Summary page
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('PODSUMOWANIE', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 20),
                if (_summaryController.text.isNotEmpty) ...[
                  pw.Text(_summaryController.text),
                  pw.SizedBox(height: 30),
                ],
                pw.Spacer(),
                pw.Text('Podpis sporządzającego:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
                pw.Text('Data: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}'),
                pw.Spacer(),
                _buildFooter(),
              ],
            );
          },
        ),
      );

      final directory = await getApplicationDocumentsDirectory();
      final pdfPath = '${directory.path}/raport_${_reportNumber.toString().padLeft(3, '0')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(pdfPath);
      await file.writeAsBytes(await pdf.save());

      await _saveReportNumber();

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);

        await Share.shareXFiles(
          [XFile(pdfPath)],
          subject: 'Raport Interklima $reportNum - ${_projectController.text}',
        );
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

  pw.Widget _buildFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Biuro Warszawa/Babice Nowe:', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('ul. Ogrodnicza 76', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('05-082 Babice Nowe', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('b.drabicki@interklima.pl', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('kom. Bartłomiej Drabicki', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('608 651 538', style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Biuro Ostrołęka:', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('ul. Miła 17', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('07-410 Ostrołęka', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('biuro@interklima.pl', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('kom. Zbigniew Drabicki', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('602 121 765', style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ],
      ),
    );
  }

  Future<pw.MemoryImage> _createSignatureImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 300, 100));
    
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 300, 100),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    final paint = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < _signaturePoints.length - 1; i++) {
      if (_signaturePoints[i] != Offset.zero && _signaturePoints[i + 1] != Offset.zero) {
        canvas.drawLine(_signaturePoints[i], _signaturePoints[i + 1], paint);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(300, 100);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return pw.MemoryImage(byteData!.buffer.asUint8List());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _projectController.dispose();
    _clientController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raport PDF'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _generatePdf,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Numer raportu: ${_getReportNumber()}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Imię i nazwisko *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _projectController,
              decoration: const InputDecoration(
                labelText: 'Nazwa projektu *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _clientController,
              decoration: const InputDecoration(
                labelText: 'Klient *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _summaryController,
              decoration: const InputDecoration(
                labelText: 'Podsumowanie (opcjonalne)',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 24),
            const Text('Wybierz zdjęcia:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...List.generate(widget.photos.length, (index) {
              final photo = widget.photos[index];
              final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
              return CheckboxListTile(
                value: _selectedPhotos.contains(index),
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
                      _selectedPhotos.add(index);
                    } else {
                      _selectedPhotos.remove(index);
                    }
                  });
                },
                title: Text('${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}'),
                subtitle: Text(photo.description.isEmpty ? 'Bez opisu' : photo.description),
                secondary: File(photo.imagePath).existsSync()
                    ? Image.file(File(photo.imagePath), width: 60, height: 60, fit: BoxFit.cover)
                    : null,
              );
            }),
            const SizedBox(height: 24),
            const Text('Podpis (rysuj palcem):', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            GestureDetector(
              onPanStart: (details) {
                setState(() {
                  _signaturePoints.add(details.localPosition);
                });
              },
              onPanUpdate: (details) {
                setState(() {
                  _signaturePoints.add(details.localPosition);
                });
              },
              onPanEnd: (details) {
                setState(() {
                  _signaturePoints.add(Offset.zero);
                });
              },
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  color: Colors.white,
                ),
                child: CustomPaint(
                  painter: SignaturePainter(_signaturePoints),
                  size: Size.infinite,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _signaturePoints.clear();
                    });
                  },
                  icon: const Icon(Icons.clear),
                  label: const Text('Wyczyść podpis'),
                ),
                ElevatedButton.icon(
                  onPressed: _generatePdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Generuj PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
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
      ..strokeWidth = 2.0
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
