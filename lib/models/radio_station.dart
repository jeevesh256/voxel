import 'package:flutter/material.dart';

class RadioStation {
  final String id;
  final String name;
  final String streamUrl;
  final String genre;
  final String artworkUrl;
  final String country;

  const RadioStation({
    required this.id,
    required this.name,
    required this.streamUrl,
    required this.genre,
    required this.artworkUrl,
    required this.country,
  });

  factory RadioStation.fromJson(Map<String, dynamic> json) {
    return RadioStation(
      id: json['id'] ?? json['stationuuid'] ?? '',
      name: json['name'] ?? '',
      streamUrl: json['streamUrl'] ?? json['url_resolved'] ?? '',
      genre: json['genre'] ?? json['tags'] ?? '',
      artworkUrl: json['artworkUrl'] ?? json['favicon'] ?? '',
      country: json['country'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'streamUrl': streamUrl,
      'genre': genre,
      'artworkUrl': artworkUrl,
      'country': country,
    };
  }
}
