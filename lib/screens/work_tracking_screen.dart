import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class WorkTrackingScreen extends StatefulWidget {
  const WorkTrackingScreen({super.key});

  @override
  State<WorkTrackingScreen> createState() => _WorkTrackingScreenState();
}

class _WorkTrackingScreenState extends State<WorkTrackingScreen> {
  bool _isWorking = false;
  bool _isSending = false;
  String? _startTime;
  String? _startDate;
  Position? _currentPosition;
  String _statusMessage = '';
  String _phoneNumber = '';

  // Google Apps Script webhook URL
  static const String _webhookUrl =
      'https://script.google.com/macros/s/AKfycby_yYzQhfdCU3dVB9EhR4HaJQ4KeyntdP_p3VrXmZ4XLUmLiXBKPeApQ5OxHk-v0i3N/exec';

  @override
  void initState() {
    super.initState();
    _loadState();
    _loadPhoneNumber();
  }

  Future<void> _loadPhoneNumber() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/phone_number.txt');
      if (await file.exists()) {
        final phone = await file.readAsString();
        setState(() => _phoneNumber = phone.trim());
      }
    } catch (e) {
      print('Error loading phone: $e');
    }
  }

  Future<void> _savePhoneNumber(String phone) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/phone_number.txt');
      await file.writeAsString(phone);
      setState(() => _phoneNumber = phone);
    } catch (e) {
      print('Error saving phone: $e');
    }
  }

  Future<void> _loadState() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/work_state.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = json.decode(content);
        setState(() {
          _isWorking = data['isWorking'] ?? false;
          _startTime = data['startTime'];
          _startDate = data['startDate'];
        });
      }
    } catch (e) {
      print('Error loading work state: $e');
    }
  }

  Future<void> _saveState() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/work_state.json');
      await file.writeAsString(json.encode({
        'isWorking': _isWorking,
        'startTime': _startTime,
        'startDate': _startDate,
      }));
    } catch (e) {
      print('Error saving work state: $e');
    }
  }

  Future<Position?> _getLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _statusMessage = 'W\u0142\u0105cz GPS!');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _statusMessage = 'Brak uprawnie\u0144 GPS');
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      setState(() => _statusMessage = 'B\u0142\u0105d GPS: $e');
      return null;
    }
  }

  Future<void> _sendToGoogleSheets(String type) async {
    if (_phoneNumber.isEmpty) {
      _showPhoneDialog();
      return;
    }

    setState(() {
      _isSending = true;
      _statusMessage = 'Wysy\u0142anie...';
    });

    // Get GPS
    final position = await _getLocation();
    if (position == null) {
      setState(() {
        _isSending = false;
        _statusMessage = 'Nie mo\u017cna pobra\u0107 GPS. Spr\u00f3buj ponownie.';
      });
      return;
    }

    final now = DateTime.now();
    final date = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final payload = {
      'date': date,
      'time': time,
      'phone': _phoneNumber,
      'type': type,
      'lat': position.latitude.toStringAsFixed(6),
      'lon': position.longitude.toStringAsFixed(6),
    };

    try {
      final response = await http.post(
        Uri.parse(_webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 302) {
        setState(() {
          if (type == 'START') {
            _isWorking = true;
            _startTime = time;
            _startDate = date;
            _statusMessage = '\u2705 START zarejestrowany o $time';
          } else {
            _isWorking = false;
            _statusMessage = '\u2705 STOP zarejestrowany o $time';
            _startTime = null;
            _startDate = null;
          }
          _isSending = false;
        });
        await _saveState();
      } else {
        setState(() {
          _isSending = false;
          _statusMessage = '\u274c B\u0142\u0105d serwera. Spr\u00f3buj ponownie.';
        });
      }
    } catch (e) {
      // Save locally for later sync
      await _saveOfflineLog(payload);
      setState(() {
        _isSending = false;
        if (type == 'START') {
          _isWorking = true;
          _startTime = time;
          _startDate = date;
          _statusMessage = '\u26a0\ufe0f Zapisano lokalnie (brak internetu). Wy\u015ble si\u0119 p\u00f3\u017aniej.';
        } else {
          _isWorking = false;
          _startTime = null;
          _startDate = null;
          _statusMessage = '\u26a0\ufe0f Zapisano lokalnie (brak internetu). Wy\u015ble si\u0119 p\u00f3\u017aniej.';
        }
      });
      await _saveState();
    }
  }

  Future<void> _saveOfflineLog(Map<String, dynamic> payload) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/offline_logs.json');
      List<dynamic> logs = [];
      if (await file.exists()) {
        final content = await file.readAsString();
        logs = json.decode(content);
      }
      logs.add(payload);
      await file.writeAsString(json.encode(logs));
    } catch (e) {
      print('Error saving offline log: $e');
    }
  }

  Future<void> _syncOfflineLogs() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/offline_logs.json');
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final List<dynamic> logs = json.decode(content);
      if (logs.isEmpty) return;

      setState(() => _statusMessage = 'Synchronizacja ${logs.length} wpis\u00f3w...');

      List<dynamic> failedLogs = [];
      for (var log in logs) {
        try {
          await http.post(
            Uri.parse(_webhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(log),
          );
        } catch (e) {
          failedLogs.add(log);
        }
      }

      await file.writeAsString(json.encode(failedLogs));
      if (failedLogs.isEmpty) {
        setState(() => _statusMessage = '\u2705 Wszystkie dane zsynchronizowane!');
      } else {
        setState(() => _statusMessage = '\u26a0\ufe0f ${failedLogs.length} wpis\u00f3w nie uda\u0142o si\u0119 wys\u0142a\u0107');
      }
    } catch (e) {
      print('Error syncing: $e');
    }
  }

  void _showPhoneDialog() {
    final controller = TextEditingController(text: _phoneNumber);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Tw\u00f3j numer telefonu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Wpisz numer telefonu (9 cyfr, bez +48).\nNumer musi by\u0107 taki sam jak w arkuszu pracownik\u00f3w.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              maxLength: 9,
              decoration: InputDecoration(
                hintText: '795561356',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.phone),
              ),
              style: const TextStyle(fontSize: 20, letterSpacing: 2),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          ElevatedButton(
            onPressed: () {
              final phone = controller.text.trim();
              if (phone.length == 9 && int.tryParse(phone) != null) {
                _savePhoneNumber(phone);
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Wpisz poprawny 9-cyfrowy numer')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[900],
              foregroundColor: Colors.white,
            ),
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ewidencja pracy'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.phone, size: 24),
            tooltip: 'Zmie\u0144 numer telefonu',
            onPressed: _showPhoneDialog,
          ),
          IconButton(
            icon: const Icon(Icons.sync, size: 24),
            tooltip: 'Synchronizuj dane offline',
            onPressed: _syncOfflineLogs,
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Phone number display
            if (_phoneNumber.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      'Tel: $_phoneNumber',
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // Current status
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _isWorking ? Colors.green[50] : Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isWorking ? Colors.green : Colors.grey[300]!,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _isWorking ? Icons.work : Icons.work_off,
                    size: 48,
                    color: _isWorking ? Colors.green[700] : Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isWorking ? 'W PRACY' : 'NIE W PRACY',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _isWorking ? Colors.green[700] : Colors.grey[600],
                    ),
                  ),
                  if (_isWorking && _startTime != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Od: $_startTime  |  $_startDate',
                      style: TextStyle(fontSize: 16, color: Colors.green[600]),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 40),

            // START / STOP buttons
            if (!_isWorking)
              SizedBox(
                width: double.infinity,
                height: 80,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : () => _sendToGoogleSheets('START'),
                  icon: _isSending
                      ? const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                        )
                      : const Icon(Icons.play_arrow, size: 36),
                  label: Text(
                    _isSending ? 'Wysy\u0142anie...' : 'START PRACY',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                  ),
                ),
              ),

            if (_isWorking)
              SizedBox(
                width: double.infinity,
                height: 80,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : () => _sendToGoogleSheets('STOP'),
                  icon: _isSending
                      ? const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                        )
                      : const Icon(Icons.stop, size: 36),
                  label: Text(
                    _isSending ? 'Wysy\u0142anie...' : 'KONIEC PRACY',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Status message
            if (_statusMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),

            const Spacer(),

            // Info
            Text(
              'GPS + czas + numer telefonu wysy\u0142ane automatycznie\ndo arkusza Google Sheets',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
