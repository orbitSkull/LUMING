import 'package:flutter/material.dart';
import '../services/writer_service.dart';

class WriterStatsScreen extends StatefulWidget {
  const WriterStatsScreen({super.key});

  @override
  State<WriterStatsScreen> createState() => _WriterStatsScreenState();
}

class _WriterStatsScreenState extends State<WriterStatsScreen> {
  final WriterService _writerService = WriterService();
  int _dailyGoal = 500;
  
  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats() async {
    await _writerService.loadStats();
    setState(() {
      _dailyGoal = _writerService.stats.dailyGoal;
    });
  }

  void _showGoalDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: _dailyGoal.toString());
        return AlertDialog(
          title: const Text('Set Daily Goal'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Words per day',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final goal = int.tryParse(controller.text) ?? 500;
                await _writerService.setDailyGoal(goal);
                setState(() => _dailyGoal = goal);
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _writerService.stats;
    final progress = stats.sessionWords / _dailyGoal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Writer Stats'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showGoalDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatCard(
              'Session Progress',
              '${stats.sessionWords} words',
              LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation(
                  progress >= 1 ? Colors.green : Colors.teal,
                ),
              ),
              '${(progress * 100).toInt()}% of daily goal',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildStatTile('Today', '${stats.sessionWords}', 'words', Icons.today)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatTile('Total', '${stats.totalWords}', 'words', Icons.library_books)),
              ],
            ),
            const SizedBox(height: 16),
            _buildStreakCard(stats),
            const SizedBox(height: 16),
            _buildVelocityCard(stats),
            const SizedBox(height: 16),
            if (stats.sessionStartTime != null)
              _buildSessionTimer()
            else
              OutlinedButton.icon(
                onPressed: () => _writerService.startSession(),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Writing Session'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Widget progress, String subtitle) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            progress,
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile(String title, String value, String unit, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: Colors.teal, size: 28),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(unit, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(color: Colors.teal, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildStreakCard(dynamic stats) {
    return Card(
      color: stats.currentStreak > 0 ? Colors.orange[50] : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              stats.currentStreak > 0 ? Icons.local_fire_department : Icons.fireplace_outlined,
              color: stats.currentStreak > 0 ? Colors.orange : Colors.grey,
              size: 40,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${stats.currentStreak} Day Streak!',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Best: ${stats.longestStreak} days',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (stats.goalReachedToday)
              const Chip(
                label: Text('Goal Met!'),
                backgroundColor: Colors.green,
                labelStyle: TextStyle(color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVelocityCard(dynamic stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Writing Velocity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildVelocityItem('${stats.velocity.toStringAsFixed(1)}', 'words/hr'),
                _buildVelocityItem('${stats.sessionDuration}', 'minutes'),
                _buildVelocityItem('${_dailyGoal}', 'daily goal'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVelocityItem(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _buildSessionTimer() {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final stats = _writerService.stats;
        final minutes = stats.sessionDuration;
        return Card(
          color: Colors.teal[50],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer, color: Colors.teal),
                const SizedBox(width: 8),
                Text(
                  'Session: ${minutes}m',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () async {
                    await _writerService.endSession();
                    setState(() {});
                  },
                  child: const Text('End Session'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}