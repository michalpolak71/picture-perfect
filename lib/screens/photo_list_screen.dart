import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/photo_data.dart';
import 'simple_draw_screen.dart';
import 'pdf_report_screen.dart';

class PhotoListScreen extends StatefulWidget {
  const PhotoListScreen({super.key});

  @override
  State<PhotoListScreen> createState() => _PhotoListScreenState();
}

class _PhotoListScreenState extends State<PhotoListScreen> {
  List<PhotoData> _photos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _deletePhoto(PhotoData photo) async {
    try {
      if (await File(photo.imagePath).exists()) {
        await File(photo.imagePath).delete();
      }

      final metaPath = photo.imagePath.replaceAll('.jpg', '.json');
      if (await File(metaPath).exists()) {
        await File(metaPath).delete();
      }

      await _loadPhotos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zdj\u0119cie usuni\u0119te')),
        );
      }
    } catch (e) {
      print('Error deleting photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('B\u0142\u0105d usuwania: $e')),
        );
      }
    }
  }

  Future<void> _loadPhotos() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${directory.path}/photos');

      if (!await photosDir.exists()) {
        setState(() => _isLoading = false);
        return;
      }

      final files = photosDir.listSync();
      final jsonFiles = files.where((f) => f.path.endsWith('.json')).toList();

      List<PhotoData> photos = [];

      for (var file in jsonFiles) {
        try {
          final content = await File(file.path).readAsString();
          final data = json.decode(content);
          photos.add(PhotoData.fromJson(data));
        } catch (e) {
          print('Error loading photo metadata: $e');
        }
      }

      photos.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _photos = photos;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading photos: $e');
      setState(() => _isLoading = false);
    }
  }

  // Share photos with GPS in description text (no txt file) - for WhatsApp etc.
  Future<void> _sharePhotosWithGps() async {
    if (_photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brak zdj\u0119\u0107 do wys\u0142ania')),
      );
      return;
    }

    try {
      // Build description with GPS for each photo
      String shareText = 'Zdj\u0119cia z dokumentacji Interklima\n\n';
      for (int i = 0; i < _photos.length; i++) {
        final photo = _photos[i];
        final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
        shareText += 'Zdj\u0119cie ${i + 1}:\n';
        shareText += '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}\n';
        if (photo.description.isNotEmpty) {
          shareText += 'Opis: ${photo.description}\n';
        }
        if (photo.hasLocation()) {
          shareText += '\ud83d\udccd Lokalizacja: https://maps.google.com/?q=${photo.latitude},${photo.longitude}\n';
        }
        shareText += '\n';
      }

      // Calculate total size
      int totalSize = 0;
      for (var photo in _photos) {
        if (await File(photo.imagePath).exists()) {
          totalSize += await File(photo.imagePath).length();
        }
      }
      final totalSizeMB = totalSize / (1024 * 1024);

      // If few photos AND small size - share directly (no ZIP, no txt file)
      if (_photos.length <= 3 && totalSizeMB < 15) {
        final files = <XFile>[];
        for (var photo in _photos) {
          if (await File(photo.imagePath).exists()) {
            files.add(XFile(photo.imagePath));
          }
        }

        await Share.shareXFiles(
          files,
          subject: 'Zdj\u0119cia Interklima (${_photos.length})',
          text: shareText,
        );
        return;
      }

      // Otherwise create ZIP with photos only (no txt file inside)
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Tworzenie ZIP...'),
            ],
          ),
        ),
      );

      final directory = await getApplicationDocumentsDirectory();
      final zipPath = '${directory.path}/photos_${DateTime.now().millisecondsSinceEpoch}.zip';

      final encoder = ZipFileEncoder();
      encoder.create(zipPath);

      for (var photo in _photos) {
        if (await File(photo.imagePath).exists()) {
          encoder.addFile(File(photo.imagePath));
        }
      }

      // Add INFO.txt only inside ZIP (not as separate share)
      final infoPath = '${directory.path}/INFO.txt';
      await File(infoPath).writeAsString(shareText);
      encoder.addFile(File(infoPath));
      await File(infoPath).delete();

      encoder.close();

      if (mounted) {
        Navigator.pop(context);

        await Share.shareXFiles(
          [XFile(zipPath)],
          subject: 'Zdj\u0119cia Interklima (${_photos.length} zdj\u0119\u0107, ${totalSizeMB.toStringAsFixed(1)}MB)',
          text: shareText,
        );
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('B\u0142\u0105d: $e')),
        );
      }
    }
  }

  // Share single photo with GPS in text (no txt file)
  Future<void> _shareSinglePhoto(PhotoData photo) async {
    String shareText = '';
    if (photo.description.isNotEmpty) {
      shareText = 'Opis: ${photo.description}\n';
    }
    if (photo.hasLocation()) {
      shareText += '\ud83d\udccd Lokalizacja: https://maps.google.com/?q=${photo.latitude},${photo.longitude}';
    }

    await Share.shareXFiles(
      [XFile(photo.imagePath)],
      subject: 'Zdj\u0119cie Interklima',
      text: shareText.isNotEmpty ? shareText : 'Zdj\u0119cie z dokumentacji',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Zdj\u0119cia (${_photos.length})'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, size: 28),
            tooltip: 'Utw\u00f3rz raport PDF',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PdfReportScreen(photos: _photos),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share, size: 28),
            tooltip: 'Wy\u015blij zdj\u0119cia z GPS',
            onPressed: _sharePhotosWithGps,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? const Center(child: Text('Brak zdj\u0119\u0107'))
              : ListView.builder(
                  itemCount: _photos.length,
                  itemBuilder: (context, index) {
                    final photo = _photos[index];
                    final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);

                    return GestureDetector(
                      onLongPress: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Opcje'),
                            content: const Text('Co chcesz zrobi\u0107?'),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SimpleDrawScreen(imagePath: photo.imagePath),
                                    ),
                                  ).then((_) => _loadPhotos());
                                },
                                child: const Text('Edytuj'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _shareSinglePhoto(photo);
                                },
                                child: const Text('Udost\u0119pnij'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Usu\u0144 zdj\u0119cie'),
                                      content: const Text('Czy na pewno chcesz usun\u0105\u0107 to zdj\u0119cie?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('Anuluj'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('Usu\u0144', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    await _deletePhoto(photo);
                                  }
                                },
                                child: const Text('Usu\u0144', style: TextStyle(color: Colors.red)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Anuluj'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Card(
                        margin: const EdgeInsets.all(8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (File(photo.imagePath).existsSync())
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                child: Image.file(
                                  File(photo.imagePath),
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (photo.hasLocation())
                                        const Icon(Icons.location_on, size: 16, color: Colors.green),
                                    ],
                                  ),
                                  if (photo.description.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      photo.description,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                  if (photo.hasLocation()) ...[
                                    const SizedBox(height: 8),
                                    GestureDetector(
                                      onTap: () async {
                                        final url = Uri.parse(
                                          'https://www.google.com/maps/dir/?api=1&destination=${photo.latitude},${photo.longitude}',
                                        );
                                        if (await canLaunchUrl(url)) {
                                          await launchUrl(url, mode: LaunchMode.externalApplication);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.green[50],
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.green),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.navigation, size: 16, color: Colors.green),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                'GPS: ${photo.latitude!.toStringAsFixed(6)}, ${photo.longitude!.toStringAsFixed(6)}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.green),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    'Przytrzymaj aby edytowa\u0107 lub usun\u0105\u0107',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[500],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
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
