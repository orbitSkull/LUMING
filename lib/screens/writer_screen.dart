import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/tts_service.dart';
import '../providers/reader_settings.dart';
import 'writer_projects_screen.dart';

class WriterScreen extends StatefulWidget {
  final WriterProject project;
  final Function(WriterProject)? onSave;
  final int startChapter;

  const WriterScreen({
    super.key,
    required this.project,
    this.onSave,
    this.startChapter = 0,
  });

  @override
  State<WriterScreen> createState() => _WriterScreenState();
}

class _WriterScreenState extends State<WriterScreen> {
  late List<Chapter> _chapters;
  int _currentChapterIndex = 0;
  final TextEditingController _contentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showUI = true;
  bool _hasUnsavedChanges = false;
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    _chapters = List.from(widget.project.chapters);
    _currentChapterIndex = widget.startChapter;
    if (_chapters.isNotEmpty && _currentChapterIndex < _chapters.length) {
      _contentController.text = _chapters[_currentChapterIndex].content;
    }
    _isEditMode = _chapters.isNotEmpty;
  }

  @override
  void dispose() {
    if (_hasUnsavedChanges) {
      _saveCurrentChapter();
    }
    _contentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _saveCurrentChapter() {
    if (_chapters.isNotEmpty && _currentChapterIndex < _chapters.length) {
      final content = _contentController.text;
      _chapters[_currentChapterIndex] = Chapter(
        id: _chapters[_currentChapterIndex].id,
        title: _chapters[_currentChapterIndex].title,
        content: content,
        order: _chapters[_currentChapterIndex].order,
      );
    }
  }

  int _countWords(String text) {
    return text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  Future<void> _saveProject() async {
    _saveCurrentChapter();
    final updatedProject = WriterProject(
      id: widget.project.id,
      title: widget.project.title,
      epubPath: widget.project.epubPath,
      chapters: _chapters,
      createdAt: widget.project.createdAt,
      updatedAt: DateTime.now(),
    );
    
    if (widget.onSave != null) {
      await widget.onSave!(updatedProject);
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project saved'), duration: Duration(seconds: 1)),
      );
      setState(() {
        _hasUnsavedChanges = false;
        _isEditMode = false;
      });
    }
  }

  void _goToChapter(int index) {
    if (index >= 0 && index < _chapters.length) {
      if (_hasUnsavedChanges) {
        _saveCurrentChapter();
      }
      setState(() {
        _currentChapterIndex = index;
        _contentController.text = _chapters[index].content;
      });
      _scrollController.jumpTo(0);
    }
  }

  void _nextChapter() {
    if (_currentChapterIndex < _chapters.length - 1) {
      _goToChapter(_currentChapterIndex + 1);
    }
  }

  void _previousChapter() {
    if (_currentChapterIndex > 0) {
      _goToChapter(_currentChapterIndex - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReaderSettings>();
    final isDark = settings.darkMode;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_hasUnsavedChanges) {
          await _saveProject();
        }
        if (context.mounted) {
          Navigator.pop(context, result);
        }
      },
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7),
        appBar: _showUI
          ? AppBar(
              title: Text(
                _chapters.isNotEmpty && _currentChapterIndex < _chapters.length
                    ? _chapters[_currentChapterIndex].title
                    : 'Writing',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(color: Colors.transparent),
                ),
              ),
              backgroundColor: isDark ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.6),
              elevation: 0,
              iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
              actions: [
                IconButton(
                  icon: Icon(
                    _isEditMode ? Icons.check : Icons.edit,
                    color: _isEditMode ? Colors.green : (_hasUnsavedChanges ? Colors.orange : null),
                  ),
                  onPressed: () {
                    if (_isEditMode) {
                      _saveProject();
                    } else {
                      setState(() => _isEditMode = true);
                    }
                  },
                  tooltip: _isEditMode ? 'Save' : 'Edit',
                ),
                IconButton(
                  icon: const Icon(Icons.text_fields_rounded),
                  onPressed: () => _showSettingsSheet(context),
                  tooltip: 'Text Settings',
                ),
                if (_chapters.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.format_list_bulleted_rounded),
                    onPressed: () => _showChapterList(context),
                    tooltip: 'Chapters',
                  ),
              ],
            )
          : null,
        body: _buildBody(settings, isDark),
        bottomNavigationBar: _showUI && _chapters.isNotEmpty ? _buildNavigationBar() : null,
      ),
    );
  }

  Widget _buildBody(ReaderSettings settings, bool isDark) {
    if (_chapters.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.edit_note, size: 64, color: Colors.teal),
            const SizedBox(height: 16),
            const Text('No chapters in this project'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _addNewChapter(),
              icon: const Icon(Icons.add),
              label: const Text('Add Chapter'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            ),
          ],
        ),
      );
    }

    final backgroundColor = isDark ? Colors.grey[900] : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final cursorColor = Colors.teal;

    if (!_isEditMode) {
      return GestureDetector(
        onTap: () {
          setState(() {
            _showUI = !_showUI;
          });
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: backgroundColor,
          height: double.infinity,
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            16,
            _showUI ? kToolbarHeight + 40 : 40,
            16,
            _showUI ? 100 : 40,
          ),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Text(
              _contentController.text,
              style: TextStyle(
                fontSize: settings.fontSize,
                height: settings.lineHeight,
                color: textColor,
                fontFamily: settings.fontFamily == 'Serif'
                    ? 'serif'
                    : settings.fontFamily == 'Mono'
                        ? 'monospace'
                        : null,
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _showUI = !_showUI;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: backgroundColor,
        height: double.infinity,
        width: double.infinity,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            16,
            _showUI ? kToolbarHeight + 40 : 40,
            16,
            _showUI ? 100 : 40,
          ),
          child: TextField(
            controller: _contentController,
            maxLines: null,
            style: TextStyle(
              fontSize: settings.fontSize,
              height: settings.lineHeight,
              color: textColor,
              fontFamily: settings.fontFamily == 'Serif'
                  ? 'serif'
                  : settings.fontFamily == 'Mono'
                      ? 'monospace'
                      : null,
            ),
            cursorColor: cursorColor,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Start writing...',
              hintStyle: TextStyle(color: textColor?.withOpacity(0.4)),
            ),
            onChanged: (val) {
              if (!_hasUnsavedChanges) {
                setState(() => _hasUnsavedChanges = true);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget? _buildNavigationBar() {
    final canGoBack = _currentChapterIndex > 0;
    final canGoForward = _currentChapterIndex < _chapters.length - 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tts = Provider.of<TtsService>(context);

    if (tts.state == TtsState.playing || tts.state == TtsState.loading || tts.state == TtsState.paused) {
      return _buildTtsFooter(isDark);
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          color: isDark ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.6),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: canGoBack ? _previousChapter : null,
                    icon: Icon(Icons.chevron_left, color: canGoBack ? (isDark ? Colors.white : Colors.black87) : Colors.grey),
                    label: Text('Previous', style: TextStyle(color: canGoBack ? (isDark ? Colors.white : Colors.black87) : Colors.grey)),
                  ),
                  Text(
                    '${_currentChapterIndex + 1} / ${_chapters.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isEditMode) _buildTtsButton(),
TextButton.icon(
                        onPressed: canGoForward ? _nextChapter : null,
                        icon: Text('Next', style: TextStyle(color: canGoForward ? (isDark ? Colors.white : Colors.black87) : Colors.grey)),
                        label: Icon(Icons.chevron_right, color: canGoForward ? (isDark ? Colors.white : Colors.black87) : Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTtsFooter(bool isDark) {
    final tts = Provider.of<TtsService>(context, listen: false);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF6C63FF).withOpacity(0.15) : const Color(0xFF6C63FF).withOpacity(0.1),
            border: Border(top: BorderSide(color: const Color(0xFF6C63FF).withOpacity(0.2))),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.first_page_rounded),
                      onPressed: () => tts.previousParagraph(),
                      color: isDark ? Colors.white70 : Colors.black87,
                      tooltip: 'Prev Paragraph',
                    ),
                    IconButton(
                      icon: const Icon(Icons.navigate_before_rounded),
                      onPressed: () => tts.previousSentence(),
                      color: isDark ? Colors.white70 : Colors.black87,
                      tooltip: 'Prev Sentence',
                    ),
                    FloatingActionButton.small(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      onPressed: () {
                        if (tts.state == TtsState.playing) {
                          tts.pause();
                        } else {
                          tts.resume();
                        }
                      },
                      child: Icon(tts.state == TtsState.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    ),
                    IconButton(
                      icon: const Icon(Icons.navigate_next_rounded),
                      onPressed: () => tts.nextSentence(),
                      color: isDark ? Colors.white70 : Colors.black87,
                      tooltip: 'Next Sentence',
                    ),
                    IconButton(
                      icon: const Icon(Icons.last_page_rounded),
                      onPressed: () => tts.nextParagraph(),
                      color: isDark ? Colors.white70 : Colors.black87,
                      tooltip: 'Next Paragraph',
                    ),
                    GestureDetector(
                      onLongPress: () => _showTtsQuickSettings(context, tts),
                      child: IconButton(
                        icon: const Icon(Icons.settings),
                        onPressed: () => _showTtsQuickSettings(context, tts),
                        tooltip: 'TTS Settings',
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
                      onPressed: () => tts.stop(),
                      tooltip: 'Stop',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTtsButton() {
    if (_isEditMode) return const SizedBox.shrink();
    return Consumer<TtsService>(
      builder: (context, tts, _) {
        return GestureDetector(
          onLongPress: () => _showTtsQuickSettings(context, tts),
          child: IconButton(
            icon: const Icon(Icons.volume_up),
            onPressed: () => _speakCurrentChapter(tts),
            tooltip: 'Read Aloud',
          ),
        );
      },
    );
  }

  void _speakCurrentChapter(TtsService tts) async {
    if (_chapters.isNotEmpty && _currentChapterIndex < _chapters.length) {
      final content = _contentController.text;
      if (content.isNotEmpty) {
        tts.speak(content);
      }
    }
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Consumer<ReaderSettings>(
        builder: (context, settings, _) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Writing Settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Text('Font Size:'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: settings.decreaseFontSize,
                  ),
                  Text('${settings.fontSize.toInt()}'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: settings.increaseFontSize,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Line Height:'),
                  const Spacer(),
                  SizedBox(
                    width: 200,
                    child: Slider(
                      value: settings.lineHeight,
                      min: 1.2,
                      max: 2.0,
                      divisions: 8,
                      label: settings.lineHeight.toStringAsFixed(1),
                      onChanged: settings.setLineHeight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Dark Mode'),
                value: settings.darkMode,
                onChanged: (_) => settings.toggleDarkMode(),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              const Text('Font Family:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Serif'),
                    selected: settings.fontFamily == 'Serif',
                    onSelected: (_) => settings.setFontFamily('Serif'),
                  ),
                  ChoiceChip(
                    label: const Text('Sans'),
                    selected: settings.fontFamily == 'Sans',
                    onSelected: (_) => settings.setFontFamily('Sans'),
                  ),
                  ChoiceChip(
                    label: const Text('Mono'),
                    selected: settings.fontFamily == 'Mono',
                    onSelected: (_) => settings.setFontFamily('Mono'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTtsQuickSettings(BuildContext context, TtsService tts) async {
    final prefs = await SharedPreferences.getInstance();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('TTS Settings', style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Speech Rate', style: TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: tts.speechRate,
                min: 0.1,
                max: 4.0,
                divisions: 39,
                label: '${tts.speechRate.toStringAsFixed(2)}x',
                onChanged: (val) {
                  tts.setSpeechRate(val);
                  setModalState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChapterList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'Chapters',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      Navigator.pop(context);
                      _addNewChapter();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _chapters.length,
                itemBuilder: (context, index) {
                  final chapter = _chapters[index];
                  final isSelected = index == _currentChapterIndex;
                  return ListTile(
                    title: Text(
                      chapter.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: isSelected,
                    onTap: () {
                      _goToChapter(index);
                      Navigator.pop(context);
                    },
                    trailing: PopupMenuButton<String>(
                      onSelected: (val) {
                        if (val == 'delete') {
                          _deleteChapter(index);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addNewChapter() {
    final chapterNumber = _chapters.length + 1;
    final newChapter = Chapter(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Chapter $chapterNumber',
      content: '',
      order: chapterNumber,
    );
    setState(() {
      _chapters.add(newChapter);
      _currentChapterIndex = _chapters.length - 1;
      _contentController.text = '';
      _isEditMode = true;
      _hasUnsavedChanges = true;
    });
  }

  void _deleteChapter(int index) {
    if (_chapters.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete the only chapter')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Chapter?'),
        content: Text('Are you sure you want to delete "${_chapters[index].title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _chapters.removeAt(index);
                if (_currentChapterIndex >= _chapters.length) {
                  _currentChapterIndex = _chapters.length - 1;
                }
                _contentController.text = _chapters[_currentChapterIndex].content;
              });
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}