import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/photo_data.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _controller;
  final Set<Marker> _markers = {};
  List<PhotoData> _photos = [];
  LatLng _initialPosition = const LatLng(52.2297, 21.0122); // Warsaw default

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${directory.path}/photos');
      
      if (!await photosDir.exists()) return;

      final files = photosDir.listSync();
      final jsonFiles = files.where((f) => f.path.endsWith('.json')).toList();

      List<PhotoData> photos = [];
      
      for (var file in jsonFiles) {
        try {
          final content = await File(file.path).readAsString();
          final data = json.decode(content);
          final photo = PhotoData.fromJson(data);
          if (photo.hasLocation()) {
            photos.add(photo);
          }
        } catch (e) {
          print('Error loading photo: $e');
        }
      }

      if (photos.isNotEmpty) {
        // Set initial position to first photo with GPS
        _initialPosition = LatLng(photos.first.latitude!, photos.first.longitude!);
        
        // Create markers
        for (int i = 0; i < photos.length; i++) {
          final photo = photos[i];
          _markers.add(
            Marker(
              markerId: MarkerId('photo_${photo.timestamp}'),
              position: LatLng(photo.latitude!, photo.longitude!),
              infoWindow: InfoWindow(
                title: 'Zdjęcie ${i + 1}',
                snippet: photo.description.isEmpty ? 'Brak opisu' : photo.description,
                onTap: () => _showPhotoDialog(photo),
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            ),
          );
        }
      }

      setState(() {
        _photos = photos;
      });
    } catch (e) {
      print('Error loading photos for map: $e');
    }
  }

  void _showPhotoDialog(PhotoData photo) {
    final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (File(photo.imagePath).existsSync())
              Image.file(
                File(photo.imagePath),
                height: 300,
                fit: BoxFit.cover,
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (photo.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(photo.description),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _navigateToLocation(photo),
                    icon: const Icon(Icons.navigation),
                    label: const Text('Nawiguj'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToLocation(PhotoData photo) async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${photo.latitude},${photo.longitude}',
    );
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nie można otworzyć nawigacji')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mapa (${_photos.length} zdjęć)'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _photos.isEmpty
          ? const Center(
              child: Text('Brak zdjęć z lokalizacją GPS'),
            )
          : GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _initialPosition,
                zoom: 14,
              ),
              markers: _markers,
              onMapCreated: (controller) {
                _controller = controller;
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
            ),
    );
  }
}
