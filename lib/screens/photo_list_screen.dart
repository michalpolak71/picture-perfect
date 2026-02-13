import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/photo_data.dart';

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
    final email = Uri.encodeComponent('');
    final subject = Uri.encodeComponent('Zdjęcia Interklima');
    final body = Uri.encodeComponent('Witam,\n\nPrzesyłam zdjęcia z dokumentacji.\n\nPozdrawiam');
    
    final Uri emailUri = Uri.parse('mailto:?subject=$subject&body=$body');
    
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nie można otworzyć aplikacji email')),
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
          IconButton(
            icon: const Icon(Icons.mail),
            onPressed: _sendEmail,
            tooltip: 'Email',
          ),
          IconButton(
            icon: const Icon(Icons.folder_zip),
            onPressed: _createZipAndShare,
            tooltip: 'Utwórz ZIP',
          ),
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
                    
                    return Card(
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
                                  Text(
                                    'GPS: ${photo.latitude!.toStringAsFixed(6)}, ${photo.longitude!.toStringAsFixed(6)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
