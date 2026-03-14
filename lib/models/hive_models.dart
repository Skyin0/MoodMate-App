import 'package:hive/hive.dart';

part 'hive_models.g.dart';

@HiveType(typeId: 0)
class CachedMood {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String emoji;
  
  @HiveField(2)
  final String note;
  
  @HiveField(3)
  final DateTime timestamp;
  
  @HiveField(4)
  final int moodScore;
  
  @HiveField(5)
  bool synced;
  
  CachedMood({
    required this.id,
    required this.emoji,
    required this.note,
    required this.timestamp,
    required this.moodScore,
    this.synced = false,
  });
}

@HiveType(typeId: 1)
class AppSettings {
  @HiveField(0)
  bool isDarkMode;
  
  @HiveField(1)
  bool notificationsEnabled;
  
  @HiveField(2)
  String language;
  
  @HiveField(3)
  double fontSizeScale;
  
  AppSettings({
    this.isDarkMode = false,
    this.notificationsEnabled = true,
    this.language = 'en',
    this.fontSizeScale = 1.0,
  });
  
  AppSettings copyWith({
    bool? isDarkMode,
    bool? notificationsEnabled,
    String? language,
    double? fontSizeScale,
  }) {
    return AppSettings(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      language: language ?? this.language,
      fontSizeScale: fontSizeScale ?? this.fontSizeScale,
    );
  }
}