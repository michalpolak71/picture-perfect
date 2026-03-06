import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../models/photo_session.dart';
import '../models/photo_data.dart';
import '../utils/session_manager.dart';
import 'pdf_report_screen.dart';
import '../main.dart';

class SessionPhotosScreen extends StatefulWidget {
  final PhotoSession session;

  const SessionPhotosScreen({super.key, required this.session});

  @override
  State<SessionPhotosScreen> createState() => _SessionPhotosScreenState();
}

class _SessionPhotosScreenState extends State<SessionPhotosScreen> {
  List<PhotoData> _photos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    setState(() => _isLoading = true);
    try {
      final directory = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${directory.path}/photos');
      if (!await photosDir.exists()) {
        setState(() {
          _photos = [];
          _isLoading = false;
        });
        return;
      }

      final List<PhotoData> photos = [];
      final sessions = await SessionManager.loadSessions();
      final currentSession =
          sessions.firstWhere((s) => s.id == widget.session.id, orElse: () => widget.session);

      for (final photoId in currentSession.photoIds) {
        final metaFile = File('${photosDir.path}/photo_$photoId.json');
        if (await metaFile.exists()) {
          final content = await metaFile.readAsString();
          photos.add(PhotoData.fromJson(json.decode(content)));
        }
      }
      photos.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      setState(() {
        _photos = photos;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading photos: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePhoto(PhotoData photo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usuń zdjęcie'),
        content: const Text('Czy na pewno usunąć to zdjęcie?'),
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
      try {
        final photoIdStr = photo.timestamp.toString();
        await SessionManager.removePhotoFromSession(
            widget.session.id, photoIdStr);
        final directory = await getApplicationDocumentsDirectory();
        final photosDir = Directory('${directory.path}/photos');
        final imgFile = File('${photosDir.path}/photo_$photoIdStr.jpg');
        final metaFile = File('${photosDir.path}/photo_$photoIdStr.json');
        if (await imgFile.exists()) await imgFile.delete();
        if (await metaFile.exists()) await metaFile.delete();
        _loadPhotos();
      } catch (e) {
        print('Error deleting photo: $e');
      }
    }
  }

  Future<void> _editDescription(PhotoData photo) async {
    final ctrl = TextEditingController(text: photo.description);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edytuj opis'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Opis zdjęcia',
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0066CC),
              foregroundColor: Colors.white,
            ),
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final directory = await getApplicationDocumentsDirectory();
        final photosDir = Directory('${directory.path}/photos');
        final metaFile =
            File('${photosDir.path}/photo_${photo.timestamp}.json');
        final updated = PhotoData(
          imagePath: photo.imagePath,
          description: result,
          timestamp: photo.timestamp,
          latitude: photo.latitude,
          longitude: photo.longitude,
          sessionId: photo.sessionId,
          altitude: photo.altitude,
        );
        await metaFile.writeAsString(json.encode(updated.toJson()));
        _loadPhotos();
      } catch (e) {
        print('Error updating description: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0066CC),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.session.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('${_photos.length} zdjęć',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          // Add photos button
          IconButton(
            icon: const Icon(Icons.camera_alt),
            tooltip: 'Dodaj zdjęcia',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CameraScreen(
                    sessionId: widget.session.id,
                    sessionName: widget.session.name,
                  ),
                ),
              );
              _loadPhotos();
            },
          ),
          // Generate report
          if (_photos.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Generuj raport PDF',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PdfReportScreen(
                      photos: _photos,
                      sessionName: widget.session.name,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? _buildEmptyState()
              : _buildPhotoGrid(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CameraScreen(
                sessionId: widget.session.id,
                sessionName: widget.session.name,
              ),
            ),
          );
          _loadPhotos();
        },
        backgroundColor: const Color(0xFF0066CC),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.camera_alt),
        label: const Text('Dodaj zdjęcie'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_camera, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('Brak zdjęć',
              style: TextStyle(
                  fontSize: 20,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Użyj aparatu aby dodać zdjęcia',
              style: TextStyle(color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildPhotoGrid() {
    return Column(
      children: [
        // Report button bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.blue[50],
          child: ElevatedButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PdfReportScreen(
                    photos: _photos,
                    sessionName: widget.session.name,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: Text('Generuj raport PDF (${_photos.length} zdjęć)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0066CC),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ),

        // Photo grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemCount: _photos.length,
            itemBuilder: (context, index) {
              final photo = _photos[index];
              final date =
                  DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
              return Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 2,
                child: InkWell(
                  onTap: () => _showPhotoDetail(photo),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              File(photo.imagePath),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey[200],
                                child: const Icon(Icons.broken_image,
                                    color: Colors.grey),
                              ),
                            ),
                            // GPS badge
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: photo.hasLocation()
                                      ? Colors.green.withValues(alpha: 0.85)
                                      : Colors.red.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  photo.hasLocation() ? 'GPS' : 'brak GPS',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 9),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Info
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              photo.description.isEmpty
                                  ? 'Brak opisu'
                                  : photo.description,
                              style: TextStyle(
                                fontSize: 11,
                                color: photo.description.isEmpty
                                    ? Colors.grey
                                    : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} ${date.day}.${date.month}',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey[500]),
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
        ),
      ],
    );
  }

  void _showPhotoDetail(PhotoData photo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.file(
                        File(photo.imagePath),
                        width: double.infinity,
                        height: 280,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 280,
                          color: Colors.grey[200],
                          child: const Icon(Icons.broken_image, size: 60),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Description
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    photo.description.isEmpty
                                        ? 'Brak opisu'
                                        : photo.description,
                                    style: const TextStyle(fontSize: 15),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Color(0xFF0066CC)),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _editDescription(photo);
                                  },
                                ),
                              ],
                            ),
                            const Divider(),

                            // GPS
                            if (photo.hasLocation()) ...[
                              Row(
                                children: [
                                  const Icon(Icons.location_on,
                                      color: Colors.green, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${photo.latitude!.toStringAsFixed(6)}, ${photo.longitude!.toStringAsFixed(6)}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.green),
                                  ),
                                ],
                              ),
                              if (photo.altitude != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 26, top: 4),
                                  child: Text(
                                    'Wysokość: ${photo.altitude!.toStringAsFixed(1)}m n.p.m.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600]),
                                  ),
                                ),
                              const Divider(),
                            ],

                            // Actions
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _deletePhoto(photo);
                                    },
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    label: const Text('Usuń',
                                        style:
                                            TextStyle(color: Colors.red)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
