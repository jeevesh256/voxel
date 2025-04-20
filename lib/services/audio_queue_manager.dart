import 'package:just_audio/just_audio.dart';
import '../models/song.dart';

abstract class AudioQueueManager {
  Future<void> reorderQueue(int oldIndex, int newIndex);
  Future<void> removeFromQueue(int index);
  Future<void> addToQueue(Song song);
  Future<void> updateQueue(List<Song> songs);
}
