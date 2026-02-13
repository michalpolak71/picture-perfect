import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/photo_data.dart';
import 'simple_draw_screen.dart';

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
      // Delete image file
      if (await File(photo.imagePath).exists()) {
        await File(photo.imagePath).delete();
      }
      
      // Delete metadata file
      final metaPath = photo.imagePath.replaceAll('.jpg', '.json');
      if (await File(metaPath).exists()) {
        await File(metaPath).delete();
      }
      
      // Reload photos
      await _loadPhotos();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zdjęcie usunięte')),
        );
      }
    } catch (e) {
      print('Error deleting photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd usuwania: $e')),
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

  Future<void> _createZipAndShare() async {
    if (_photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brak zdjęć do spakowania')),
      );
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final directory = await getApplicationDocumentsDirectory();
      final zipPath = '${directory.path}/photos_${DateTime.now().millisecondsSinceEpoch}.zip';
      
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);

      for (var photo in _photos) {
        if (await File(photo.imagePath).exists()) {
          encoder.addFile(File(photo.imagePath));
          
          // Add metadata as text file
          final timestamp = photo.timestamp;
          final metaPath = '${directory.path}/temp_meta_$timestamp.txt';
          final metaContent = '''
Opis: ${photo.description}
Data: ${DateTime.fromMillisecondsSinceEpoch(timestamp)}
${photo.hasLocation() ? 'GPS: ${photo.latitude}, ${photo.longitude}' : 'Brak lokalizacji GPS'}
''';
          await File(metaPath).writeAsString(metaContent);
          encoder.addFile(File(metaPath));
          await File(metaPath).delete();
        }
      }

      encoder.close();

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        
        await Share.shareXFiles(
          [XFile(zipPath)],
          subject: 'Zdjęcia Interklima',
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd tworzenia ZIP: $e')),
        );
      }
    }
  }

  Future<void> _sendEmail() async {
    if (_photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brak zdjęć do wysłania')),
      );
      return;
    }

    try {
      // Calculate total size
      int totalSize = 0;
      for (var photo in _photos) {
        if (await File(photo.imagePath).exists()) {
          totalSize += await File(photo.imagePath).length();
        }
      }

      final totalSizeMB = totalSize / (1024 * 1024);

      // If few photos AND small size - share directly
      if (_photos.length <= 3 && totalSizeMB < 15) {
        final files = <XFile>[];
        for (var photo in _photos) {
          if (await File(photo.imagePath).exists()) {
            files.add(XFile(photo.imagePath));
          }
        }
        
        await Share.shareXFiles(
          files,
          subject: 'Zdjęcia Interklima (${_photos.length})',
          text: 'Zdjęcia z dokumentacji',
        );
        return;
      }

      // Otherwise create ZIP
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

      encoder.close();

      if (mounted) {
        Navigator.pop(context); // Close loading
        
        await Share.shareXFiles(
          [XFile(zipPath)],
          subject: 'Zdjęcia Interklima (${_photos.length} zdjęć, ${totalSizeMB.toStringAsFixed(1)}MB)',
          text: 'Zdjęcia z dokumentacji - spakowane w ZIP',
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Zdjęcia (${_photos.length})'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _sendEmail,
              borderRadius: BorderRadius.circular(24),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(Icons.mail, size: 32, color: Colors.white),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _createZipAndShare,
              borderRadius: BorderRadius.circular(24),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Icon(Icons.folder_zip, size: 32, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? const Center(child: Text('Brak zdjęć'))
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
                            content: const Text('Co chcesz zrobić?'),
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
                                onPressed: () async {
                                  Navigator.pop(context);
                                  // Share single photo
                                  await Share.shareXFiles(
                                    [XFile(photo.imagePath)],
                                    subject: 'Zdjęcie Interklima',
                                    text: photo.description.isNotEmpty ? photo.description : 'Zdjęcie z dokumentacji',
                                  );
                                },
                                child: const Text('Udostępnij'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Usuń zdjęcie'),
                                      content: const Text('Czy na pewno chcesz usunąć to zdjęcie?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('Anuluj'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('Usuń', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  );
                                  
                                  if (confirm == true) {
                                    await _deletePhoto(photo);
                                  }
                                },
                                child: const Text('Usuń', style: TextStyle(color: Colors.red)),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (File(photo.imagePath).existsSync())
                              Image.file(
                                File(photo.imagePath),
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.cover,
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
                                          borderRadius: BorderRadius.circular(4),
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
                                    'Przytrzymaj aby edytować lub usunąć',
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
