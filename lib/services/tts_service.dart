import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:piper_tts_plugin/piper_tts_plugin.dart';
import 'package:piper_tts_plugin/enums/piper_voice_pack.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/piper_voice.dart';

enum TtsState { idle, loading, ready, playing, paused, error }

class TtsService extends ChangeNotifier {
  final PiperTtsPlugin _tts = PiperTtsPlugin();
  final AudioPlayer _player = AudioPlayer();
  static const _audioEffectChannel = MethodChannel('com.orbitskull.luming/audio_effects');
  
  TtsState _state = TtsState.idle;
  bool _isEngineLoaded = false;
  String? _currentText;
  double _speechRate = 1.0;
  double _pitch = 1.0;
  int _sampleRate = 22050; // Default Piper sample rate
  
  // Legacy support for PiperVoicePack
  PiperVoicePack _selectedVoicePack = PiperVoicePack.norman;
  // New support for dynamic PiperVoice
  PiperVoice? _selectedCustomVoice;
  List<PiperVoice> _availableVoices = [];

  String? _errorMessage;
  final List<String> _tempFiles = [];

  List<String> _chunks = [];
  List<int> _paragraphStartIndices = [];
  int _chunkIndex = 0;
  VoidCallback? onChapterFinished;

  TtsState get state => _state;
  double get speechRate => _speechRate;
  double get pitch => _pitch;
  PiperVoicePack get selectedVoice => _selectedVoicePack;
  PiperVoice? get selectedCustomVoice => _selectedCustomVoice;
  List<PiperVoice> get availableVoices => _availableVoices;
  
  bool get isPlaying => _state == TtsState.playing;
  bool get isPaused => _state == TtsState.paused;
  String? get errorMessage => _errorMessage;
  AudioPlayer get player => _player;
  int get currentChunkIndex => _chunkIndex;
  int get totalChunks => _chunks.length;
  String? get currentChunkText => _chunks.isNotEmpty && _chunkIndex < _chunks.length ? _chunks[_chunkIndex] : null;

  TtsService() {
    _loadSettings();
    _initPlayer();
    fetchVoices();
  }

  void _initPlayer() {
    _player.playerStateStream.listen((playerState) {
      // ONLY trigger completion if we are in the 'playing' state and it finishes.
      // This prevents 'idle' or 'completed' states from other sources triggering it.
      if (playerState.processingState == ProcessingState.completed && _state == TtsState.playing) {
        _onPlaybackCompleted();
      }
    });
  }

