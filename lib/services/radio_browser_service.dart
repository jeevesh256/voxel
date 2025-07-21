import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/radio_station.dart';

class RadioBrowserService {
  static const String _baseUrl = 'https://de1.api.radio-browser.info/json';

  Future<List<RadioStation>> fetchStations({String? genre, int limit = 20}) async {
    final uri = Uri.parse(
      genre == null || genre.isEmpty
        ? '$_baseUrl/stations?limit=$limit&hidebroken=true'
        : '$_baseUrl/stations/bytag/$genre?limit=$limit&hidebroken=true'
    );
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((e) => RadioStation.fromJson(e)).where((s) => s.streamUrl.isNotEmpty).toList();
    }
    return [];
  }

  Future<List<RadioStation>> fetchTopStations({int limit = 200}) async {
    final uri = Uri.parse('$_baseUrl/stations/topclick/$limit');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((e) => RadioStation.fromJson(e)).where((s) => s.streamUrl.isNotEmpty).toList();
    }
    return [];
  }

  Future<List<String>> fetchGenres() async {
    final uri = Uri.parse('$_baseUrl/tags');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((e) => e['name'] as String).toList();
    }
    return [];
  }
}
