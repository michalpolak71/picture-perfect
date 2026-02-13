import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import '../models/photo_data.dart';

class PdfReportScreen extends StatefulWidget {
  final List<PhotoData> photos;

  const PdfReportScreen({super.key, required this.photos});

  @override
  State<PdfReportScreen> createState() => _PdfReportScreenState();
}

class _PdfReportScreenState extends State<PdfReportScreen> {
  final _projectController = TextEditingController();
  final _clientController = TextEditingController();
  final _summaryController = TextEditingController();
  final List<Offset> _signaturePoints = [];
  bool _isSigning = false;

  @override
  void dispose() {
    _projectController.dispose();
    _clientController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  Future<void> _generatePdf() async {
    if (_projectController.text.isEmpty || _clientController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wypełnij nazwę projektu i klienta')),
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
      
      // Load logo
      final logoData = await rootBundle.load('assets/logo.png');
      final logoBytes = logoData.buffer.asUint8List();
      final logo = pw.MemoryImage(logoBytes);

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
                pw.Text('Projekt: ${_projectController.text}', style: const pw.TextStyle(fontSize: 16)),
                pw.SizedBox(height: 10),
                pw.Text('Klient: ${_clientController.text}', style: const pw.TextStyle(fontSize: 16)),
                pw.SizedBox(height: 10),
                pw.Text('Data sporządzenia: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
                    style: const pw.TextStyle(fontSize: 16)),
                pw.SizedBox(height: 10),
                pw.Text('Liczba zdjęć: ${widget.photos.length}', style: const pw.TextStyle(fontSize: 16)),
              ],
            );
          },
        ),
      );

      // Photo pages
      for (int i = 0; i < widget.photos.length; i++) {
        final photo = widget.photos[i];
        final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
        
        // Load photo
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
                      pw.Text('Zdjęcie ${i + 1}/${widget.photos.length}',
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
                ],
              );
            },
          ),
        );
      }

      // Summary page with signature
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
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Text('Podpis sporządzającego:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                if (_signaturePoints.isNotEmpty)
                  pw.Container(
                    height: 100,
                    decoration: pw.BoxDecoration(border: pw.Border.all()),
                    child: pw.CustomPaint(
                      painter: (canvas, size) {
                        // Draw signature
                        for (int i = 0; i < _signaturePoints.length - 1; i++) {
                          if (_signaturePoints[i] != Offset.zero && _signaturePoints[i + 1] != Offset.zero) {
                            canvas.drawLine(
                              _signaturePoints[i].dx,
                              _signaturePoints[i].dy,
                              _signaturePoints[i + 1].dx,
                              _signaturePoints[i + 1].dy,
                            );
                          }
                        }
                      },
                    ),
                  ),
                pw.SizedBox(height: 10),
                pw.Text('Data: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}'),
              ],
            );
          },
        ),
      );

      // Save PDF
      final directory = await getApplicationDocumentsDirectory();
      final pdfPath = '${directory.path}/raport_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(pdfPath);
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        Navigator.pop(context); // Close loading
        Navigator.pop(context); // Close form

        // Share PDF
        await Share.shareXFiles(
          [XFile(pdfPath)],
          subject: 'Raport Interklima - ${_projectController.text}',
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
            const Text(
              'Podpis (rysuj palcem):',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onPanStart: (details) {
                setState(() {
                  _isSigning = true;
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
                  _isSigning = false;
                  _signaturePoints.add(Offset.zero); // Separator
                });
              },
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  color: Colors.grey[100],
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
      ..strokeWidth = 3.0
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
