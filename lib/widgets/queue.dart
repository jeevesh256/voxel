import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';  // Fixed import
import 'dart:convert';

class QueueList extends StatefulWidget {
  const QueueList({super.key});

  @override
  State<QueueList> createState() => _QueueListState();
}

class _QueueListState extends State<QueueList> {
  List<Map<String, String>> _songs = [];
  static const String _storageKey = 'queue_songs';
  SharedPreferences? _prefs;  // Make nullable

  @override
  void initState() {
    super.initState();
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadSongs();
    } catch (e) {
      debugPrint('Error initializing preferences: $e');
      _setDefaultSongs();
    }
  }

  Future<void> _loadSongs() async {
    try {
      final String? songsJson = _prefs?.getString(_storageKey);
      if (songsJson != null) {
        setState(() {
          _songs = List<Map<String, String>>.from(
            (json.decode(songsJson) as List).map((item) => Map<String, String>.from(item)),
          );
        });
      } else {
        _setDefaultSongs();
      }
    } catch (e) {
      debugPrint('Error loading songs: $e');
      _setDefaultSongs();
    }
  }

  void _setDefaultSongs() {
    setState(() {
      _songs = List.generate(
        10,
        (index) => {
          'title': 'Song ${index + 1}',
          'artist': 'Artist ${index + 1}',
        },
      );
    });
    _saveSongs();
  }

  Future<void> _saveSongs() async {
    try {
      await _prefs?.setString(_storageKey, json.encode(_songs));
    } catch (e) {
      debugPrint('Error saving songs: $e');
    }
  }

  // Update onReorder to save changes
  void _handleReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _songs.removeAt(oldIndex);
      _songs.insert(newIndex, item);
    });
    _saveSongs();
  }

  // Update onDismissed to save changes
  void _handleDismiss(int index, Map<String, String> deletedSong) {
    setState(() {
      _songs.removeAt(index);
    });
    _saveSongs();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed ${deletedSong['title']}'),
        backgroundColor: Colors.grey.shade800,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.white,
          onPressed: () {
            setState(() {
              _songs.insert(index, deletedSong);
            });
            _saveSongs();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Playing Next',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: _songs.length,
              onReorderStart: (index) {
                HapticFeedback.mediumImpact();
              },
              onReorder: _handleReorder,
              itemBuilder: (context, index) {
                final currentSong = _songs[index];
                return Dismissible(
                  key: ValueKey('dismiss_${currentSong['title']}_$index'),
                  background: Container(
                    color: Colors.red.shade400,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  direction: DismissDirection.endToStart,
                  onDismissed: (direction) => _handleDismiss(index, currentSong),
                  child: ReorderableDragStartListener(
                    key: ValueKey('drag_${currentSong['title']}_$index'),
                    index: index,
                    child: ListTile(
                      leading: Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          color: Colors.deepPurple.shade200,
                        ),
                        child: const Icon(Icons.music_note),
                      ),
                      title: Text(
                        _songs[index]['title']!,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        _songs[index]['artist']!,
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                      trailing: const Icon(
                        Icons.drag_handle,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
