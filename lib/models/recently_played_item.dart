import 'radio_station.dart';

class RecentlyPlayedItem {
  final String type; // 'song' | 'radio' | 'playlist'
  final String id;
  final String title;
  final String subtitle;
  final String artwork;
  final int timestamp;
  final RadioStation? radioStation;

  RecentlyPlayedItem({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.artwork,
    required this.timestamp,
    this.radioStation,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'artwork': artwork,
        'timestamp': timestamp,
        if (radioStation != null) 'radioStation': radioStation!.toJson(),
      };

  factory RecentlyPlayedItem.fromJson(Map<String, dynamic> json) => RecentlyPlayedItem(
        type: json['type'] ?? '',
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        subtitle: json['subtitle'] ?? '',
        artwork: json['artwork'] ?? '',
        timestamp: json['timestamp'] ?? 0,
        radioStation: json['radioStation'] != null
            ? RadioStation.fromJson(json['radioStation'])
            : null,
      );
}
