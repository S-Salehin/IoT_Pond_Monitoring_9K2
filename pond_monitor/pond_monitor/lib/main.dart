// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const PondApp());
}

/// Global theme — clean, modern, unique
class PondApp extends StatelessWidget {
  const PondApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pond Monitor',
      theme: base.copyWith(
        textTheme: GoogleFonts.interTextTheme(base.textTheme),
        cardTheme: CardThemeData(
          elevation: 2,
          margin: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        ),
      ),
      home: const HomeShell(),
    );
  }
}


/// Bottom-nav shell
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  String nodeId = 'pond_node_01';

  @override
  Widget build(BuildContext context) {
    final pages = [
      LiveScreen(nodeId: nodeId, onNodeChanged: (s) => setState(() => nodeId = s)),
      HistoryScreen(nodeId: nodeId),
      SettingsScreen(nodeId: nodeId, onNodeChanged: (s) => setState(() => nodeId = s)),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Pond Monitor', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0f766e), Color(0xFF042f2e)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(child: pages[_index]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.podcasts), label: 'Live'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

/// LIVE — listens to /live/<nodeId> and renders cards for ANY keys it finds
class LiveScreen extends StatelessWidget {
  final String nodeId;
  final ValueChanged<String> onNodeChanged;
  const LiveScreen({super.key, required this.nodeId, required this.onNodeChanged});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('live/$nodeId');

    return StreamBuilder(
      stream: ref.onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }

        final event = snapshot.data as DatabaseEvent?;
        final map = (event?.snapshot.value is Map)
            ? Map<String, dynamic>.from(event!.snapshot.value as Map)
            : <String, dynamic>{};

        final ts = map['ts'] is int
            ? DateTime.fromMillisecondsSinceEpoch((map['ts'] as int) * 1000)
            : null;

        // Render all keys except meta
        final keys = map.keys.where((k) => !['node_id', 'ts'].contains(k)).toList()..sort();

        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Row(
              children: [
                Expanded(child: NodePicker(current: nodeId, onChanged: onNodeChanged)),
                const SizedBox(width: 12),
                if (ts != null)
                  Text(DateFormat('MMM d, HH:mm:ss').format(ts),
                      style: GoogleFonts.inter(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 8),

            // Animate list of cards
            ...keys.map((k) {
              final v = map[k];
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, .05), end: Offset.zero).animate(anim),
                      child: child,
                    )),
                child: SensorCard(
                  key: ValueKey('$k-$v'),
                  title: prettyKey(k),
                  value: v,
                  unit: unitFor(k),
                  status: statusFor(k, v),
                  icon: iconFor(k),
                ),
              );
            }),

            if (keys.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Text('No live data yet…',
                      style: GoogleFonts.inter(color: Colors.white70, fontSize: 16)),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// HISTORY — reads last 200 entries
/// New sensors: ift add another HistoryChart line below to visualize
class HistoryScreen extends StatelessWidget {
  final String nodeId;
  const HistoryScreen({super.key, required this.nodeId});

  Future<List<Map<String, dynamic>>> _load() async {
    final ref = FirebaseDatabase.instance.ref('history/$nodeId').limitToLast(200);
    final snap = await ref.get();
    final out = <Map<String, dynamic>>[];
    if (snap.value is Map) {
      (snap.value as Map).forEach((_, v) => out.add(Map<String, dynamic>.from(v as Map)));
      out.sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _load(),
      builder: (context, s) {
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        final data = s.data as List<Map<String, dynamic>>;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Last ${data.length} samples',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 16)),
            ),
            HistoryChart(title: 'Water Temp (°C)', data: data, keyName: 'water_temp_c'),
            HistoryChart(title: 'pH', data: data, keyName: 'ph'),
            HistoryChart(title: 'Air Temp (°C)', data: data, keyName: 'air_temp_c'),
            HistoryChart(title: 'Humidity (%)', data: data, keyName: 'humidity'),

            // 👉 Add new sensors here when you want charts for them:
            // HistoryChart(title: 'Turbidity (NTU)', data: data, keyName: 'turbidity'),
            // HistoryChart(title: 'DO (mg/L)', data: data, keyName: 'do_mg_l'),
          ],
        );
      },
    );
  }
}

/// SETTINGS — switch node id (
class SettingsScreen extends StatefulWidget {
  final String nodeId;
  final ValueChanged<String> onNodeChanged;
  const SettingsScreen({super.key, required this.nodeId, required this.onNodeChanged});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _ctl;
  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.nodeId);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Card(
          color: Colors.white.withOpacity(.95),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Node ID', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _ctl,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'pond_node_01'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => widget.onNodeChanged(_ctl.text.trim()),
                child: const Text('Switch Node'),
              ),
              const SizedBox(height: 8),
              const Text('Tip: Add more sensors on ESP32. New keys appear automatically on the Live tab.'),
            ]),
          ),
        ),
      ],
    );
  }
}

