import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../models/photo_session.dart';
import '../models/photo_data.dart';
import '../utils/session_manager.dart';
import 'pdf_report_screen.dart';
import 'session_photos_screen.dart';
import '../main.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    _sessions = await SessionManager.loadSessions();
    setState(() => _isLoading = false);
  }

  Future<void> _createNewSession() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nowa sesja'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Nazwa sesji (np. "Kowalski - instalacja")',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
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
            child: const Text('Utwórz'),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      final session = await SessionManager.createSession(result.trim());
      if (mounted) {
        // Immediately open camera for new session
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CameraScreen(
              sessionId: session.id,
              sessionName: session.name,
            ),
          ),
        );
        _loadSessions();
      }
    }
  }

  Future<void> _deleteSession(PhotoSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usuń sesję'),
        content: Text(
            'Czy na pewno usunąć "${session.name}"?\n\nZdjęcia pozostaną w pamięci.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Usuń', style: TextStyle(color: Colors.red)),
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
          photos.add(PhotoData.fromJson(json.decode(content)));
        }
      }
      photos.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return photos;
    } catch (e) {
      print('Error loading session photos: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF0066CC),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Image.asset('assets/logo.png', height: 28),
            const SizedBox(width: 12),
            const Text('Sesje',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? _buildEmptyState()
              : _buildSessionList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewSession,
        backgroundColor: const Color(0xFF0066CC),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nowa sesja'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('Brak sesji',
              style: TextStyle(
                  fontSize: 20,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Utwórz nową sesję aby zacząć',
              style: TextStyle(color: Colors.grey[400])),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _createNewSession,
            icon: const Icon(Icons.add),
            label: const Text('Utwórz pierwszą sesję'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0066CC),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _sessions.length,
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final date =
            DateTime.fromMillisecondsSinceEpoch(session.createdTimestamp);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      SessionPhotosScreen(session: session),
                ),
              );
              _loadSessions();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0066CC).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.folder,
                        color: Color(0xFF0066CC), size: 28),
                  ),
                  const SizedBox(width: 14),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.photo,
                                size: 13, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              '${session.photoIds.length} zdjęć',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 12),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.calendar_today,
                                size: 13, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              '${date.day}.${date.month}.${date.year}',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Actions
                  PopupMenuButton(
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'camera',
                        child: Row(children: [
                          Icon(Icons.camera_alt),
                          SizedBox(width: 8),
                          Text('Dodaj zdjęcia'),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'photos',
                        child: Row(children: [
                          Icon(Icons.photo_library),
                          SizedBox(width: 8),
                          Text('Przeglądaj'),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'report',
                        child: Row(children: [
                          Icon(Icons.picture_as_pdf),
                          SizedBox(width: 8),
                          Text('Generuj raport'),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Usuń',
                              style: TextStyle(color: Colors.red)),
                        ]),
                      ),
                    ],
                    onSelected: (value) async {
                      if (value == 'camera') {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CameraScreen(
                              sessionId: session.id,
                              sessionName: session.name,
                            ),
                          ),
                        );
                        _loadSessions();
                      } else if (value == 'photos') {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                SessionPhotosScreen(session: session),
                          ),
                        );
                        _loadSessions();
                      } else if (value == 'report') {
                        final photos =
                            await _loadSessionPhotos(session);
                        if (mounted) {
                          if (photos.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Brak zdjęć w tej sesji')),
                            );
                          } else {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PdfReportScreen(
                                  photos: photos,
                                  sessionName: session.name,
                                ),
                              ),
                            );
                          }
                        }
                      } else if (value == 'delete') {
                        await _deleteSession(session);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
