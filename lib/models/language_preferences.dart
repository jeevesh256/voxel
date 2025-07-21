import 'package:flutter/material.dart';

class LanguagePreferences extends ChangeNotifier {
  final List<String> _selectedLanguages = ['English'];

  List<String> get selectedLanguages => _selectedLanguages;

  void toggleLanguage(String language) {
    if (_selectedLanguages.contains(language)) {
      _selectedLanguages.remove(language);
    } else {
      _selectedLanguages.add(language);
    }
    notifyListeners();
  }

  void setLanguages(List<String> languages) {
    _selectedLanguages
      ..clear()
      ..addAll(languages);
    notifyListeners();
  }
}