/// Small picker widget
class NodePicker extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const NodePicker({super.key, required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white.withOpacity(.95),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          const Icon(Icons.router, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(current, style: GoogleFonts.inter(fontWeight: FontWeight.w600))),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () async {
              final ctl = TextEditingController(text: current);
              final res = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Change Node ID'),
                  content: TextField(controller: ctl, decoration: const InputDecoration(hintText: 'pond_node_01')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('OK')),
                  ],
                ),
              );
              if (res != null && res.isNotEmpty) onChanged(res);
            },
          ),
        ]),
      ),
    );
  }
}

/// Sensor Card 
class SensorCard extends StatelessWidget {
  final String title;
  final dynamic value;
  final String unit;
  final String status;
  final IconData icon;

  const SensorCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.status,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final display =
        (value == null) ? '—' : (value is num ? (value as num).toStringAsFixed(2) : value.toString());
    final ok = status == 'OK';

    return Card(
      color: Colors.white.withOpacity(.97),
      child: ListTile(
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: ok ? Colors.teal : Colors.orange,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        subtitle: Text('$display $unit', style: GoogleFonts.inter(fontSize: 18)),
        trailing: Chip(
          label: Text(ok ? 'OK' : status, style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          backgroundColor: ok ? Colors.teal.shade50 : Colors.orange.shade50,
          side: BorderSide(color: ok ? Colors.teal.shade200 : Colors.orange.shade200),
        ),
      ),
    );
  }
}

/// Small line chart card
class HistoryChart extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> data;
  final String keyName;

  const HistoryChart({super.key, required this.title, required this.data, required this.keyName});

  @override
  Widget build(BuildContext context) {
    final points = <FlSpot>[];
    int idx = 0;
    for (final m in data) {
      if (m[keyName] == null) continue;
      final y = (m[keyName] as num).toDouble();
      points.add(FlSpot(idx.toDouble(), y));
      idx++;
    }

    if (points.isEmpty) {
      return Card(
        color: Colors.white.withOpacity(.95),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('$title — no data', style: GoogleFonts.inter()),
        ),
      );
    }

    return Card(
      color: Colors.white.withOpacity(.95),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                lineBarsData: [
                  LineChartBarData(
                    spots: points,
                    isCurved: true,
                    dotData: const FlDotData(show: false),
                    barWidth: 3,
                  ),
                ],
                gridData: const FlGridData(show: true),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// names, units, icons, status ranges 

String prettyKey(String k) {
  switch (k) {
    case 'water_temp_c':
      return 'Water Temp';
    case 'air_temp_c':
      return 'Air Temp';
    case 'humidity':
      return 'Humidity';
    case 'ph':
      return 'pH';
    default:
      // Make unknown keys look nice: "do_mg_l" -> "do mg l" -> "Do Mg L"
      return k.replaceAll('_', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return '${w[0].toUpperCase()}${w.substring(1)}';
      }).join(' ');
  }
}

String unitFor(String k) {
  switch (k) {
    case 'water_temp_c':
    case 'air_temp_c':
      return '°C';
    case 'humidity':
      return '%';
    case 'ph':
      return '';
    // Examples for future sensors 
    case 'turbidity':
      return 'NTU';
    case 'do_mg_l':
      return 'mg/L';
    default:
      return '';
  }
}

IconData iconFor(String k) {
  switch (k) {
    case 'water_temp_c':
      return Icons.water;
    case 'air_temp_c':
      return Icons.thermostat;
    case 'humidity':
      return Icons.water_drop;
    case 'ph':
      return Icons.science;
    case 'turbidity':
      return Icons.auto_graph;
    case 'do_mg_l':
      return Icons.bubble_chart;
    default:
      return Icons.sensors;
  }
}

/// Simple “good/bad” labels for quick demo.
/// You can refine thresholds later (or even fetch them from Firebase/Settings).
String statusFor(String k, dynamic val) {
  if (val == null) return '—';
  final v = (val is num) ? val.toDouble() : double.tryParse(val.toString());
  if (v == null) return 'OK';

  switch (k) {
    case 'water_temp_c':
      return (v < 18 || v > 34) ? 'Check' : 'OK';
    case 'ph':
      return (v < 6.5 || v > 8.5) ? 'Check' : 'OK';
    default:
      return 'OK';
  }
}
