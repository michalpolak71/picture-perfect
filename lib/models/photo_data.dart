class PhotoData {
  final String imagePath;
  final String description;
  final int timestamp;
  final double? latitude;
  final double? longitude;
  final String? sessionId;
  final double? altitude;
  final int? floor;
  final double? relativeHeight;
  final String? floorLabel;

  PhotoData({
    required this.imagePath,
    required this.description,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.sessionId,
    this.altitude,
    this.floor,
    this.relativeHeight,
    this.floorLabel,
  });

  String get id => timestamp.toString();

  bool hasLocation() => latitude != null && longitude != null;

  String get fullLocation {
    String loc = '';
    if (latitude != null && longitude != null) {
      loc = 'GPS: ${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}';
    }
    if (floorLabel != null) {
      loc += '\nKondygnacja: $floorLabel';
    }
    if (relativeHeight != null) {
      loc += ' (${relativeHeight! >= 0 ? '+' : ''}${relativeHeight!.toStringAsFixed(2)}m)';
    }
    if (altitude != null) {
      loc += '\nWysokość n.p.m.: ${altitude!.toStringAsFixed(1)}m';
    }
    return loc;
  }

  Map<String, dynamic> toJson() => {
        'imagePath': imagePath,
        'description': description,
        'timestamp': timestamp,
        'latitude': latitude,
        'longitude': longitude,
        'sessionId': sessionId,
        'altitude': altitude,
        'floor': floor,
        'relativeHeight': relativeHeight,
        'floorLabel': floorLabel,
      };

  factory PhotoData.fromJson(Map<String, dynamic> json) => PhotoData(
        imagePath: json['imagePath'],
        description: json['description'],
        timestamp: json['timestamp'],
        latitude: json['latitude']?.toDouble(),
        longitude: json['longitude']?.toDouble(),
        sessionId: json['sessionId'],
        altitude: json['altitude']?.toDouble(),
        floor: json['floor'],
        relativeHeight: json['relativeHeight']?.toDouble(),
        floorLabel: json['floorLabel'],
      );
}
