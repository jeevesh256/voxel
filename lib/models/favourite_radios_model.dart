import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'radio_station.dart';

class FavouriteRadiosModel extends ChangeNotifier {
  final List<RadioStation> _favourites = [];

  List<RadioStation> get favourites => List.unmodifiable(_favourites);

  void addFavourite(RadioStation station) {
    if (_favourites.firstWhereOrNull((r) => r.streamUrl == station.streamUrl) == null) {
      _favourites.add(station);
      notifyListeners();
    }
  }

  void removeFavourite(RadioStation station) {
    _favourites.removeWhere((r) => r.streamUrl == station.streamUrl);
    notifyListeners();
  }

  bool isFavourite(RadioStation station) {
    return _favourites.any((r) => r.streamUrl == station.streamUrl);
  }
}
