import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import '../models/mood_entry.dart';
import '../models/hive_models.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Connectivity _connectivity = Connectivity();
  late Box<CachedMood> _moodCache;
  late Box<AppSettings> _settingsBox;

  Future<void> initHive() async {
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