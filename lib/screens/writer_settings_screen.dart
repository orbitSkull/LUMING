import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../providers/reader_settings.dart';
import '../services/tts_service.dart';

class WriterSettingsScreen extends StatefulWidget {
  const WriterSettingsScreen({super.key});

  @override
  State<WriterSettingsScreen> createState() => _WriterSettingsScreenState();
}

class _WriterSettingsScreenState extends State<WriterSettingsScreen> {
  bool _autoSave = true;
  bool _autoCapitalization = true;
  double _fontSize = 16.0;
  double _lineHeight = 1.5;
  String _fontFamily = 'Sans';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoSave = prefs.getBool('writer_autoSave') ?? true;
      _autoCapitalization = prefs.getBool('writer_autoCapitalization') ?? true;
      final settings = context.read<ReaderSettings>();
      _fontSize = prefs.getDouble('writer_fontSize') ?? settings.fontSize;
      _lineHeight = prefs.getDouble('writer_lineHeight') ?? settings.lineHeight;
      _fontFamily = prefs.getString('writer_fontFamily') ?? 'Sans';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('writer_autoSave', _autoSave);
    await prefs.setBool('writer_autoCapitalization', _autoCapitalization);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReaderSettings>();
    final tts = Provider.of<TtsService>(context);

    return ListView(
      children: [
        _buildSection('Appearance', [
          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: const Text('Toggle dark/light theme'),
            value: settings.darkMode,
            onChanged: (value) {
              settings.setDarkMode(value);
            },
          ),
          ListTile(
            title: const Text('Default Font Size'),
            subtitle: Text('${settings.fontSize.toInt()}px'),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: settings.fontSize,
                min: 12,
                max: 32,
                divisions: 10,
                label: '${settings.fontSize.toInt()}px',
                onChanged: (value) {
                  settings.setFontSize(value);
                },
              ),
            ),
          ),
          ListTile(
            title: const Text('Default Line Height'),
            subtitle: Text(settings.lineHeight.toStringAsFixed(1)),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: settings.lineHeight,
                min: 1.2,
                max: 2.0,
                divisions: 8,
                label: settings.lineHeight.toStringAsFixed(1),
                onChanged: (value) {
                  settings.setLineHeight(value);
                },
              ),
            ),
          ),
        ]),
        _buildSection('Text-to-Speech', [
          ListTile(
            title: const Text('Default Speech Rate'),
            subtitle: Text('${tts.speechRate.toStringAsFixed(2)}x'),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: tts.speechRate,
                min: 0.1,
                max: 4.0,
                divisions: 39,
                label: '${tts.speechRate.toStringAsFixed(2)}x',
                onChanged: (value) {
                  tts.setSpeechRate(value);
                },
              ),
            ),
          ),
          ListTile(
            title: const Text('Default Pitch'),
            subtitle: Text(tts.pitch.toStringAsFixed(2)),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: tts.pitch,
                min: 0.1,
                max: 4.0,
                divisions: 39,
                label: tts.pitch.toStringAsFixed(2),
                onChanged: (value) {
                  tts.setPitch(value);
                },
              ),
            ),
          ),
        ]),
        _buildSection('Writing Behavior', [
          SwitchListTile(
            title: const Text('Auto-Save'),
            subtitle: const Text('Automatically save changes'),
            value: _autoSave,
            onChanged: (value) {
              setState(() => _autoSave = value);
              _saveSettings();
            },
          ),
          SwitchListTile(
            title: const Text('Auto-Capitalization'),
            subtitle: const Text('Capitalize first letter of sentences'),
            value: _autoCapitalization,
            onChanged: (value) {
              setState(() => _autoCapitalization = value);
              _saveSettings();
            },
          ),
          SwitchListTile(
            title: const Text('Show Word Count'),
            subtitle: const Text('Display live word counter'),
            value: settings.showWordCount,
            onChanged: (value) {
              settings.setShowWordCount(value);
            },
          ),
          SwitchListTile(
            title: const Text('Focus Mode'),
            subtitle: const Text('Hide status bar and UI'),
            value: settings.focusMode,
            onChanged: (value) {
              settings.setFocusMode(value);
            },
          ),
          SwitchListTile(
            title: const Text('Typewriter Scrolling'),
            subtitle: const Text('Keep current line centered'),
            value: settings.typewriterScrolling,
            onChanged: (value) {
              settings.setTypewriterScrolling(value);
            },
          ),
        ]),
        _buildSection('About', [
          const ListTile(
            title: Text('Version'),
            subtitle: Text('1.0.0'),
          ),
          const ListTile(
            title: Text('Developer'),
            subtitle: Text('DaPub Reader Team'),
          ),
        ]),
        const SizedBox(height: 20),
        const Center(
          child: Column(
            children: [
              Text(
                'LUMING',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'https://github.com/orbitSkull/LUMING',
                style: TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                  fontSize: 12,
                ),
              ),
              SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}