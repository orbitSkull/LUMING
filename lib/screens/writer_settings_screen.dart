import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WriterSettingsScreen extends StatefulWidget {
  const WriterSettingsScreen({super.key});

  @override
  State<WriterSettingsScreen> createState() => _WriterSettingsScreenState();
}

class _WriterSettingsScreenState extends State<WriterSettingsScreen> {
  bool _typewriterMode = false;
  int _autoSaveInterval = 30;
  String _exportPreset = 'standard';
  final List<String> _customDict = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _typewriterMode = prefs.getBool('typewriterMode') ?? false;
      _autoSaveInterval = prefs.getInt('autoSaveInterval') ?? 30;
      _exportPreset = prefs.getString('exportPreset') ?? 'standard';
      _customDict.clear();
      _customDict.addAll(prefs.getStringList('customDict') ?? []);
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('typewriterMode', _typewriterMode);
    await prefs.setInt('autoSaveInterval', _autoSaveInterval);
    await prefs.setString('exportPreset', _exportPreset);
    await prefs.setStringList('customDict', _customDict);
  }

  void _showAutoSaveDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auto-Save Interval'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [15, 30, 60, 120].map((seconds) {
            return RadioListTile<int>(
              title: Text(seconds < 60 ? '$seconds seconds' : '${seconds ~/ 60} minute${seconds > 60 ? 's' : ''}'),
              value: seconds,
              groupValue: _autoSaveInterval,
              onChanged: (value) {
                setState(() => _autoSaveInterval = value!);
                _saveSettings();
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showExportPresetDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Preset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            'standard', 'kobo', 'amazon', 'custom'
          ].map((preset) {
            return RadioListTile<String>(
              title: Text(preset.toUpperCase()),
              value: preset,
              groupValue: _exportPreset,
              onChanged: (value) {
                setState(() => _exportPreset = value!);
                _saveSettings();
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _addCustomWord() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Custom Word'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter word',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final word = controller.text.trim();
              if (word.isNotEmpty) {
                setState(() => _customDict.add(word));
                _saveSettings();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Studio Settings'),
        backgroundColor: Colors.teal,
      ),
      body: ListView(
        children: [
          _buildSection('Writing Experience'),
          SwitchListTile(
            title: const Text('Typewriter Mode'),
            subtitle: const Text('Distraction-free, fullscreen writing'),
            value: _typewriterMode,
            activeColor: Colors.teal,
            onChanged: (value) {
              setState(() => _typewriterMode = value);
              _saveSettings();
            },
          ),
          ListTile(
            title: const Text('Auto-Save Interval'),
            subtitle: Text('Every $_autoSaveInterval seconds'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showAutoSaveDialog,
          ),
          const Divider(),
          _buildSection('Export'),
          ListTile(
            title: const Text('EPUB Export Preset'),
            subtitle: Text(_exportPreset.toUpperCase()),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showExportPresetDialog,
          ),
          const Divider(),
          _buildSection('Custom Dictionary'),
          ListTile(
            title: const Text('Custom Words'),
            subtitle: Text('${_customDict.length} words added'),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addCustomWord,
            ),
          ),
          if (_customDict.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _customDict.map((word) => Chip(
                  label: Text(word),
                  onDeleted: () {
                    setState(() => _customDict.remove(word));
                    _saveSettings();
                  },
                )).toList(),
              ),
            ),
          const Divider(),
          _buildSection('About'),
          const ListTile(
            title: Text('LUMING Writer'),
            subtitle: Text('Version 1.0.0'),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.teal,
        ),
      ),
    );
  }
}