import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';

// --------------------------- Model: MoodEntry ------------------------------
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

// ---------------------------- FirebaseService ------------------------------
import 'package:connectivity_plus/connectivity_plus.dart';
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

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Connectivity _connectivity = Connectivity();
  late Box<CachedMood> _moodCache;
  late Box<AppSettings> _settingsBox;

  Future<void> initHive() async {
    await Hive.initFlutter();
    Hive.registerAdapter(CachedMoodAdapter());
    Hive.registerAdapter(AppSettingsAdapter());
    _moodCache = await Hive.openBox<CachedMood>('mood_cache');
    _settingsBox = await Hive.openBox<AppSettings>('app_settings');
  }

  Future<User?> signUp(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    return cred.user;
  }

  Future<User?> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
    return cred.user;
  }

  Future<void> signOut() => _auth.signOut();

  Future<String> addMood(String uid, MoodEntry mood) async {
    final connectivity = await _connectivity.checkConnectivity();
    final cachedMood = CachedMood(
      id: mood.id,
      emoji: mood.emoji,
      note: mood.note,
      timestamp: mood.timestamp,
      moodScore: mood.moodScore,
      synced: connectivity != ConnectivityResult.none,
    );

    await _moodCache.put(mood.id, cachedMood);

    if (connectivity != ConnectivityResult.none) {
      try {
        final ref = _db.collection('users').doc(uid).collection('moods');
        final docRef = await ref.add(mood.toMap());
        
        cachedMood.synced = true;
        await _moodCache.put(mood.id, cachedMood);
        
        return docRef.id;
      } catch (e) {
        print('Sync failed: $e');
      }
    }
    
    return mood.id;
  }

  Stream<List<MoodEntry>> streamMoods(String uid) {
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('moods')
        .orderBy('timestamp', descending: true);
    return ref.snapshots().map(
        (snap) => snap.docs.map((d) => MoodEntry.fromDoc(d)).toList());
  }

  Future<void> updateMood(String uid, String id, Map<String, dynamic> updates) async {
    final doc = _db.collection('users').doc(uid).collection('moods').doc(id);
    await doc.update(updates);
  }

  Future<void> deleteMood(String uid, String id) async {
    final doc = _db.collection('users').doc(uid).collection('moods').doc(id);
    await doc.delete();
  }
  
  Future<void> syncOfflineMoods(String uid) async {
    final offlineMoods = _moodCache.values
        .where((mood) => !mood.synced)
        .toList();

    for (final cached in offlineMoods) {
      final mood = MoodEntry(
        id: cached.id,
        emoji: cached.emoji,
        note: cached.note,
        timestamp: cached.timestamp,
        moodScore: cached.moodScore,
      );
      
      try {
        await _db
            .collection('users')
            .doc(uid)
            .collection('moods')
            .add(mood.toMap());
        
        cached.synced = true;
        await _moodCache.put(cached.id, cached);
      } catch (e) {
        print('Failed to sync mood ${cached.id}: $e');
      }
    }
  }
  
  Future<void> saveSettings(AppSettings settings) async {
    await _settingsBox.put('settings', settings);
  }
  
  AppSettings loadSettings() {
    return _settingsBox.get('settings') ?? AppSettings();
  }
}

// --------------------------- Validators ----------------------------
String? validateEmail(String? email) {
  if (email == null || email.trim().isEmpty) return 'Email required';
  final re = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$");
  if (!re.hasMatch(email.trim())) return 'Enter a valid email';
  return null;
}

String? validatePassword(String? pw) {
  if (pw == null || pw.length < 6) return 'Password must be at least 6';
  return null;
}

// --------------------------- Riverpod providers ----------------------------
final firebaseServiceProvider = Provider<FirebaseService>((ref) => FirebaseService());
final authStateProvider = StreamProvider<User?>((ref) => FirebaseAuth.instance.authStateChanges());

