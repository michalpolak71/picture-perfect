import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../models/photo_session.dart';
import '../models/photo_data.dart';
import '../utils/session_manager.dart';
import 'pdf_report_screen.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List<PhotoSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    _sessions = await SessionManager.loadSessions();
    setState(() => _isLoading = false);
  }

  Future<void> _createNewSession() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nowa sesja'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nazwa sesji (np. "Naprawa Kowalskiego")',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Utwórz'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await SessionManager.createSession(result);
      _loadSessions();
    }
  }

  Future<void> _deleteSession(PhotoSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usuń sesję'),
        content: Text('Czy na pewno usunąć "${session.name}"?\n\nZdjęcia pozostaną w galerii.'),
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
      await SessionManager.deleteSession(session.id);
      _loadSessions();
    }
  }

  Future<List<PhotoData>> _loadSessionPhotos(PhotoSession session) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${directory.path}/photos');
      
      if (!await photosDir.exists()) return [];

      final List<PhotoData> photos = [];
      
      for (final photoId in session.photoIds) {
        final metaFile = File('${photosDir.path}/photo_$photoId.json');
        if (await metaFile.exists()) {
          final content = await metaFile.readAsString();
          final photo = PhotoData.fromJson(json.decode(content));
          photos.add(photo);
        }
      }
      
      return photos;
    } catch (e) {
      print('Error loading session photos: $e');
      return [];
    }
  }

  void _openSessionPhotos(PhotoSession session) async {
    final photos = await _loadSessionPhotos(session);
    
    if (!mounted) return;
    
    if (photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brak zdjęć w tej sesji')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfReportScreen(photos: photos),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sesje zdjęciowe'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _sessions.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.photo_library, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Brak sesji', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 8),
                  const Text('Utwórz nową sesję aby rozpocząć', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                final date = DateTime.fromMillisecondsSinceEpoch(session.createdTimestamp);
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.folder),
                    ),
                    title: Text(session.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '${session.photoIds.length} zdjęć • ${date.day}.${date.month}.${date.year}',
                    ),
                    trailing: PopupMenuButton(
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'open',
                          child: Row(
                            children: [
                              Icon(Icons.picture_as_pdf),
                              SizedBox(width: 8),
                              Text('Utwórz raport'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Usuń', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'open') {
                          _openSessionPhotos(session);
                        } else if (value == 'delete') {
                          _deleteSession(session);
                        }
                      },
                    ),
                    onTap: () => _openSessionPhotos(session),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewSession,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
