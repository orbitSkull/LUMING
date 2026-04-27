import 'dart:convert';
import '../services/storage_service.dart';

class WriterSettingsScreen extends StatefulWidget {
  const WriterSettingsScreen({super.key});

  @override
  State<WriterSettingsScreen> createState() => _WriterSettingsScreenState();
}

class _WriterSettingsScreenState extends State<WriterSettingsScreen> {
  bool _autoSave = true;
  bool _autoCapitalization = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = StorageService();
    final settingsFile = File(storage.settingsFile);
    Map<String, dynamic> settings = {};
    if (settingsFile.existsSync()) {
      try {
        settings = jsonDecode(settingsFile.readAsStringSync());
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoSave = settings['writer_autoSave'] ?? prefs.getBool('writer_autoSave') ?? true;
      _autoCapitalization = settings['writer_autoCapitalization'] ?? prefs.getBool('writer_autoCapitalization') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final storage = StorageService();
    final settingsFile = File(storage.settingsFile);
    Map<String, dynamic> settings = {};
    if (settingsFile.existsSync()) {
      try {
        settings = jsonDecode(settingsFile.readAsStringSync());
      } catch (_) {}
    }

    settings['writer_autoSave'] = _autoSave;
    settings['writer_autoCapitalization'] = _autoCapitalization;
    await settingsFile.writeAsString(jsonEncode(settings));

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
          ListTile(
            title: const Text('Voice Selection'),
            subtitle: Text(tts.selectedCustomVoice?.name ?? tts.selectedVoice.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showVoiceSelector(context, tts),
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
            subtitle: Text('1.1.0'),
          ),
          const ListTile(
            title: Text('Developer'),
            subtitle: Text('LUMING Team'),
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

  void _showVoiceSelector(BuildContext context, TtsService tts) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, bool> downloadedStatus = {};
    for (var voice in tts.availableVoices) {
      final modelPath = prefs.getString(voice.modelPrefKey);
      downloadedStatus[voice.key] = modelPath != null && File(modelPath).existsSync();
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => VoiceSelectionModal(
        tts: tts,
        selectedVoicePack: tts.selectedVoice,
        selectedCustomVoice: tts.selectedCustomVoice,
        downloadedVoices: downloadedStatus,
        onVoiceSelected: (voicePack, customVoice) {
          if (customVoice != null) {
            tts.setCustomVoice(customVoice);
          } else if (voicePack != null) {
            tts.setVoice(voicePack);
          }
        },
        onVoiceDelete: (key) async {
          final voice = tts.availableVoices.where((v) => v.key == key).firstOrNull;
          if (voice != null) {
            await tts.deleteCustomVoice(voice);
          }
        },
      ),
    );
  }
}
