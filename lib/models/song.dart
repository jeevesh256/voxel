class Song {
  final String title;
  final String artist;
  final String albumArt;
  final Duration duration;

  const Song({
    required this.title,
    required this.artist,
    this.albumArt = '',
    this.duration = const Duration(minutes: 3),
  });
}
