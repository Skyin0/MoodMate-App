import 'package:cloud_firestore/cloud_firestore.dart';

class MoodEntry {
  final String id;
  final String emoji;
  final String note;
  final DateTime timestamp;
  final int moodScore;

  MoodEntry({
    required this.id,
    required this.emoji,
    required this.note,
    required this.timestamp,
    required this.moodScore,
  });

  Map<String, dynamic> toMap() => {
        'emoji': emoji,
        'note': note,
        'timestamp': Timestamp.fromDate(timestamp),
        'moodScore': moodScore,
      };

  static MoodEntry fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MoodEntry(
      id: doc.id,
      emoji: data['emoji'] ?? '🙂',
      note: data['note'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      moodScore: (data['moodScore'] is int) ? data['moodScore'] : 0,
    );
  }
}