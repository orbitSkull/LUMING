import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:piper_tts_plugin/enums/piper_voice_pack.dart';
import '../providers/reader_settings.dart';
import '../services/tts_service.dart';
import '../models/piper_voice.dart';
import '../services/storage_service.dart';
import 'dart:convert';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _defaultSpeechRate = 1.0;
  double _defaultPitch = 1.0;
  PiperVoicePack _selectedVoicePack = PiperVoicePack.norman;
  PiperVoice? _selectedCustomVoice;
  
  bool _isLoadingVoice = false;
  double _downloadProgress = 0;
  String _downloadStatus = '';
  Map<String, bool> _downloadedVoices = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkDownloadedVoices();
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
    final voiceIndex = settings['selectedVoice'] ?? prefs.getInt('selectedVoice') ?? PiperVoicePack.norman.index;
    
    setState(() {
      _defaultSpeechRate = settings['defaultSpeechRate'] ?? prefs.getDouble('defaultSpeechRate') ?? 1.0;
      _defaultPitch = settings['defaultPitch'] ?? prefs.getDouble('defaultPitch') ?? 1.0;
      _selectedVoicePack = PiperVoicePack.values[voiceIndex.clamp(0, PiperVoicePack.values.length - 1)];
    });
  }

  Future<void> _checkDownloadedVoices() async {
    final storage = StorageService();
    final settingsFile = File(storage.settingsFile);
    Map<String, dynamic> settings = {};
    if (settingsFile.existsSync()) {
      try {
        settings = jsonDecode(settingsFile.readAsStringSync());
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    Map<String, bool> status = {};
    
    // Check built-in voices
    for (var voice in PiperVoicePack.values) {
      final modelPath = settings[voice.modelPrefKey] ?? prefs.getString(voice.modelPrefKey);
      final jsonPath = settings[voice.jsonPrefKey] ?? prefs.getString(voice.jsonPrefKey);
      status[voice.name] = modelPath != null && File(modelPath).existsSync() &&
                       jsonPath != null && File(jsonPath).existsSync();
    }
    
    // Check custom voices from TtsService
    final tts = Provider.of<TtsService>(context, listen: false);
    for (var voice in tts.availableVoices) {
      final modelPath = settings[voice.modelPrefKey] ?? prefs.getString(voice.modelPrefKey);
      final configPath = settings[voice.configPrefKey] ?? prefs.getString(voice.configPrefKey);
      status[voice.key] = modelPath != null && File(modelPath).existsSync() &&
                          configPath != null && File(configPath).existsSync();
    }

    setState(() {
      _downloadedVoices = status;
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

    settings['defaultSpeechRate'] = _defaultSpeechRate;
    settings['defaultPitch'] = _defaultPitch;
    if (_selectedCustomVoice == null) {
      settings['selectedVoice'] = _selectedVoicePack.index;
      settings.remove('selectedCustomVoiceKey');
    } else {
      settings['selectedCustomVoiceKey'] = _selectedCustomVoice!.key;
    }

    await settingsFile.writeAsString(jsonEncode(settings));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('defaultSpeechRate', _defaultSpeechRate);
    await prefs.setDouble('defaultPitch', _defaultPitch);
    if (_selectedCustomVoice == null) {
      await prefs.setInt('selectedVoice', _selectedVoicePack.index);
      await prefs.remove('selectedCustomVoiceKey');
    } else {
      await prefs.setString('selectedCustomVoiceKey', _selectedCustomVoice!.key);
    }
  }

  Future<void> _downloadVoiceModel() async {
    setState(() {
      _isLoadingVoice = true;
      _downloadProgress = 0;
      _downloadStatus = 'Starting download...';
    });

    try {
      final ttsService = Provider.of<TtsService>(context, listen: false);
      
      if (_selectedCustomVoice != null) {
        await ttsService.downloadCustomVoice(_selectedCustomVoice!, (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
              _downloadStatus = 'Downloading: ${(progress * 100).toStringAsFixed(0)}%';
            });
          }
        });
      }

      await _checkDownloadedVoices();
      if (mounted) {
        final name = _selectedCustomVoice?.name ?? 'Voice';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name voice downloaded successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingVoice = false;
          _downloadStatus = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReaderSettings>();

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
          Consumer<TtsService>(
            builder: (context, tts, _) {
              _selectedCustomVoice = tts.selectedCustomVoice;
              final voiceName = _selectedCustomVoice?.name ?? 'No voice selected';
              final voiceKey = _selectedCustomVoice?.key ?? '';
              final isDownloaded = voiceKey.isNotEmpty && (_downloadedVoices[voiceKey] ?? false);

              return Column(
                children: [
                  ListTile(
                    title: const Text('Voice Model'),
                    subtitle: Text(voiceName),
                    trailing: const Icon(Icons.arrow_drop_down),
                    onTap: () => _showVoiceSelector(tts),
                  ),
                  if (!isDownloaded && voiceKey.isNotEmpty)
                    ListTile(
                      title: const Text('Download Voice'),
                      subtitle: _isLoadingVoice
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                LinearProgressIndicator(value: _downloadProgress),
                                const SizedBox(height: 4),
                                Text(_downloadStatus, style: const TextStyle(fontSize: 12)),
                              ],
                            )
                          : const Text('Model not found. Tap to download.'),
                      trailing: _isLoadingVoice
                          ? null
                          : ElevatedButton.icon(
                              onPressed: _downloadVoiceModel,
                              icon: const Icon(Icons.download),
                              label: const Text('Download'),
                            ),
                    )
                  else if (isDownloaded)
                    ListTile(
                      title: const Text('Voice Status'),
                      subtitle: const Text('Downloaded'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _showDeleteFromSettings(voiceKey),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Default Speech Rate'),
            subtitle: Text('${_defaultSpeechRate.toStringAsFixed(2)}x'),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: _defaultSpeechRate,
                min: 0.1,
                max: 4.0,
                divisions: 39,
                label: '${_defaultSpeechRate.toStringAsFixed(2)}x',
                onChanged: (value) {
                  setState(() => _defaultSpeechRate = value);
                  Provider.of<TtsService>(context, listen: false).setSpeechRate(value);
                  _saveSettings();
                },
              ),
            ),
          ),
          ListTile(
            title: const Text('Default Pitch'),
            subtitle: Text(_defaultPitch.toStringAsFixed(2)),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: _defaultPitch,
                min: 0.1,
                max: 4.0,
                divisions: 39,
                label: _defaultPitch.toStringAsFixed(2),
                onChanged: (value) {
                  setState(() => _defaultPitch = value);
                  Provider.of<TtsService>(context, listen: false).setPitch(value);
                  _saveSettings();
                },
              ),
            ),
          ),
        ]),
        _buildSection('Storage', [
          ListTile(
            title: const Text('Clear Library'),
            subtitle: const Text('Remove all books from library'),
            trailing: const Icon(Icons.delete_outline, color: Colors.red),
            onTap: () => _showClearLibraryDialog(),
          ),
        ]),
        _buildSection('About', [
          const ListTile(
            title: Text('Version'),
            subtitle: Text('1.0.0'),
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
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }

  void _showClearLibraryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Library'),
        content: const Text(
            'Are you sure you want to remove all books from your library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('library');
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Library cleared')),
                );
              }
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showVoiceSelector(TtsService tts) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => VoiceSelectionModal(
        tts: tts,
        selectedVoicePack: _selectedVoicePack,
        selectedCustomVoice: _selectedCustomVoice,
        downloadedVoices: _downloadedVoices,
        onVoiceSelected: (voicePack, customVoice) {
          setState(() {
            _selectedVoicePack = voicePack ?? _selectedVoicePack;
            _selectedCustomVoice = customVoice;
          });
          if (customVoice != null) {
            tts.setCustomVoice(customVoice);
          } else if (voicePack != null) {
            tts.setVoice(voicePack);
          }
          _saveSettings();
          _checkDownloadedVoices();
        },
        onVoiceDelete: (key) async {
          final voice = tts.availableVoices.where((v) => v.key == key).firstOrNull;
          if (voice != null) {
            await tts.deleteCustomVoice(voice);
          }
          _checkDownloadedVoices();
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  void _showDeleteFromSettings(String voiceKey) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Voice Model'),
        content: const Text('Delete voice file to free storage?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final tts = Provider.of<TtsService>(context, listen: false);
              final voice = tts.availableVoices.where((v) => v.key == voiceKey).firstOrNull;
              if (voice != null) {
                await tts.deleteCustomVoice(voice);
              }
              _checkDownloadedVoices();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class VoiceSelectionModal extends StatefulWidget {
  final TtsService tts;
  final PiperVoicePack selectedVoicePack;
  final PiperVoice? selectedCustomVoice;
  final Map<String, bool> downloadedVoices;
  final Function(PiperVoicePack?, PiperVoice?)? onVoiceSelected;
  final Function(String)? onVoiceDelete;

  const VoiceSelectionModal({
    super.key,
    required this.tts,
    required this.selectedVoicePack,
    this.selectedCustomVoice,
    required this.downloadedVoices,
    this.onVoiceSelected,
    this.onVoiceDelete,
  });

  @override
  State<VoiceSelectionModal> createState() => _VoiceSelectionModalState();
}

class _VoiceSelectionModalState extends State<VoiceSelectionModal> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCustom = widget.tts.availableVoices.where((v) =>
        v.key.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        v.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        v.language.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search voices...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  if (filteredCustom.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text('HuggingFace Voices', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    ...filteredCustom.map((voice) {
                      final isDownloaded = widget.downloadedVoices[voice.key] ?? false;
                      return ListTile(
                        title: Text(voice.key),
                        subtitle: Text('${voice.language} - ${voice.quality} ${isDownloaded ? "(Downloaded)" : ""}'),
                        leading: Icon(
                          isDownloaded ? Icons.check_circle : Icons.download_for_offline,
                          color: isDownloaded ? Colors.green : Colors.grey,
                        ),
                        trailing: isDownloaded
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                    onPressed: () => widget.onVoiceDelete?.call(voice.key),
                                  ),
                                  Icon(Icons.radio_button_off),
                                ],
                              )
                            : const Icon(Icons.radio_button_off),
                        onTap: () {
                          widget.onVoiceSelected?.call(null, voice);
                          Navigator.pop(context);
                        },
                      );
                    }),
                  ],
                  if (filteredCustom.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text('No voices found'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