final moodListProvider = StateNotifierProvider<MoodListNotifier, AsyncValue<List<MoodEntry>>>(
  (ref) => MoodListNotifier(ref),
);

class MoodListNotifier extends StateNotifier<AsyncValue<List<MoodEntry>>> {
  final Ref ref;
  StreamSubscription<List<MoodEntry>>? _sub;
  MoodListNotifier(this.ref) : super(const AsyncValue.loading()) {
    _init();
  }

  Future<void> _init() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      state = const AsyncValue.data([]);
      return;
    }
    _sub?.cancel();
    _sub = ref.read(firebaseServiceProvider).streamMoods(user.uid).listen(
          (moods) => state = AsyncValue.data(moods),
          onError: (err, st) => state = AsyncValue.error(err, st),
        );
  }

  Future<void> add(MoodEntry m) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');
    await ref.read(firebaseServiceProvider).addMood(user.uid, m);
  }

  Future<void> update(String id, Map<String, dynamic> updates) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');
    await ref.read(firebaseServiceProvider).updateMood(user.uid, id, updates);
  }

  Future<void> delete(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');
    await ref.read(firebaseServiceProvider).deleteMood(user.uid, id);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// ------------------------------- Emoji set --------------------------------
const List<String> emojiOptions = ['😁', '🙂', '😐', '😢', '😡', '🤩', '😴', '😰'];

// -------------------------- Notification Service ---------------------------
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    
    print('Notification permission: ${settings.authorizationStatus}');

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    await _notificationsPlugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showNotification(message);
    });

    final token = await _firebaseMessaging.getToken();
    print('FCM Token: $token');
  }

  static Future<void> _showNotification(RemoteMessage message) async {
    const androidDetails = AndroidNotificationDetails(
      'moodmate_channel',
      'MoodMate Notifications',
      channelDescription: 'Notifications for mood tracking',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const iosDetails = DarwinNotificationDetails();
    
    await _notificationsPlugin.show(
      0,
      message.notification?.title ?? 'MoodMate',
      message.notification?.body ?? 'New notification',
      const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
    );
  }

  static Future<void> scheduleDailyReminder(TimeOfDay time) async {
    const androidDetails = AndroidNotificationDetails(
      'daily_reminder',
      'Daily Reminder',
      channelDescription: 'Daily mood tracking reminder',
      importance: Importance.high,
    );
    
    await _notificationsPlugin.zonedSchedule(
      1,
      'How are you feeling today?',
      'Track your mood in MoodMate',
      _nextTime(time.hour, time.minute),
      const NotificationDetails(android: androidDetails),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
  
  static tz.TZDateTime _nextTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    
    return scheduled;
  }
}

// -------------------------- API Service ---------------------------
import 'dart:convert';
import 'package:http/http.dart' as http;

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
    return {
      'averageMood': moods.isEmpty ? 0 : moods.map((m) => m.moodScore).reduce((a, b) => a + b) / moods.length,
      'trend': 'stable',
      'suggestion': 'Try to maintain consistency in your mood tracking',
    };
  }
}

// -------------------------- Route Transitions ---------------------------
class FadeRouteBuilder<T> extends PageRouteBuilder<T> {
  final Widget page;

  FadeRouteBuilder({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
        );
}

class SlideUpRouteBuilder<T> extends PageRouteBuilder<T> {
  final Widget page;

  SlideUpRouteBuilder({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(0.0, 1.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;
            
            var tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: curve),
            );
            
            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 400),
        );
}

