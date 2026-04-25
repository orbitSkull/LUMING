import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const DaPubReaderApp());
}

class DaPubReaderApp extends StatelessWidget {
  const DaPubReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DaPub Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}