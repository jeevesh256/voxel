import 'package:flutter/material.dart';

class SettingsModel extends ChangeNotifier {
  bool _showNonMusicGenres = false;

  bool get showNonMusicGenres => _showNonMusicGenres;

  void setShowNonMusicGenres(bool value) {
    _showNonMusicGenres = value;
    notifyListeners();
  }
}