class ShimmerMoodTile extends StatelessWidget {
  const ShimmerMoodTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        title: Container(
          height: 16,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        subtitle: Container(
          height: 12,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

// ------------------------------- Main -------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  await Hive.initFlutter();
  
  await NotificationService.initialize();
  
  final prefs = await SharedPreferences.getInstance();
  final isDarkMode = prefs.getBool('isDarkMode') ?? false;
  
  runApp(
    ProviderScope(
      overrides: [
        initialThemeProvider.overrideWithValue(isDarkMode),
      ],
      child: const MoodMateApp(),
    ),
  );
}

final initialThemeProvider = StateProvider<bool>((ref) => false);
final fontSizeScaleProvider = StateProvider<double>((ref) => 1.0);

final appSettingsProvider = StateNotifierProvider<AppSettingsNotifier, AppSettings>(
  (ref) => AppSettingsNotifier(),
);

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier() : super(AppSettings());

  void updateNotifications(bool enabled) {
    state = state.copyWith(notificationsEnabled: enabled);
  }
  
  void updateLanguage(String lang) {
    state = state.copyWith(language: lang);
  }
}

// ----------------------------- App Widget ---------------------------------
class MoodMateApp extends ConsumerStatefulWidget {
  const MoodMateApp({Key? key}) : super(key: key);

  @override
  ConsumerState<MoodMateApp> createState() => _MoodMateAppState();
}

class _MoodMateAppState extends ConsumerState<MoodMateApp> {
  bool isDark = false;

  void toggleTheme(bool val) => setState(() => isDark = val);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoodMate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light, colorSchemeSeed: Colors.blue),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: Colors.blue),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: AuthWrapper(toggleTheme: toggleTheme, isDark: isDark),
    );
  }
}

