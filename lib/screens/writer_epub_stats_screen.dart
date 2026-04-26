import 'dart:io';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/epub_project_service.dart';

class WriterEpubStatsScreen extends StatefulWidget {
  final EpisodeProject project;

  const WriterEpubStatsScreen({super.key, required this.project});

  @override
  State<WriterEpubStatsScreen> createState() => _WriterEpubStatsScreenState();
}

class _WriterEpubStatsScreenState extends State<WriterEpubStatsScreen> {
  int _totalWords = 0;
  int _totalChars = 0;
  int _totalCharsNoSpaces = 0;
  int _chapterCount = 0;
  int _paragraphCount = 0;
  DateTime? _lastModified;
  int? _goalWords;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (widget.project.epubPath == null) return;

    final file = File(widget.project.epubPath!);
    if (!await file.existsSync()) return;

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      int totalWords = 0;
      int totalChars = 0;
      int totalCharsNoSpaces = 0;
      int chapterCount = 0;
      int paragraphCount = 0;
      
      for (final af in archive.files) {
        if (af.name.startsWith('OEBPS/chapter') && af.name.endsWith('.xhtml')) {
          chapterCount++;
          final htmlContent = String.fromCharCodes(af.content);
          
          final bodyMatch = RegExp(r'<body>([\s\S]*)</body>', dotAll: true).firstMatch(htmlContent);
          final body = bodyMatch?.group(1) ?? '';
          
          final plainText = body.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
          
          totalChars += plainText.length;
          totalCharsNoSpaces += plainText.replaceAll(' ', '').length;
          totalWords += plainText.isEmpty ? 0 : plainText.split(RegExp(r'\s+')).length;
          
          paragraphCount += '\n'.allMatches(body).length;
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final goalStr = prefs.getString('writer_${widget.project.id}_goal');
      final goalWords = goalStr != null ? int.tryParse(goalStr) : null;

      if (mounted) {
        setState(() {
          _totalWords = totalWords;
          _totalChars = totalChars;
          _totalCharsNoSpaces = totalCharsNoSpaces;
          _chapterCount = chapterCount;
          _paragraphCount = paragraphCount;
          _lastModified = widget.project.updatedAt;
          _goalWords = goalWords;
        });
      }
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  int get _wordsWrittenToday {
    final now = DateTime.now();
    if (_lastModified == null) return 0;
    if (_lastModified!.year == now.year && 
        _lastModified!.month == now.month && 
        _lastModified!.day == now.day) {
      return _totalWords;
    }
    return 0;
  }

  int get _readingTime => (_totalWords / 250).ceil();
  int get _listenTime => (_totalWords / 150).ceil();
  int get _avgWordsPerChapter => _chapterCount > 0 ? (_totalWords / _chapterCount).round() : 0;

  double get _goalProgress {
    if (_goalWords == null || _goalWords == 0) return 0;
    return (_totalWords / _goalWords!).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.title),
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatCard('Total Word Count', '$_totalWords', 'Primary metric for writers',
                Icons.text_fields, Colors.blue),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatTile('Characters', '$_totalChars', 'with spaces', Icons.abc),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatTile('Characters', '$_totalCharsNoSpaces', 'no spaces', Icons.abc_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatTile('Chapters', '$_chapterCount', 'total', Icons.library_books),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatTile('Paragraphs', '$_paragraphCount', 'total', Icons.format_indent_increase),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatTile('Reading Time', '~$_readingTime min', '@ 250 wpm', Icons.menu_book),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatTile('Listening Time', '~$_listenTime min', '@ 150 wpm', Icons.headphones),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatTile('Words Today', '$_wordsWrittenToday', 'since midnight', Icons.today),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatTile('Avg/Chapter', '$_avgWordsPerChapter', 'words', Icons.trending_up),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              'Last Modified',
              _lastModified != null 
                  ? '${_lastModified!.day}/${_lastModified!.month}/${_lastModified!.year} ${_lastModified!.hour}:${_lastModified!.minute.toString().padLeft(2, '0')}'
                  : 'Unknown',
              'Project saves',
              Icons.update,
              Colors.grey),
            const SizedBox(height: 12),
            if (_goalWords != null && _goalWords! > 0)
              _buildGoalCard(),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _setGoal,
              icon: const Icon(Icons.flag),
              label: Text(_goalWords != null ? 'Change Goal ($_goalWords words)' : 'Set Goal'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, String subtitle, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile(String title, String value, String subtitle, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: Colors.teal, size: 24),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.teal)),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Project Goal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('${(_goalProgress * 100).toInt()}%', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _goalProgress,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation(_goalProgress >= 1 ? Colors.green : Colors.teal),
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            Text('$_totalWords / $_goalWords words', style: const TextStyle(color: Colors.grey)),
            if (_goalProgress >= 1)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Goal reached!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  void _setGoal() async {
    final controller = TextEditingController(text: _goalWords?.toString() ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Project Goal'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Target word count',
            border: OutlineInputBorder(),
            hintText: 'e.g., 50000',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final goal = int.tryParse(controller.text);
              if (goal != null && goal > 0) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('writer_${widget.project.id}_goal', goal.toString());
                setState(() => _goalWords = goal);
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}