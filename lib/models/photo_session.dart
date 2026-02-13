class PhotoSession {
  final String id;
  final String name;
  final int createdTimestamp;
  final List<String> photoIds;

  PhotoSession({
    required this.id,
    required this.name,
    required this.createdTimestamp,
    required this.photoIds,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdTimestamp': createdTimestamp,
        'photoIds': photoIds,
      };

  factory PhotoSession.fromJson(Map<String, dynamic> json) => PhotoSession(
        id: json['id'],
        name: json['name'],
        createdTimestamp: json['createdTimestamp'],
        photoIds: List<String>.from(json['photoIds'] ?? []),
      );
}
