import 'dart:io';


import 'radio_station.dart';

class PlaylistModel {
  final String id;
  final String name;
  final List<File> songs;
  final List<RadioStation> radios;
  final bool isSystem;

  const PlaylistModel({
    required this.id,
    required this.name,
    this.songs = const [],
    this.radios = const [],
    this.isSystem = false,
  });
}
