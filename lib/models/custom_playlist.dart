class CustomPlaylist {
  final String id;
  final String name;
  final String? artworkPath;
  final int? artworkColor; // Store color as int
  final List<String> songPaths;
  final DateTime createdAt;
  final DateTime modifiedAt;

  CustomPlaylist({
    required this.id,
    required this.name,
    this.artworkPath,
    this.artworkColor,
    required this.songPaths,
    required this.createdAt,
    required this.modifiedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artworkPath': artworkPath,
      'artworkColor': artworkColor,
      'songPaths': songPaths,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
    };
  }

  factory CustomPlaylist.fromJson(Map<String, dynamic> json) {
    return CustomPlaylist(
      id: json['id'],
      name: json['name'],
      artworkPath: json['artworkPath'],
      artworkColor: json['artworkColor'],
      songPaths: List<String>.from(json['songPaths']),
      createdAt: DateTime.parse(json['createdAt']),
      modifiedAt: DateTime.parse(json['modifiedAt']),
    );
  }

  CustomPlaylist copyWith({
    String? name,
    String? artworkPath,
    int? artworkColor,
    List<String>? songPaths,
    DateTime? modifiedAt,
  }) {
    return CustomPlaylist(
      id: id,
      name: name ?? this.name,
      artworkPath: artworkPath ?? this.artworkPath,
      artworkColor: artworkColor ?? this.artworkColor,
      songPaths: songPaths ?? this.songPaths,
      createdAt: createdAt,
      modifiedAt: modifiedAt ?? DateTime.now(),
    );
  }
}
