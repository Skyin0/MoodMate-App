import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../services/notification_service.dart';
import '../providers/app_providers.dart';
import '../models/app_settings.dart';

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