  Future<void> _onPlaybackCompleted() async {
    // Safety check to ensure we don't advance if the list was cleared
    if (_chunks.isEmpty) return;

    if (_chunkIndex < _chunks.length - 1) {
      // Reduced delay between sentences for a more natural flow
      await Future.delayed(const Duration(milliseconds: 150));
      // Re-check state after delay
      if (_chunks.isNotEmpty && (_state == TtsState.playing || _state == TtsState.loading)) { 
        _chunkIndex++;
        await _synthesizeAndPlayChunk(_chunkIndex);
      }
    } else {
      debugPrint('TTS: Finished all ${_chunks.length} chunks. Triggering next chapter.');
      _state = TtsState.ready;
      _chunks = [];
      _chunkIndex = 0;
      notifyListeners();

      // Added callback for completion to trigger next chapter
      if (onChapterFinished != null) {
        onChapterFinished!();
      }
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _speechRate = prefs.getDouble('defaultSpeechRate') ?? 1.0;
    _pitch = prefs.getDouble('defaultPitch') ?? 1.0;
    
    final customVoiceKey = prefs.getString('selectedCustomVoiceKey');
    if (customVoiceKey != null) {
      // Create a temporary PiperVoice placeholder so initialize() can work 
      // immediately before fetchVoices() returns the full list from HF.
      final modelPath = prefs.getString("piper_voice_custom_${customVoiceKey}_model");
      final configPath = prefs.getString("piper_voice_custom_${customVoiceKey}_config");
      
      if (modelPath != null && configPath != null) {
        _selectedCustomVoice = PiperVoice(
          key: customVoiceKey,
          name: customVoiceKey.split('-').last,
          language: customVoiceKey.split('-').first,
          country: "",
          quality: "",
          onnxPath: "", // Not needed for local loading
          configPath: "",
        );
        debugPrint('TTS: Pre-loaded voice placeholder for $customVoiceKey');
        // Initializing immediately with the stored paths
        initialize();
      }
    }

    final voiceIndex = prefs.getInt('selectedVoice') ?? PiperVoicePack.norman.index;
    _selectedVoicePack = PiperVoicePack.values[voiceIndex.clamp(0, PiperVoicePack.values.length - 1)];
  }

  bool _isFetchingVoices = false;
  bool get isFetchingVoices => _isFetchingVoices;

  Future<void> fetchVoices() async {
    if (_isFetchingVoices) return;
    _isFetchingVoices = true;
    notifyListeners();
    
    try {
      final response = await http.get(Uri.parse('https://huggingface.co/rhasspy/piper-voices/raw/main/voices.json'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<PiperVoice> voices = [];
        data.forEach((key, value) {
          voices.add(PiperVoice.fromJson(key, value));
        });
        // Sort voices by key
        voices.sort((a, b) => a.key.compareTo(b.key));
        _availableVoices = voices;
        
        final prefs = await SharedPreferences.getInstance();
        final customVoiceKey = prefs.getString('selectedCustomVoiceKey');
        if (customVoiceKey != null) {
          try {
            _selectedCustomVoice = _availableVoices.firstWhere(
              (v) => v.key == customVoiceKey,
            );
            debugPrint('TTS: Restored selected voice: ${_selectedCustomVoice?.key}');
            // Automatically initialize if we found the voice
            initialize();
          } catch (_) {
            _selectedCustomVoice = _availableVoices.isNotEmpty ? _availableVoices.first : null;
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching voices: $e');
    } finally {
      _isFetchingVoices = false;
      notifyListeners();
    }
  }

  Future<void> setCustomVoice(PiperVoice voice) async {
    _selectedCustomVoice = voice;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedCustomVoiceKey', voice.key);
    _state = TtsState.idle;
    notifyListeners();
    await initialize();
  }

  void setSpeechRate(double rate) {
    _speechRate = rate.clamp(0.1, 4.0);
    // If we're playing, update the player speed immediately with correction
    if (_state == TtsState.playing || _state == TtsState.paused) {
      double speedCorrection = _sampleRate / 22050.0;
      _player.setSpeed(_speechRate * speedCorrection);
    }
    notifyListeners();
  }

  void setPitch(double pitch) {
    _pitch = pitch.clamp(0.1, 4.0);
    // If we're playing, update the player pitch immediately
    if (_state == TtsState.playing || _state == TtsState.paused) {
      _player.setPitch(_pitch);
    }
    notifyListeners();
  }

  Future<void> setVoice(PiperVoicePack voice) async {
    _selectedVoicePack = voice;
    _selectedCustomVoice = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selectedCustomVoiceKey');
    _state = TtsState.idle;
    notifyListeners();
    await initialize();
  }

  Future<void> initialize() async {
    if (_isEngineLoaded && _state != TtsState.error) {
      _state = TtsState.ready;
      return;
    }
    
    if (_state == TtsState.loading) return;
    
    _state = TtsState.loading;
    _isEngineLoaded = false;
    _errorMessage = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (_selectedCustomVoice != null) {
        final modelPath = prefs.getString(_selectedCustomVoice!.modelPrefKey);
        final configPath = prefs.getString(_selectedCustomVoice!.configPrefKey);
        
        if (modelPath != null && configPath != null && File(modelPath).existsSync() && File(configPath).existsSync()) {
          // Extract sample rate and speaker info from config if possible
          try {
            final configContent = await File(configPath).readAsString();
            final configJson = json.decode(configContent);
            _sampleRate = configJson['audio']?['sample_rate'] ?? 22050;
            
            // Check for multi-speaker model
            if (configJson['num_speakers'] != null && (configJson['num_speakers'] as int) > 1) {
              debugPrint('TTS: Multi-speaker model detected. Total speakers: ${configJson['num_speakers']}. Using speaker 0.');
            }
            
            debugPrint('TTS: Detected sample rate: $_sampleRate');
          } catch (e) {
            _sampleRate = 22050;
            debugPrint('TTS: Could not parse config for details, using defaults');
          }

          await _tts.loadViaPath(modelPath: modelPath, configPath: configPath);
          _isEngineLoaded = true;
          _state = TtsState.ready;
        } else {
          throw Exception('Voice model not downloaded');
        }
      } else {
        await _tts.loadViaVoicePack(_selectedVoicePack);
        _sampleRate = 22050; // PiperVoicePack defaults
        _isEngineLoaded = true;
        _state = TtsState.ready;
      }
    } catch (e) {
      debugPrint('TTS: Initialization error: $e');
      _errorMessage = 'Voice model not loaded. Go to Settings > TTS to download a voice model first.';
      _state = TtsState.error;
      _isEngineLoaded = false;
    }
    notifyListeners();
  }

  Future<void> downloadCustomVoice(PiperVoice voice, Function(double) onProgress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uuidGen = const Uuid();
      final uniqueId = uuidGen.v4().replaceAll("-", "_");

      final modelPath = await _downloadWithProgress(
        voice.modelUrl, 
        "${voice.key}_${uniqueId}_model.onnx",
        (p) => onProgress(p * 0.8)
      );

      final configPath = await _downloadWithProgress(
        voice.configUrl, 
        "${voice.key}_${uniqueId}_config.json",
        (p) => onProgress(0.8 + p * 0.2)
      );

      await prefs.setString(voice.modelPrefKey, modelPath);
      await prefs.setString(voice.configPrefKey, configPath);
      
      await _tts.loadViaPath(modelPath: modelPath, configPath: configPath);
      _state = TtsState.ready;
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> downloadVoice(PiperVoicePack pack, Function(double) onProgress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uuidGen = const Uuid();
      final uniqueId = uuidGen.v4().replaceAll("-", "_");

      final modelPath = await _downloadWithProgress(
        pack.modelUrl, 
        "${pack.name}_piper_voice_model_${uniqueId}_model.onnx",
        (p) => onProgress(p * 0.8) // Model is usually bigger, 80% of total
      );

      final jsonPath = await _downloadWithProgress(
        pack.jsonUrl, 
        "${pack.name}_piper_voice_model_${uniqueId}_config.json",
        (p) => onProgress(0.8 + p * 0.2) // Json is 20%
      );

      await prefs.setString(pack.modelPrefKey, modelPath);
      await prefs.setString(pack.jsonPrefKey, jsonPath);
      
      // Load it immediately after download
      await _tts.loadViaVoicePack(pack);
      _state = TtsState.ready;
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<String> _downloadWithProgress(String url, String fileName, Function(double) onProgress) async {
    final dir = await getApplicationSupportDirectory();
    final file = File("${dir.path.replaceAll("\\", "/")}/$fileName");

    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    final response = await client.send(request);

    final contentLength = response.contentLength ?? 0;
    int downloaded = 0;

    final bytes = <int>[];
    await for (var chunk in response.stream) {
      bytes.addAll(chunk);
      downloaded += chunk.length;
      if (contentLength > 0) {
        onProgress(downloaded / contentLength);
      }
    }

    await file.writeAsBytes(bytes);
    return file.path;
  }

  List<String> _splitIntoChunks(String text) {
    final RegExp sentenceSplitter = RegExp(r'(?<!\b(?:Mr|Mrs|Ms|Dr|Jr|Sr|vs|Prof|St|i\.e|e\.g)\.)(?<=[.!?])\s+');
    
    final List<String> paragraphs = text.split(RegExp(r'\n+'));
    final List<String> chunks = [];
    _paragraphStartIndices = [];
    
    for (var paragraph in paragraphs) {
      paragraph = paragraph.trim();
      if (paragraph.isEmpty) continue;

      _paragraphStartIndices.add(chunks.length);
      final List<String> sentences = paragraph.split(sentenceSplitter);
      
      for (var sentence in sentences) {
        sentence = sentence.trim();
        if (sentence.isEmpty) continue;

        if (sentence.length > 400) {
          List<String> words = sentence.split(' ');
          String temp = "";
          for (var word in words) {
            if (temp.length + word.length > 350) {
              chunks.add(temp.trim());
              temp = word;
            } else {
              temp = temp.isEmpty ? word : "$temp $word";
            }
          }
          if (temp.isNotEmpty) chunks.add(temp.trim());
        } else {
          chunks.add(sentence);
        }
      }
    }
    
    return chunks;
  }

  Future<void> _synthesizeAndPlayChunk(int index) async {
    if (index >= _chunks.length) {
      debugPrint('TTS: All chunks finished');
      _state = TtsState.ready;
      notifyListeners();
      return;
    }

    // Check if we were stopped before starting synthesis
    if (_chunks.isEmpty) return;

    try {
      _chunkIndex = index;
      _state = TtsState.loading;
      notifyListeners();

      final text = _chunks[index];
      debugPrint('TTS: Synthesizing chunk $index: ${text.substring(0, text.length > 20 ? 20 : text.length)}...');
      
      final tempDir = await getTemporaryDirectory();
      final String outputPath = '${tempDir.path}/piper_part_${DateTime.now().millisecondsSinceEpoch}.wav'.replaceAll("\\", "/");
      
      debugPrint('TTS: Output path: $outputPath');
      
      await _tts.synthesizeToFile(
        text: text,
        outputPath: outputPath,
      );

      // Track words read and listening minutes
      try {
        final prefs = await SharedPreferences.getInstance();
        int wordsCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        int wr = prefs.getInt('wordsRead') ?? 0;
        await prefs.setInt('wordsRead', wr + wordsCount);
        
        // Approx 130 words per minute. Let's just track word count and we can calculate minutes in Stats.
        // Actually the StatsScreen reads 'totalListeningMinutes' directly. We add the exact fraction of a minute.
        // Since we can't store floats in Int, we can store 'totalListeningSeconds' and derive minutes.
        // But for simplicity, let's bump listening minutes by 1 every 130 words.
        int totalWords = wr + wordsCount;
        await prefs.setInt('totalListeningMinutes', totalWords ~/ 130);
        
        // Also update avgTtsSpeed
        double currentAvg = prefs.getDouble('avgTtsSpeed') ?? 1.0;
        await prefs.setDouble('avgTtsSpeed', (currentAvg + _speechRate) / 2.0);
      } catch (_) {}

      // Check again if we were stopped or if a new 'speak' call happened during synthesis
      if (_chunks.isEmpty || _chunkIndex != index) {
        debugPrint('TTS: Synthesis finished but chunk was cancelled or changed. Cleaning up.');
        try {
          final file = File(outputPath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
        return;
      }
      
      final file = File(outputPath);
      if (await file.exists()) {
        final size = await file.length();
        debugPrint('TTS: Synthesis successful, file size: $size bytes');
        if (size == 0) {
           throw Exception('Synthesized file is empty');
        }
      } else {
        throw Exception('Synthesized file does not exist at $outputPath');
      }


      _tempFiles.add(outputPath);
      
      // Keep only the last 3 temp files to save space
      if (_tempFiles.length > 3) {
        final oldFile = _tempFiles.removeAt(0);
        try {
          final fileToDelete = File(oldFile);
          if (await fileToDelete.exists()) {
            await fileToDelete.delete();
            debugPrint('TTS: Deleted old temp file: $oldFile');
          }
        } catch (e) {
          debugPrint('TTS: Error deleting temp file: $e');
        }
      }
      
      // Load the audio file
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.file(outputPath),
          tag: MediaItem(
            id: 'luming_tts_chunk',
            album: "LUMING Reader",
            title: text,
            artist: "LUMING TTS",
            artUri: Uri.parse("asset:///assets/logo.png"),
          ),
        ),
      );

      // Apply noise suppression via platform channel
      try {
        final sessionId = _player.androidAudioSessionId;
        if (sessionId != null) {
          await _audioEffectChannel.invokeMethod('applyNoiseSuppression', {'sessionId': sessionId});
        }
      } catch (e) {
        debugPrint('TTS: Failed to apply noise suppression: $e');
      }
      
      // Adjust playback speed based on user setting and sample rate correction.
      // The Piper plugin hardcodes 22050Hz in the WAV header.
      // We calculate the correction factor based on the actual sample rate from the model config.
      double speedCorrection = _sampleRate / 22050.0;
      double finalSpeed = _speechRate * speedCorrection;
      
      debugPrint('TTS: Playing chunk $index. SampleRate: $_sampleRate, HeaderRate: 22050, UserRate: $_speechRate, AppliedSpeed: $finalSpeed');
      
      await _player.setSpeed(finalSpeed);
      await _player.setPitch(_pitch);
      
      // Update state to playing BEFORE calling play so UI can react immediately
      _state = TtsState.playing;
      notifyListeners();
      
      debugPrint('TTS: Starting playback for chunk $index');
      await _player.play();
    } catch (e, stack) {
      debugPrint('TTS: Error in _synthesizeAndPlayChunk: $e');
      debugPrint('TTS: Stack trace: $stack');
      _errorMessage = 'Synthesis error: $e';
      _state = TtsState.error;
      notifyListeners();
    }
  }

  Future<void> speak(String text, {int startChunkIndex = 0}) async {
    debugPrint('TTS: speak() called with text length: ${text.length}, startChunk: $startChunkIndex');
    if (text.isEmpty) return;

    try {
      if (_state == TtsState.paused) {
        debugPrint('TTS: Resuming from pause');
        await _player.play();
        _state = TtsState.playing;
        notifyListeners();
        return;
      }

      // Stop current playback if any
      await stop();

      debugPrint('TTS: Ensuring engine is initialized...');
      await initialize();
      
      // Wait for engine to be ready with a timeout
      int retryCount = 0;
      while (_state == TtsState.loading && retryCount < 50) { // Increased timeout for slow devices
        await Future.delayed(const Duration(milliseconds: 200));
        retryCount++;
      }
      
      // Log a listening session
      try {
        final prefs = await SharedPreferences.getInstance();
        int ls = prefs.getInt('listeningSessions') ?? 0;
        await prefs.setInt('listeningSessions', ls + 1);
        
        // Update daily streak based on today's date
        final today = DateTime.now().toIso8601String().substring(0, 10);
        final lastActive = prefs.getString('lastActiveDate') ?? '';
        if (lastActive != today) {
          int streak = prefs.getInt('currentStreak') ?? 0;
          
          DateTime todayDate = DateTime.now();
          DateTime? lastDate;
          if (lastActive.isNotEmpty) {
            lastDate = DateTime.parse(lastActive);
          }
          
          if (lastDate != null && todayDate.difference(lastDate).inDays == 1) {
            streak += 1;
          } else if (lastDate == null || todayDate.difference(lastDate).inDays > 1) {
            streak = 1;
          }
          await prefs.setInt('currentStreak', streak);
          await prefs.setString('lastActiveDate', today);
        }
      } catch (_) {}
      
      debugPrint('TTS: Engine state before chunking: $_state (Loaded: $_isEngineLoaded)');

      if (_isEngineLoaded) {
        _state = TtsState.ready; // Ensure we are in ready state if loaded
        _currentText = text;
        _chunks = _splitIntoChunks(text);
        
        // Ensure start index is within bounds
        _chunkIndex = (startChunkIndex >= 0 && startChunkIndex < _chunks.length) 
            ? startChunkIndex 
            : 0;
            
        debugPrint('TTS: Split into ${_chunks.length} chunks, starting at $_chunkIndex');
        
        if (_chunks.isNotEmpty) {
          // Double check we haven't been stopped in the meantime
          if (_currentText == text) {
            await _synthesizeAndPlayChunk(_chunkIndex);
          }
        } else {
          debugPrint('TTS: No chunks to play');
          _state = TtsState.ready;
          notifyListeners();
        }
      } else {
        debugPrint('TTS: Engine FAILED to reach ready state. Current state: $_state');
        _errorMessage = "Engine initialization timed out or failed.";
        _state = TtsState.error;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('TTS: Error in speak(): $e');
      _errorMessage = e.toString();
      _state = TtsState.error;
      notifyListeners();
    }
  }

  Future<void> nextSentence() async {
    if (_chunkIndex < _chunks.length - 1) {
      await _player.stop(); // Stop current playback immediately
      _chunkIndex++;
      await _synthesizeAndPlayChunk(_chunkIndex);
    }
  }

  Future<void> previousSentence() async {
    if (_chunkIndex > 0) {
      await _player.stop();
      _chunkIndex--;
      await _synthesizeAndPlayChunk(_chunkIndex);
    }
  }

  Future<void> nextParagraph() async {
    if (_chunks.isEmpty) return;
    
    // Find the first paragraph start index that is greater than current index
    int nextParaIdx = -1;
    for (int startIndex in _paragraphStartIndices) {
      if (startIndex > _chunkIndex) {
        nextParaIdx = startIndex;
        break;
      }
    }

    if (nextParaIdx != -1) {
      await _player.stop();
      _chunkIndex = nextParaIdx;
      await _synthesizeAndPlayChunk(_chunkIndex);
    } else {
      // If no next paragraph, maybe jump to the end or stop?
      // For now, let's just stop or go to last chunk
      await stop();
    }
  }

  Future<void> previousParagraph() async {
    if (_chunks.isEmpty) return;

    // Find the paragraph that the current chunk belongs to
    int currentParaIdx = 0;
    for (int i = 0; i < _paragraphStartIndices.length; i++) {
      if (_paragraphStartIndices[i] <= _chunkIndex) {
        currentParaIdx = i;
      } else {
        break;
      }
    }

    // If we are at the start of a paragraph, go to the previous one
    // Otherwise, go to the start of the current paragraph
    int targetChunkIdx;
    if (_chunkIndex == _paragraphStartIndices[currentParaIdx] && currentParaIdx > 0) {
      targetChunkIdx = _paragraphStartIndices[currentParaIdx - 1];
    } else {
      targetChunkIdx = _paragraphStartIndices[currentParaIdx];
    }

    await _player.stop();
    _chunkIndex = targetChunkIdx;
    await _synthesizeAndPlayChunk(_chunkIndex);
  }

  Future<void> pause() async {
    if (_state == TtsState.playing) {
      await _player.pause();
      _state = TtsState.paused;
      notifyListeners();
    }
  }

  Future<void> resume() async {
    if (_state == TtsState.paused) {
      await _player.play();
      _state = TtsState.playing;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _chunks = [];
    _chunkIndex = 0;
    await _player.stop();
    try {
      await _audioEffectChannel.invokeMethod('releaseNoiseSuppression');
    } catch (_) {}
    if (_isEngineLoaded) {
      _state = TtsState.ready;
    } else {
      _state = TtsState.idle;
    }
    
    // Clean up all temp files on stop
    for (final path in _tempFiles) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    _tempFiles.clear();

    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}