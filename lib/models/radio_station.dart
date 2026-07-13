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

  static String cleanGenre(String rawGenre) {
    if (rawGenre.isEmpty) return 'Radio Station';
    
    // Split by comma, semicolon, or slash
    final parts = rawGenre.split(RegExp(r'[,;/]'));
    final cleanedList = <String>[];
    
    // Filter out common generic descriptor terms/filler tags
    final genericTerms = {
      'beautiful music',
      'easy listening',
      'various',
      'music',
      'news',
      'information',
      'talk',
      'other',
      'general',
      'variety',
      'radio',
      'live',
      'station',
      'mixed',
      'unknown',
    };
    
    for (var part in parts) {
      var clean = part.trim().toLowerCase();
      
      // Skip if it matches a generic descriptor phrase
      if (genericTerms.contains(clean)) continue;
      
      // Remove any weird symbols, web URLs, or overcrowded tag characters
      clean = clean.replaceAll(RegExp(r'[^a-zA-Z0-9\s-]'), '');
      
      // Skip empty, single character, or numeric-only tags
      if (clean.length < 2 || RegExp(r'^\d+$').hasMatch(clean)) continue;
      
      // Capitalize first letter of each word
      final words = clean.split(' ');
      final capitalized = words.map((w) {
        if (w.isEmpty) return '';
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');
      
      if (capitalized.isNotEmpty && !cleanedList.contains(capitalized)) {
        cleanedList.add(capitalized);
      }
    }
    
    if (cleanedList.isEmpty) return 'Radio Station';
    
    // Return only the single, most accurate genre tag
    return cleanedList.first;
  }

  factory RadioStation.fromJson(Map<String, dynamic> json) {
    return RadioStation(
      id: json['id'] ?? json['stationuuid'] ?? '',
      name: json['name'] ?? '',
      streamUrl: json['streamUrl'] ?? json['url_resolved'] ?? '',
      genre: cleanGenre(json['genre'] ?? json['tags'] ?? ''),
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
