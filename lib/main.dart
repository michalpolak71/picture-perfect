import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'screens/photo_list_screen.dart';
import 'screens/map_screen.dart';
import 'models/photo_data.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    cameras = await availableCameras();
  } catch (e) {
    print('Error: $e');
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Picture Perfect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  bool _permissionGranted = false;
  bool _isInitialized = false;
  bool _gpsEnabled = true;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final locationStatus = await Permission.location.request();
    
    if (cameraStatus.isGranted) {
      setState(() {
        _permissionGranted = true;
      });
      _initializeCamera();
      
      if (locationStatus.isGranted) {
        _getCurrentLocation();
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _gpsEnabled = false);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      setState(() {
        _currentPosition = position;
        _gpsEnabled = true;
      });
    } catch (e) {
      print('Error getting location: $e');
      setState(() => _gpsEnabled = false);
    }
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) return;

    controller = CameraController(
      cameras[0],
      ResolutionPreset.high,
    );

    try {
      await controller!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (controller == null || !controller!.value.isInitialized) return;

    // Refresh GPS before taking photo
    if (_gpsEnabled) {
      await _getCurrentLocation();
    }

    try {
      final image = await controller!.takePicture();
      
      if (!mounted) return;
      
      final description = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => PhotoDescriptionScreen(
            imagePath: image.path,
            position: _currentPosition,
          ),
        ),
      );

      if (description != null) {
        await _savePhoto(image.path, description);
      }
    } catch (e) {
      print('Error taking picture: $e');
    }
  }

  Future<void> _savePhoto(String imagePath, String description) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${directory.path}/photos');
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'photo_$timestamp.jpg';
      await File(imagePath).copy('${photosDir.path}/$fileName');

      // Save metadata with GPS
      final photoData = PhotoData(
        imagePath: '${photosDir.path}/$fileName',
        description: description,
        timestamp: timestamp,
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
      );

      final metaFile = File('${photosDir.path}/photo_$timestamp.json');
      await metaFile.writeAsString(json.encode(photoData.toJson()));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_currentPosition != null 
                ? 'Zdjęcie zapisane z lokalizacją GPS!' 
                : 'Zdjęcie zapisane (bez GPS)'),
          ),
        );
      }
    } catch (e) {
      print('Error saving photo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionGranted) {
      return Scaffold(
        appBar: AppBar(title: const Text('Picture Perfect')),
        body: const Center(child: Text('Brak uprawnień do aparatu')),
      );
    }

    if (!_isInitialized || controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Picture Perfect')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(controller!)),
          
          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Image.asset('assets/logo.png', height: 40),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _gpsEnabled ? Icons.gps_fixed : Icons.gps_off,
                            color: _gpsEnabled ? Colors.green : Colors.red,
                          ),
                          onPressed: _getCurrentLocation,
                        ),
                        IconButton(
                          icon: const Icon(Icons.map, color: Colors.white),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MapScreen(),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.photo_library, color: Colors.white),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const PhotoListScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // GPS indicator
          if (_currentPosition != null)
            Positioned(
              bottom: 120,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'GPS: ${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          
          // Capture button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _takePicture,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.blue, width: 4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PhotoDescriptionScreen extends StatefulWidget {
  final String imagePath;
  final Position? position;

  const PhotoDescriptionScreen({
    super.key,
    required this.imagePath,
    this.position,
  });

  @override
  State<PhotoDescriptionScreen> createState() => _PhotoDescriptionScreenState();
}

class _PhotoDescriptionScreenState extends State<PhotoDescriptionScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dodaj opis'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.pop(context, _controller.text),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Image.file(File(widget.imagePath), fit: BoxFit.contain),
          ),
          if (widget.position != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.green[100],
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'GPS: ${widget.position!.latitude.toStringAsFixed(6)}, ${widget.position!.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[200],
            child: Column(
              children: [
                TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Dodaj opis zdjęcia...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Anuluj'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context, _controller.text);
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Zapisz'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
