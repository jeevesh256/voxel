import 'package:just_audio/just_audio.dart';

abstract class QueueManager {
  Future<void> reorderQueue(int oldIndex, int newIndex);
  Future<void> removeFromQueue(int index);
  Future<void> addToQueue(int index);
}
