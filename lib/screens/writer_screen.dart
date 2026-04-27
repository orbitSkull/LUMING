import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/storage_service.dart';
import 'dart:convert';
import '../services/tts_service.dart';
import '../providers/reader_settings.dart';
import '../services/epub_project_service.dart';
import '../models/piper_voice.dart';
import '../models/episode_project.dart';
import 'settings_screen.dart';

class WriterScreen extends StatefulWidget {
  final EpisodeProject project;
  final Function(EpisodeProject)? onSave;
  final int startChapter;

  const WriterScreen({super.key, required this.project, this.onSave, this.startChapter = 0});

  @override
  State<WriterScreen> createState() => _WriterScreenState();
}

class _WriterScreenState extends State<WriterScreen> {
  final EpubProjectService _service = EpubProjectService();
  List<ChapterData> _chapters = [];
  int _currentChapterIndex = 0;
  final TextEditingController _contentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _showUI = true;
  bool _hasUnsavedChanges = false;
  bool _isEditMode = false;
  bool _isLoading = true;
  int _wordCount = 0;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  // ignore: unused_field
  String _lastRecognizedText = '';

  @override
  void initState() {
    super.initState();
    _loadChapters();
  }

  Future<void> _loadChapters() async {
    if (widget.project.epubPath != null) {
      try {
        _chapters = await _service.getChapters(widget.project.epubPath!);
      } catch (e) {
        debugPrint('Error loading chapters: $e');
      }
    }
    _currentChapterIndex = widget.startChapter;
    if (_chapters.isNotEmpty && _currentChapterIndex < _chapters.length) {
      _contentController.text = _stripHtml(_chapters[_currentChapterIndex].content);
    }
    _updateWordCount();
    setState(() {
      _isLoading = false;
      _isEditMode = _chapters.isEmpty;
    });
  }

  String _stripHtml(String html) {
    // Remove script and style tags
    String content = html.replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', dotAll: true), '');
    // Replace block tags with newlines
    content = content.replaceAll(RegExp(r'<(p|div|li|h[1-6])[^>]*>', caseSensitive: false), '\n');
    content = content.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    // Remove all other tags
    content = content.replaceAll(RegExp(r'<[^>]*>'), '');
    // Decode entities
    content = content
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    
    // Clean up multiple newlines while preserving single ones
    content = content.replaceAll(RegExp(r'\n\s*\n+'), '\n\n').trim();
    return content;
  }

  String _wrapInHtml(String text) {
    final paragraphs = text.split('\n');
    final buffer = StringBuffer();
    for (var p in paragraphs) {
      if (p.trim().isNotEmpty) {
        buffer.write('<p>${p.trim().replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}</p>\n');
      }
    }
    return buffer.toString();
  }

  void _updateWordCount() {
    final text = _contentController.text;
    setState(() {
      if (text.trim().isEmpty) {
        _wordCount = 0;
      } else {
        _wordCount = text.trim().split(RegExp(r'\s+')).length;
      }
    });
  }

  @override
  void dispose() {
    if (_hasUnsavedChanges) {
      _saveCurrentChapter();
    }
    _contentController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _saveCurrentChapter() async {
    if (_chapters.isNotEmpty && _currentChapterIndex < _chapters.length && widget.project.epubPath != null) {
      final htmlContent = _wrapInHtml(_contentController.text);
      _chapters[_currentChapterIndex] = ChapterData(
        id: _chapters[_currentChapterIndex].id,
        title: _chapters[_currentChapterIndex].title,
        content: htmlContent,
        order: _chapters[_currentChapterIndex].order,
      );
      await _service.saveChapters(widget.project.epubPath!, _chapters);
    }
  }

  Future<void> _saveProject() async {
    await _saveCurrentChapter();
    final updated = EpisodeProject(
      id: widget.project.id,
      title: widget.project.title,
      epubPath: widget.project.epubPath,
      coverPath: widget.project.coverPath,
      createdAt: widget.project.createdAt,
      updatedAt: DateTime.now(),
      bookmarks: widget.project.bookmarks,
    );
    if (widget.onSave != null) {
      await widget.onSave!(updated);
    }
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
    );
    setState(() {
      _hasUnsavedChanges = false;
      _isEditMode = false;
    });
  }

