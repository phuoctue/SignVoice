import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';

/// User settings screen
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().loadSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final settings = settingsProvider.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: settingsProvider.isLoading && settings == null
          ? const Center(child: CircularProgressIndicator())
          : settingsProvider.errorMessage != null && settings == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Lỗi: ${settingsProvider.errorMessage}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => settingsProvider.loadSettings(),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Theme setting
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Giao diện',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      ListTile(
                        title: const Text('Sáng'),
                        leading: Icon(
                          (settings?.theme ?? 'SYSTEM') == 'LIGHT'
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        onTap: () => _updateTheme('LIGHT'),
                      ),
                      ListTile(
                        title: const Text('Tối'),
                        leading: Icon(
                          (settings?.theme ?? 'SYSTEM') == 'DARK'
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        onTap: () => _updateTheme('DARK'),
                      ),
                      ListTile(
                        title: const Text('Theo hệ thống'),
                        leading: Icon(
                          (settings?.theme ?? 'SYSTEM') == 'SYSTEM'
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        onTap: () => _updateTheme('SYSTEM'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Language setting
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Ngôn ngữ',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      ListTile(
                        title: const Text('Tiếng Việt'),
                        leading: Icon(
                          (settings?.language ?? 'vi') == 'vi'
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        onTap: () => _updateLanguage('vi'),
                      ),
                      ListTile(
                        title: const Text('English'),
                        leading: Icon(
                          (settings?.language ?? 'vi') == 'en'
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        onTap: () => _updateLanguage('en'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Notifications setting
                Card(
                  child: SwitchListTile(
                    title: const Text('Thông báo'),
                    subtitle: const Text('Nhận thông báo từ ứng dụng'),
                    value: settings?.notifications ?? true,
                    onChanged: (value) {
                      _updateNotifications(value);
                    },
                  ),
                ),

                // Loading indicator
                if (settingsProvider.isLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),

                // Error message
                if (settingsProvider.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      settingsProvider.errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _updateTheme(String theme) async {
    final success = await context.read<SettingsProvider>().updateSettings(
      theme: theme,
    );
    if (success && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã cập nhật giao diện')));
    }
  }

  Future<void> _updateLanguage(String language) async {
    final success = await context.read<SettingsProvider>().updateSettings(
      language: language,
    );
    if (success && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã cập nhật ngôn ngữ')));
    }
  }

  Future<void> _updateNotifications(bool notifications) async {
    final success = await context.read<SettingsProvider>().updateSettings(
      notifications: notifications,
    );
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notifications ? 'Đã bật thông báo' : 'Đã tắt thông báo',
          ),
        ),
      );
    }
  }
}
