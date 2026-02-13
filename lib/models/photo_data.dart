class PhotoData {
  final String imagePath;
  final String description;
  final int timestamp;
  final double? latitude;
  final double? longitude;
  final String? sessionId;

  PhotoData({
    required this.imagePath,
    required this.description,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.sessionId,
  });

  String get id => timestamp.toString();

  Map<String, dynamic> toJson() => {
        'imagePath': imagePath,
        'description': description,
        'timestamp': timestamp,
        'latitude': latitude,
        'longitude': longitude,
        'sessionId': sessionId,
      };

  factory PhotoData.fromJson(Map<String, dynamic> json) => PhotoData(
        imagePath: json['imagePath'],
        description: json['description'],
        timestamp: json['timestamp'],
        latitude: json['latitude'],
        longitude: json['longitude'],
        sessionId: json['sessionId'],
      );

  bool hasLocation() => latitude != null && longitude != null;
}
