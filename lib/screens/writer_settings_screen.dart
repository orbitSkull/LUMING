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
  int _fontStyle = 0;
  int _lineSpacing = 1;
  int _textAlign = 0;

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
      _fontStyle = prefs.getInt('writer_fontStyle') ?? 0;
      _lineSpacing = prefs.getInt('writer_lineSpacing') ?? 1;
      _textAlign = prefs.getInt('writer_textAlign') ?? 0;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('writer_autoSave', _autoSave);
    await prefs.setBool('writer_autoCapitalization', _autoCapitalization);
    await prefs.setInt('writer_fontStyle', _fontStyle);
    await prefs.setInt('writer_lineSpacing', _lineSpacing);
    await prefs.setInt('writer_textAlign', _textAlign);
  }

  String _getFontLabel(int style) {
    switch (style) { case 0: return 'Sans'; case 1: return 'Serif'; default: return 'Sans'; }
  }

  String _getSpacingLabel(int space) {
    switch (space) { case 0: return '1'; case 1: return '1.5'; case 2: return '2'; default: return '1.5'; }
  }

  String _getAlignLabel(int align) {
    switch (align) { case 0: return 'Left'; case 1: return 'Justify'; default: return 'Left'; }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReaderSettings>();
    final tts = Provider.of<TtsService>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Studio Settings'), backgroundColor: Colors.teal),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('Appearance'),
          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: const Text('Toggle dark/light theme'),
            value: settings.darkMode,
            onChanged: (value) => settings.setDarkMode(value),
            activeColor: Colors.teal,
          ),
          _optionCard('Font Size', '${settings.fontSize.toInt()}', Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.remove), onPressed: () { settings.decreaseFontSize(); _saveSettings(); }),
            Text('${settings.fontSize.toInt()}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.add), onPressed: () { settings.increaseFontSize(); _saveSettings(); }),
          ])),
          _optionCard('Font Style', _getFontLabel(_fontStyle), _chipRow([
            _chip('Sans', _fontStyle == 0, () => setState(() { _fontStyle = 0; settings.setFontFamily('Sans'); _saveSettings(); })),
            _chip('Serif', _fontStyle == 1, () => setState(() { _fontStyle = 1; settings.setFontFamily('Serif'); _saveSettings(); })),
          ])),
          _optionCard('Line Spacing', _getSpacingLabel(_lineSpacing), _chipRow([
            _chip('1', _lineSpacing == 0, () => setState(() { _lineSpacing = 0; settings.setLineHeight(1.0); _saveSettings(); })),
            _chip('1.5', _lineSpacing == 1, () => setState(() { _lineSpacing = 1; settings.setLineHeight(1.5); _saveSettings(); })),
            _chip('2', _lineSpacing == 2, () => setState(() { _lineSpacing = 2; settings.setLineHeight(2.0); _saveSettings(); })),
          ])),
          _optionCard('Text Alignment', _getAlignLabel(_textAlign), _chipRow([
            _chip('Left', _textAlign == 0, () => setState(() { _textAlign = 0; _saveSettings(); })),
            _chip('Justify', _textAlign == 1, () => setState(() { _textAlign = 1; _saveSettings(); })),
          ])),
          _sectionHeader('Writing Behavior'),
          _switchTile('Auto-Save', _autoSave, (v) => setState(() { _autoSave = v; _saveSettings(); })),
          _switchTile('Auto-Capitalization', _autoCapitalization, (v) => setState(() { _autoCapitalization = v; _saveSettings(); })),
          _switchTile('Show Word Count', settings.showWordCount, (v) => setState(() { settings.setShowWordCount(v); _saveSettings(); })),
          _switchTile('Focus Mode', settings.focusMode, (v) => setState(() { settings.setFocusMode(v); _saveSettings(); })),
          _switchTile('Typewriter Scrolling', settings.typewriterScrolling, (v) => setState(() { settings.setTypewriterScrolling(v); _saveSettings(); })),
          _sectionHeader('TTS Settings'),
          _sliderTile('Reading Speed', '${tts.speechRate.toStringAsFixed(2)}x', tts.speechRate, 0.1, 4.0, tts.setSpeechRate),
          _sliderTile('Voice Pitch', tts.pitch.toStringAsFixed(1), tts.pitch, 0.5, 2.0, tts.setPitch),
          _sliderTile('Pause at Period', '${tts.sentencePause}ms', tts.sentencePause.toDouble(), 0, 2000, (v) => tts.setSentencePause(v.toInt())),
          _switchTile('Highlight Spoken Word', tts.highlightSpokenWord, tts.setHighlightSpokenWord),
          _switchTile('Continuous Play', tts.continuousPlay, tts.setContinuousPlay),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(padding: const EdgeInsets.only(bottom: 12, top: 16), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)));

  Widget _optionCard(String title, String value, Widget trailing) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(title: Text(title), trailing: trailing));

  Widget _switchTile(String title, bool value, Function(bool) onChanged) => Card(margin: const EdgeInsets.only(bottom: 8), child: SwitchListTile(title: Text(title), value: value, onChanged: onChanged, activeColor: Colors.teal));

  Widget _sliderTile(String title, String value, double current, double min, double max, Function(double) onChanged) => Card(margin: const EdgeInsets.only(bottom: 8), child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    Row(children: [Text(title), const Spacer(), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))]),
    Slider(value: current, min: min, max: max, activeColor: Colors.teal, onChanged: onChanged),
  ])));

  Widget _chipRow(List<Widget> children) => SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: children));

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(label: Text(label), selected: selected, onSelected: (_) => onTap(), selectedColor: Colors.teal[200]));
}