// --------------------------- Auth wrapper ---------------------------------
class AuthWrapper extends ConsumerWidget {
  final void Function(bool) toggleTheme;
  final bool isDark;
  const AuthWrapper({required this.toggleTheme, required this.isDark, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    return authState.when(
      data: (user) {
        if (user == null) return const LoginScreen();
        ref.read(moodListProvider);
        return HomeScreen(toggleTheme: toggleTheme, isDark: isDark);
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Auth error: $e'))),
    );
  }
}

// --------------------------- Login Screen ---------------------------------
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  String email = '';
  String password = '';
  bool isLoading = false;
  bool isLogin = true;

  void submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);
    final service = ref.read(firebaseServiceProvider);
    try {
      if (isLogin) {
        await service.signIn(email, password);
      } else {
        await service.signUp(email, password);
      }
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(20),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: validateEmail,
                  onChanged: (v) => email = v,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  validator: validatePassword,
                  onChanged: (v) => password = v,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                    onPressed: isLoading ? null : submit,
                    child: Text(isLogin ? 'Login' : 'Sign Up')),
                TextButton(
                  onPressed: () => setState(() => isLogin = !isLogin),
                  child: Text(isLogin ? 'Create account' : 'Already have account?'),
                )
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------- Home Screen ---------------------------------
class HomeScreen extends ConsumerWidget {
  final void Function(bool) toggleTheme;
  final bool isDark;
  const HomeScreen({required this.toggleTheme, required this.isDark, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moodState = ref.watch(moodListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MoodMate'),
        actions: [
          Semantics(
            label: 'Toggle dark mode',
            child: Switch(
              value: isDark,
              onChanged: toggleTheme,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          Semantics(
            label: 'Logout button',
            child: IconButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.logout),
            ),
          ),
        ],
      ),
      body: moodState.when(
        data: (moods) {
          if (moods.isEmpty) {
            return const Center(
              child: Semantics(
                label: 'No moods recorded yet',
                child: Text('No moods yet'),
              ),
            );
          }
          
          return ListView.builder(
            itemCount: moods.length,
            itemBuilder: (context, index) {
              final m = moods[index];
              return Semantics(
                label: 'Mood entry: ${m.emoji} ${m.note}',
                child: Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: ExcludeSemantics(
                      child: Text(m.emoji, style: const TextStyle(fontSize: 28)),
                    ),
                    title: Text(
                      m.note,
                      style: TextStyle(
                        fontSize: 16 * ref.watch(fontSizeScaleProvider),
                      ),
                    ),
                    subtitle: Text(
                      DateFormat.yMMMd().add_jm().format(m.timestamp),
                    ),
                    trailing: Semantics(
                      label: 'Delete mood entry',
                      child: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => ref.read(moodListProvider.notifier).delete(m.id),
                      ),
                    ),
                    onTap: () async {
                      final newNote = await showDialog<String>(
                        context: context,
                        builder: (_) => EditMoodDialog(mood: m),
                      );
                      if (newNote != null) {
                        ref.read(moodListProvider.notifier).update(m.id, {'note': newNote});
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(
          child: Semantics(
            label: 'Loading moods',
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, st) => Center(
          child: Semantics(
            label: 'Error loading moods',
            child: Text('Error: $e'),
          ),
        ),
      ),
      floatingActionButton: Semantics(
        label: 'Add new mood',
        child: FloatingActionButton(
          onPressed: () async {
            final newMood = await showDialog<MoodEntry>(
              context: context,
              builder: (_) => const AddMoodDialog(),
            );
            if (newMood != null) {
              ref.read(moodListProvider.notifier).add(newMood);
            }
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

// --------------------------- Settings Screen ---------------------------------
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontSizeScale = ref.watch(fontSizeScaleProvider);
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Font Size'),
            subtitle: Slider(
              value: fontSizeScale,
              min: 0.8,
              max: 1.5,
              divisions: 7,
              label: fontSizeScale.toStringAsFixed(1),
              onChanged: (value) {
                ref.read(fontSizeScaleProvider.notifier).state = value;
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Enable Notifications'),
            value: settings.notificationsEnabled,
            onChanged: (value) {
              ref.read(appSettingsProvider.notifier).updateNotifications(value);
              if (value) {
                NotificationService.scheduleDailyReminder(
                  const TimeOfDay(hour: 20, minute: 0),
                );
              }
            },
          ),
          ListTile(
            title: const Text('Daily Reminder Time'),
            subtitle: const Text('8:00 PM'),
            onTap: () async {
              final time = await showTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 20, minute: 0),
              );
              if (time != null) {
                NotificationService.scheduleDailyReminder(time);
              }
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Clear Cache'),
            subtitle: const Text('Remove all locally stored data'),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Cache'),
                  content: const Text('Are you sure? This will remove all offline data.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await Hive.box('mood_cache').clear();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cache cleared')),
                );
              }
            },
          ),
          ListTile(
            title: const Text('Export Data'),
            subtitle: const Text('Download your mood history as CSV'),
            onTap: () {
              // Implement CSV export
            },
          ),
        ],
      ),
    );
  }
}

// --------------------------- AddMood Dialog ---------------------------------
class AddMoodDialog extends StatefulWidget {
  const AddMoodDialog({Key? key}) : super(key: key);

  @override
  State<AddMoodDialog> createState() => _AddMoodDialogState();
}

class _AddMoodDialogState extends State<AddMoodDialog> {
  String selectedEmoji = emojiOptions.first;
  final noteController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Mood'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(
          spacing: 8,
          children: emojiOptions.map((e) {
            return ChoiceChip(
              label: Text(e, style: const TextStyle(fontSize: 20)),
              selected: selectedEmoji == e,
              onSelected: (_) => setState(() => selectedEmoji = e),
            );
          }).toList(),
        ),
        TextField(
          controller: noteController,
          decoration: const InputDecoration(labelText: 'Note'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final newMood = MoodEntry(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              emoji: selectedEmoji,
              note: noteController.text,
              timestamp: DateTime.now(),
              moodScore: 0,
            );
            Navigator.pop(context, newMood);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

// --------------------------- EditMood Dialog ---------------------------------
class EditMoodDialog extends StatefulWidget {
  final MoodEntry mood;
  const EditMoodDialog({required this.mood, Key? key}) : super(key: key);

  @override
  State<EditMoodDialog> createState() => _EditMoodDialogState();
}

class _EditMoodDialogState extends State<EditMoodDialog> {
  late TextEditingController controller;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.mood.note);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Note'),
      content: TextField(controller: controller),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
      ],
    );
  }
}