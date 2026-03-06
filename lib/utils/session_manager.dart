import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/photo_session.dart';

class SessionManager {
  static const String _fileName = 'sessions.json';

  static Future<String> get _filePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_fileName';
  }

  static Future<List<PhotoSession>> loadSessions() async {
    try {
      final path = await _filePath;
      final file = File(path);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> jsonList = json.decode(content);
      return jsonList.map((j) => PhotoSession.fromJson(j)).toList();
    } catch (e) {
      print('Error loading sessions: $e');
      return [];
    }
  }

  static Future<void> saveSessions(List<PhotoSession> sessions) async {
    try {
      final path = await _filePath;
      final file = File(path);
      await file.writeAsString(
          json.encode(sessions.map((s) => s.toJson()).toList()));
    } catch (e) {
      print('Error saving sessions: $e');
    }
  }

  static Future<PhotoSession> createSession(String name) async {
    final sessions = await loadSessions();
    final session = PhotoSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      createdTimestamp: DateTime.now().millisecondsSinceEpoch,
      photoIds: [],
    );
    sessions.insert(0, session);
    await saveSessions(sessions);
    return session;
  }

  static Future<void> addPhotoToSession(
      String sessionId, String photoId) async {
    final sessions = await loadSessions();
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index != -1) {
      sessions[index].photoIds.add(photoId);
      await saveSessions(sessions);
    }
  }

  static Future<void> removePhotoFromSession(
      String sessionId, String photoId) async {
    final sessions = await loadSessions();
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index != -1) {
      sessions[index].photoIds.remove(photoId);
      await saveSessions(sessions);
    }
  }

  static Future<void> deleteSession(String sessionId) async {
    final sessions = await loadSessions();
    sessions.removeWhere((s) => s.id == sessionId);
    await saveSessions(sessions);
  }
}