  void _goToChapter(int index) {
    if (index >= 0 && index < _chapters.length) {
      if (_hasUnsavedChanges) {
        _saveCurrentChapter();
        _hasUnsavedChanges = false;
      }
      setState(() {
        _currentChapterIndex = index;
        _contentController.text = _stripHtml(_chapters[index].content);
        _updateWordCount();
      });
      _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReaderSettings>();
    final isDark = settings.darkMode;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final hideUI = settings.focusMode && _isEditMode && !_showUI;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_hasUnsavedChanges) {
          await _saveProject();
        }
        if (mounted) {
          Navigator.pop(context, result);
        }
      },
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7),
        appBar: _showUI && !hideUI ? AppBar(
          title: Text(
            _chapters.isNotEmpty && _currentChapterIndex < _chapters.length
                ? _chapters[_currentChapterIndex].title
                : 'Writing',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87),
          ),
          flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(color: Colors.transparent))),
          backgroundColor: isDark ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.6),
          elevation: 0,
          iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
          actions: [
            IconButton(
              icon: Icon(_isEditMode ? Icons.check : Icons.edit, color: _isEditMode ? Colors.green : (_hasUnsavedChanges ? Colors.orange : null)),
              onPressed: () {
                if (_isEditMode) {
                  _saveProject();
                } else {
                  setState(() => _isEditMode = true);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.abc),
              onPressed: () => _showSettingsSheet(context),
            ),
            if (_chapters.isNotEmpty) IconButton(icon: const Icon(Icons.format_list_bulleted_rounded), onPressed: () => _showChapterList(context)),
          ],
        ) : null,
        body: _buildBody(settings, isDark),
        bottomNavigationBar: _showUI && !hideUI && _chapters.isNotEmpty ? _buildNavigationBar() : null,
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
            const Text('No chapters found'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _addNewChapter,
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

    return Consumer<TtsService>(
      builder: (context, tts, _) {
        final currentText = tts.currentChunkText;
        final isPlaying = tts.state == TtsState.playing || tts.state == TtsState.paused;
        
        TextSpan? highlightSpan;
        if (isPlaying && currentText != null) {
          final content = _contentController.text;
          final offset = tts.currentChunkOffset;
          
          if (offset < content.length) {
            // We find the exact piece of text. Since we split the chunks from the plain text 
            // of the content controller, the offset should match.
            // However, chunks are trimmed, so we find the index of currentText starting from offset.
            int startIdx = content.indexOf(currentText, offset);
            if (startIdx != -1) {
              highlightSpan = TextSpan(
                children: [
                  TextSpan(text: content.substring(0, startIdx)),
                  TextSpan(
                    text: content.substring(startIdx, startIdx + currentText.length),
                    style: TextStyle(backgroundColor: isDark ? Colors.teal.withOpacity(0.4) : Colors.teal.withOpacity(0.2)),
                  ),
                  TextSpan(text: content.substring(startIdx + currentText.length)),
                ],
              );
            }
          }
        }

        if (!_isEditMode) {
          return GestureDetector(
            onTap: () => setState(() => _showUI = !_showUI),
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: backgroundColor,
              height: double.infinity,
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(16, _showUI ? kToolbarHeight + 40 : 40, 16, _showUI ? 100 : 40),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: highlightSpan != null 
                  ? RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: settings.fontSize, height: settings.lineHeight, color: textColor),
                        children: [highlightSpan],
                      ),
                    )
                  : Text(
                      _contentController.text,
                      style: TextStyle(fontSize: settings.fontSize, height: settings.lineHeight, color: textColor),
                    ),
              ),
            ),
          );
        }

        return GestureDetector(
          onTap: () => setState(() => _showUI = !_showUI),
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              Container(
                color: backgroundColor,
                height: double.infinity,
                width: double.infinity,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(16, _showUI ? kToolbarHeight + 40 : 40, 16, _showUI ? 100 : 40),
                  child: TextField(
                    controller: _contentController,
                    maxLines: null,
                    style: TextStyle(fontSize: settings.fontSize, height: settings.lineHeight, color: textColor),
                    cursorColor: Colors.teal,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Start writing...',
                      hintStyle: TextStyle(color: textColor.withOpacity(0.4)),
                    ),
                    focusNode: _focusNode,
                    onChanged: (val) {
                      if (!_hasUnsavedChanges) {
                        setState(() => _hasUnsavedChanges = true);
                      }
                      _updateWordCount();
                    },
                  ),
                ),
              ),
              if (settings.showWordCount && _isEditMode)
                Positioned(
                  top: _showUI ? kToolbarHeight + 50 : 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '$_wordCount words',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
                    onPressed: canGoBack ? () => _goToChapter(_currentChapterIndex - 1) : null,
                    icon: Icon(Icons.chevron_left, color: canGoBack ? (isDark ? Colors.white : Colors.black87) : Colors.grey),
                    label: Text('Previous', style: TextStyle(color: canGoBack ? (isDark ? Colors.white : Colors.black87) : Colors.grey)),
                  ),
                  Flexible(
                    child: Text(
                      '${_currentChapterIndex + 1} / ${_chapters.length}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_isEditMode) _buildTtsButton(),
                      TextButton.icon(
                        onPressed: canGoForward ? () => _goToChapter(_currentChapterIndex + 1) : null,
                        icon: Icon(Icons.chevron_right, color: canGoForward ? (isDark ? Colors.white : Colors.black87) : Colors.grey),
                        label: Text('Next', style: TextStyle(color: canGoForward ? (isDark ? Colors.white : Colors.black87) : Colors.grey)),
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
                    IconButton(icon: const Icon(Icons.first_page_rounded), onPressed: () => tts.previousParagraph(), color: isDark ? Colors.white70 : Colors.black87),
                    IconButton(icon: const Icon(Icons.navigate_before_rounded), onPressed: () => tts.previousSentence(), color: isDark ? Colors.white70 : Colors.black87),
                    FloatingActionButton.small(
                      backgroundColor: const Color(0xFF6C63FF),
                      onPressed: () {
                        if (tts.state == TtsState.playing) {
                          tts.pause();
                        } else {
                          tts.resume();
                        }
                      },
                      child: Icon(tts.state == TtsState.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    ),
                    IconButton(icon: const Icon(Icons.navigate_next_rounded), onPressed: () => tts.nextSentence(), color: isDark ? Colors.white70 : Colors.black87),
                    IconButton(icon: const Icon(Icons.last_page_rounded), onPressed: () => tts.nextParagraph(), color: isDark ? Colors.white70 : Colors.black87),
                    GestureDetector(
                      onLongPress: () => _showTtsQuickSettings(context, tts),
                      child: IconButton(icon: const Icon(Icons.settings), onPressed: () => _showTtsQuickSettings(context, tts)),
                    ),
                    IconButton(icon: const Icon(Icons.stop_circle_outlined, color: Colors.red), onPressed: () => tts.stop()),
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
    return Consumer<TtsService>(
      builder: (context, tts, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isEditMode)
              GestureDetector(
                onLongPress: () => _showTtsQuickSettings(context, tts),
                child: IconButton(
                  icon: const Icon(Icons.volume_up),
                  onPressed: () => _speakCurrentChapter(tts),
                ),
              ),
          ],
        );
      },
    );
  }

  // ignore: unused_element
  void _toggleListening() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (val) {
          debugPrint('Speech error: $val');
          setState(() => _isListening = false);
        },
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              if (val.finalResult) {
                final currentText = _contentController.text;
                final selection = _contentController.selection;
                String newText;
                if (selection.start >= 0) {
                  newText = currentText.replaceRange(selection.start, selection.end, val.recognizedWords);
                } else {
                  newText = currentText + (currentText.isEmpty ? "" : " ") + val.recognizedWords;
                }
                _contentController.text = newText;
                _contentController.selection = TextSelection.collapsed(offset: selection.start + val.recognizedWords.length);
                _updateWordCount();
                _hasUnsavedChanges = true;
              }
            });
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Consumer<ReaderSettings>(
        builder: (context, settings, _) => SafeArea(
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Writing Settings', style: Theme.of(context).textTheme.titleLarge),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 24),
              Row(
                children: [
                  const Text('Font Size:'),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.remove), onPressed: settings.decreaseFontSize),
                  Text('${settings.fontSize.toInt()}'),
                  IconButton(icon: const Icon(Icons.add), onPressed: settings.increaseFontSize),
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
              SwitchListTile(
                title: const Text('Show Word Count'),
                value: settings.showWordCount,
                onChanged: settings.setShowWordCount,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('Focus Mode'),
                subtitle: const Text('Hides non-essential UI while writing'),
                value: settings.focusMode,
                onChanged: settings.setFocusMode,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('Typewriter Scrolling'),
                subtitle: const Text('Keep the cursor in the center of the screen'),
                value: settings.typewriterScrolling,
                onChanged: settings.setTypewriterScrolling,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        ),
      ),
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

  double _downloadProgress = 0;
  bool _isLoadingVoice = false;
  String _downloadStatus = '';

  void _showTtsQuickSettings(BuildContext context, TtsService tts) async {
    final storage = StorageService();
    final settingsFile = File(storage.settingsFile);
    Map<String, dynamic> settings = {};
    if (settingsFile.existsSync()) {
      try {
        settings = jsonDecode(settingsFile.readAsStringSync());
      } catch (_) {}
    }
    
    final prefs = await SharedPreferences.getInstance();
    final List<PiperVoice> downloadedVoices = [];
    
    for (var voice in tts.availableVoices) {
      final modelPath = settings[voice.modelPrefKey] ?? prefs.getString(voice.modelPrefKey);
      if (modelPath != null && File(modelPath).existsSync()) {
        downloadedVoices.add(voice);
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('TTS Quick Settings', style: Theme.of(context).textTheme.titleLarge),
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
              const Text('Pitch', style: TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: tts.pitch,
                min: 0.1,
                max: 4.0,
                divisions: 39,
                label: tts.pitch.toStringAsFixed(2),
                onChanged: (val) {
                  tts.setPitch(val);
                  setModalState(() {});
                },
              ),
              const SizedBox(height: 16),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Voice Selection', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () => _showVoiceSelector(context, tts),
                    child: const Text('All Voices'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (downloadedVoices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('No other voices downloaded', style: TextStyle(color: Colors.grey, fontSize: 12)),
                )
              else
                SizedBox(
                  height: 150,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: downloadedVoices.length,
                    itemBuilder: (context, index) {
                      final voice = downloadedVoices[index];
                      final isSelected = tts.selectedCustomVoice?.key == voice.key;
                      return ListTile(
                        title: Text(voice.name),
                        subtitle: Text(voice.key, style: const TextStyle(fontSize: 10)),
                        trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                        dense: true,
                        onTap: () {
                          tts.setCustomVoice(voice);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              if (tts.selectedCustomVoice != null) ...[
                const SizedBox(height: 16),
                _buildDownloadSection(context, tts, setModalState),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadSection(BuildContext context, TtsService tts, StateSetter setModalState) {
    final voice = tts.selectedCustomVoice!;
    return FutureBuilder<bool>(
      future: _isVoiceDownloaded(voice),
      builder: (context, snapshot) {
        final isDownloaded = snapshot.data ?? false;
        if (isDownloaded) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Download Selected Voice'),
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
                  : Text('Download ${voice.name} model to use it.'),
              trailing: _isLoadingVoice
                  ? null
                  : ElevatedButton.icon(
                      onPressed: () => _downloadVoiceModel(context, tts, setModalState),
                      icon: const Icon(Icons.download),
                      label: const Text('Download'),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _isVoiceDownloaded(PiperVoice voice) async {
    final prefs = await SharedPreferences.getInstance();
    final modelPath = prefs.getString(voice.modelPrefKey);
    final configPath = prefs.getString(voice.configPrefKey);
    return modelPath != null && File(modelPath).existsSync() &&
           configPath != null && File(configPath).existsSync();
  }

  Future<void> _downloadVoiceModel(BuildContext context, TtsService tts, StateSetter setModalState) async {
    setModalState(() {
      _isLoadingVoice = true;
      _downloadProgress = 0;
      _downloadStatus = 'Starting download...';
    });

    try {
      if (tts.selectedCustomVoice != null) {
        await tts.downloadCustomVoice(tts.selectedCustomVoice!, (progress) {
          setModalState(() {
            _downloadProgress = progress;
            _downloadStatus = 'Downloading: ${(progress * 100).toStringAsFixed(0)}%';
          });
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tts.selectedCustomVoice?.name ?? 'Voice'} downloaded successfully!')),
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
        setModalState(() {
          _isLoadingVoice = false;
          _downloadStatus = '';
        });
      }
    }
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
                  Text('Chapters', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.add), onPressed: () { Navigator.pop(context); _addNewChapter(); }),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
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
                    leading: CircleAvatar(
                      backgroundColor: isSelected ? Colors.teal : Colors.grey[300],
                      radius: 16,
                      child: Text('${index + 1}', style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black87)),
                    ),
                    title: Text(chapter.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    selected: isSelected,
                    onTap: () { _goToChapter(index); Navigator.pop(context); },
                    trailing: PopupMenuButton<String>(
                      onSelected: (val) {
                        if (val == 'delete') { _deleteChapter(index); }
                        else if (val == 'rename') { _showRenameChapterDialog(index); }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'rename', child: Text('Rename')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
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
    if (widget.project.epubPath != null) {
      _chapters.add(ChapterData(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'Chapter $chapterNumber',
        content: '',
        order: chapterNumber,
      ));
      _service.saveChapters(widget.project.epubPath!, _chapters);
    }
    setState(() {
      _currentChapterIndex = _chapters.length - 1;
      _contentController.text = '';
      _isEditMode = true;
      _hasUnsavedChanges = true;
    });
  }

  void _showRenameChapterDialog(int index) {
    if (index < 0 || index >= _chapters.length) return;
    final controller = TextEditingController(text: _chapters[index].title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Chapter'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Chapter Title', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty && widget.project.epubPath != null) {
                _chapters[index] = ChapterData(id: _chapters[index].id, title: controller.text, content: _chapters[index].content, order: _chapters[index].order);
                await _service.saveChapters(widget.project.epubPath!, _chapters);
                if (mounted) {
                  setState(() => _hasUnsavedChanges = true);
                  Navigator.pop(ctx);
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteChapter(int index) {
    if (_chapters.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete the only chapter')));
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Chapter?'),
        content: Text('Delete "${_chapters[index].title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              setState(() {
                _chapters.removeAt(index);
                if (_currentChapterIndex >= _chapters.length) {
                  _currentChapterIndex = _chapters.length - 1;
                }
                if (_chapters.isNotEmpty) {
                  _contentController.text = _stripHtml(_chapters[_currentChapterIndex].content);
                }
                _hasUnsavedChanges = true;
              });
              if (widget.project.epubPath != null) {
                _service.saveChapters(widget.project.epubPath!, _chapters);
              }
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