import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../models/photo_session.dart';

class SessionManager {
  static Future<List<PhotoSession>> loadSessions() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final sessionsFile = File('${directory.path}/sessions.json');
      
      if (await sessionsFile.exists()) {
        final content = await sessionsFile.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        return jsonList.map((j) => PhotoSession.fromJson(j)).toList();
      }
    } catch (e) {
      print('Error loading sessions: $e');
    }
    return [];
  }

  static Future<void> saveSessions(List<PhotoSession> sessions) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final sessionsFile = File('${directory.path}/sessions.json');
      final jsonList = sessions.map((s) => s.toJson()).toList();
      await sessionsFile.writeAsString(json.encode(jsonList));
    } catch (e) {
      print('Error saving sessions: $e');
    }
  }

  static Future<PhotoSession> createSession(String name) async {
    final session = PhotoSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      createdTimestamp: DateTime.now().millisecondsSinceEpoch,
      photoIds: [],
    );
    
    final sessions = await loadSessions();
    sessions.add(session);
    await saveSessions(sessions);
    
    return session;
  }

  static Future<void> addPhotoToSession(String sessionId, String photoId) async {
    final sessions = await loadSessions();
    final session = sessions.firstWhere((s) => s.id == sessionId);
    if (!session.photoIds.contains(photoId)) {
      session.photoIds.add(photoId);
      await saveSessions(sessions);
    }
  }

  static Future<void> deleteSession(String sessionId) async {
    final sessions = await loadSessions();
    sessions.removeWhere((s) => s.id == sessionId);
    await saveSessions(sessions);
  }
}
