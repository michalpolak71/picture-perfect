import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PhotoListScreen extends StatefulWidget {
  const PhotoListScreen({super.key});

  @override
  State<PhotoListScreen> createState() => _PhotoListScreenState();
}

class _PhotoListScreenState extends State<PhotoListScreen> {
  List<PhotoData> _photos = [];

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
        return;
      }

      final files = photosDir.listSync();
      final photoFiles = files.where((f) => f.path.endsWith('.jpg')).toList();

      List<PhotoData> photos = [];
      
      for (var file in photoFiles) {
        final timestamp = file.path.split('_').last.split('.').first;
        final descFile = File('${photosDir.path}/photo_$timestamp.txt');
        
        String description = '';
        if (await descFile.exists()) {
          description = await descFile.readAsString();
        }

        photos.add(PhotoData(
          imagePath: file.path,
          description: description,
          timestamp: int.parse(timestamp),
        ));
      }

      photos.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _photos = photos;
      });
    } catch (e) {
      print('Error loading photos: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zdjęcia'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _photos.isEmpty
          ? const Center(
              child: Text('Brak zdjęć'),
            )
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
                      Image.file(
                        File(photo.imagePath),
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            if (photo.description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                photo.description,
                                style: const TextStyle(fontSize: 14),
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

class PhotoData {
  final String imagePath;
  final String description;
  final int timestamp;

  PhotoData({
    required this.imagePath,
    required this.description,
    required this.timestamp,
  });
}
