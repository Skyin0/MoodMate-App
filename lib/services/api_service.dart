import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/mood_entry.dart';

class ApiService {
  static const String _baseUrl = 'https://api.quotable.io';
  static const Duration _timeout = Duration(seconds: 10);

  Future<String> getDailyQuote() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/random'),)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return '${data['content']} - ${data['author']}';
      }
      return 'The only way to do great work is to love what you do. - Steve Jobs';
    } catch (e) {
      return 'Stay positive and happy. Work hard and don\'t give up hope.';
    }
  }

  Future<Map<String, dynamic>> analyzeMoodTrends(List<MoodEntry> moods) async {
    // This would integrate with a sentiment analysis API
    // Example: AWS Comprehend, Google Cloud NLP, etc.
    return {
      'averageMood': moods.isEmpty ? 0 : moods.map((m) => m.moodScore).reduce((a, b) => a + b) / moods.length,
      'trend': 'stable',
      'suggestion': 'Try to maintain consistency in your mood tracking',
    };
  }
}