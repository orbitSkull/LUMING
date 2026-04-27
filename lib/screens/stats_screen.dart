import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/storage_service.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  int _totalBooks = 0;
  int _booksCompleted = 0;
  int _chaptersRead = 0;
  int _totalListeningMinutes = 0;
  int _currentStreak = 0;
  double _avgTtsSpeed = 1.0;
  int _listeningSessions = 0;

  // Daily and weekly stats
  int _todayChaptersRead = 0;
  int _todayListeningMinutes = 0;
  final List<int> _weeklyReadingMinutes = List.filled(7, 0);
  final List<int> _weeklyListeningMinutes = List.filled(7, 0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final storage = StorageService();
    
    // Load Overall Stats
    final statsFile = File(storage.overallStatsFile);
    Map<String, dynamic> stats = {};
    if (statsFile.existsSync()) {
      try {
        stats = jsonDecode(statsFile.readAsStringSync());
      } catch (_) {}
    }

    // Load Today Stats
    final todayFile = File(storage.getDailyStatsFile(DateTime.now()));
    Map<String, dynamic> todayStats = {};
    if (todayFile.existsSync()) {
      try {
        todayStats = jsonDecode(todayFile.readAsStringSync());
      } catch (_) {}
    }

    // Load Weekly Stats
    final now = DateTime.now();
    final List<int> weeklyReading = List.filled(7, 0);
    final List<int> weeklyListening = List.filled(7, 0);
    
    for (int i = 0; i < 7; i++) {
      final date = now.subtract(Duration(days: i));
      final file = File(storage.getDailyStatsFile(date));
      if (file.existsSync()) {
        try {
          final data = jsonDecode(file.readAsStringSync());
          int reading = (data['chaptersRead'] ?? 0) * 5;
          int listening = data['listeningMinutes'] ?? 0;
          int weekday = date.weekday; // 1 (Mon) to 7 (Sun)
          weeklyReading[weekday - 1] = reading;
          weeklyListening[weekday - 1] = listening;
        } catch (_) {}
      }
    }

    final prefs = await SharedPreferences.getInstance();
    
    setState(() {
      _totalBooks = stats['totalBooks'] ?? prefs.getInt('totalBooks') ?? 0;
      _booksCompleted = stats['booksCompleted'] ?? prefs.getInt('booksCompleted') ?? 0;
      _chaptersRead = stats['chaptersRead'] ?? prefs.getInt('chaptersRead') ?? 0;
      _totalListeningMinutes = stats['totalListeningMinutes'] ?? prefs.getInt('totalListeningMinutes') ?? 0;
      _currentStreak = stats['currentStreak'] ?? prefs.getInt('currentStreak') ?? 0;
      _avgTtsSpeed = (stats['avgTtsSpeed'] ?? prefs.getDouble('avgTtsSpeed') ?? 1.0).toDouble();
      _listeningSessions = stats['listeningSessions'] ?? prefs.getInt('listeningSessions') ?? 0;
      
      _todayChaptersRead = todayStats['chaptersRead'] ?? 0;
      _todayListeningMinutes = todayStats['listeningMinutes'] ?? 0;
      
      for (int i = 0; i < 7; i++) {
        _weeklyReadingMinutes[i] = weeklyReading[i];
        _weeklyListeningMinutes[i] = weeklyListening[i];
      }
    });
  }

  int get _totalReadingMinutes => (_chaptersRead * 5);
  int get _grandTotalMinutes => _totalReadingMinutes + _totalListeningMinutes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'Week'),
            Tab(text: 'All Time'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTodayTab(),
          _buildWeekTab(),
          _buildAllTimeTab(),
        ],
      ),
    );
  }

  Widget _buildTodayTab() {
    final todayReading = _todayChaptersRead * 5;
    final todayListening = _todayListeningMinutes;
    final todayTotal = todayReading + todayListening;
    final readingPercent = todayTotal > 0 ? (todayReading / todayTotal * 100).round() : 0;
    final listeningPercent = todayTotal > 0 ? (todayListening / todayTotal * 100).round() : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCircularProgress(todayTotal, 30, 'mins read'),
          const SizedBox(height: 24),
          _buildSectionTitle('Reading vs Listening'),
          const SizedBox(height: 12),
          _buildStackedBar(readingPercent, listeningPercent),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatChip(_formatMinutes(todayReading), 'Reading', Colors.blue),
              const SizedBox(width: 8),
              _buildStatChip(_formatMinutes(todayListening), 'Listening', Colors.orange),
            ],
          ),
          const SizedBox(height: 24),
          _buildStreakCard(),
        ],
      ),
    );
  }

  Widget _buildWeekTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatCard('Books This Week', _booksCompleted.toString(), Icons.menu_book),
          const SizedBox(height: 16),
          _buildStatCard('Chapters Read', _chaptersRead.toString(), Icons.auto_stories),
          const SizedBox(height: 16),
          _buildStatCard('Listening Time', _formatMinutes(_totalListeningMinutes), Icons.headphones),
          const SizedBox(height: 24),
          _buildSectionTitle('Daily Activity'),
          const SizedBox(height: 12),
          _buildWeeklyBarChart(),
        ],
      ),
    );
  }

  Widget _buildAllTimeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatCard('Total Books', _totalBooks.toString(), Icons.library_books),
          const SizedBox(height: 16),
          _buildStatCard('Books Completed', _booksCompleted.toString(), Icons.check_circle),
          const SizedBox(height: 16),
          _buildStatCard('Grand Total', _formatMinutes(_grandTotalMinutes), Icons.timer),
          const SizedBox(height: 24),
          _buildSectionTitle('TTS Insights'),
          const SizedBox(height: 12),
          _buildTtsInsights(),
        ],
      ),
    );
  }

  Widget _buildCircularProgress(int current, int goal, String label) {
    final progress = goal > 0 ? (current / goal).clamp(0.0, 1.0) : 0.0;
    
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 150,
            height: 150,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 12,
              backgroundColor: Colors.grey[200],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$current',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'of $goal $label',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildStackedBar(int readingPercent, int listeningPercent) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          if (readingPercent > 0)
            Expanded(
              flex: readingPercent,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.horizontal(left: Radius.circular(15)),
                ),
              ),
            ),
          if (listeningPercent > 0)
            Expanded(
              flex: listeningPercent,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(15)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStreakCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.local_fire_department, color: Colors.orange, size: 40),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_currentStreak days',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text('Daily streak', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        trailing: Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyBarChart() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(7, (index) {
        final day = days[index];
        final reading = _weeklyReadingMinutes[index];
        final listening = _weeklyListeningMinutes[index];
        final total = (reading + listening).toDouble();
        
        // Scale height (max 150 pixels for 120 minutes)
        final height = (total / 120 * 150).clamp(4.0, 150.0);
        
        return Column(
          children: [
            Container(
              width: 25,
              height: height,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Text(day, style: const TextStyle(fontSize: 10)),
          ],
        );
      }),
    );
  }

  Widget _buildTtsInsights() {
    return Column(
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.speed, color: Colors.orange),
            title: const Text('Avg TTS Speed'),
            trailing: Text(
              '${_avgTtsSpeed.toStringAsFixed(1)}x',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.headphones, color: Colors.purple),
            title: const Text('Listening Sessions'),
            trailing: Text(
              '$_listeningSessions',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.access_time, color: Colors.green),
            title: const Text('Total Listening Time'),
            trailing: Text(
              _formatMinutes(_totalListeningMinutes),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) {
      return '${minutes}m';
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) {
      return '${hours}h';
    }
    return '${hours}h ${mins}m';
  }
}