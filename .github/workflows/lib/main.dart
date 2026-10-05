// NEXA AI phone app. Native screens for everything NEXA shows on the phone:
// Home (talk, approvals, live screen), Tasks, Cafe, Team and More.
// It pairs by scanning the codes in NEXA AI > Settings on the laptop.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link.dart';
import 'remote.dart';
import 'ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const NexaApp());
}

class NexaApp extends StatelessWidget {
  const NexaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NEXA AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kPrimary, surface: kPanel),
        useMaterial3: true,
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<String> links = <String>[];
  bool ready = false;
  bool adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      links = (p.getStringList('links') ?? <String>[]).where((String l) => kLink.hasMatch(l)).toList();
      ready = true;
    });
  }

  Future<void> _save() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setStringList('links', links);
  }

  void _paired(String link) {
    setState(() {
      // the newest code replaces an older one for the same address
      final String host = link.split('#').first;
      links = links.where((String l) => l.split('#').first != host).toList()..insert(0, link);
      adding = false;
    });
    _save();
  }

  void _unpair() {
    setState(() => links = <String>[]);
    _save();
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: kPrimary)));
    }
    if (links.isEmpty || adding) {
      return PairScreen(onPaired: _paired, onCancel: links.isEmpty ? null : () => setState(() => adding = false));
    }
    return RemoteScreen(
      key: ValueKey<String>(links.join('|')),
      links: links,
      onUnpair: _unpair,
      onScan: () => setState(() => adding = true),
    );
  }
}

/// Scan a code shown in NEXA AI > Settings > Phone link or Away link.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key, required this.onPaired, this.onCancel});

  final void Function(String link) onPaired;
  final VoidCallback? onCancel;

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final TextEditingController typed = TextEditingController();
  bool done = false;
  String note = '';

  void _try(String value) {
    final String v = value.trim();
    if (done) {
      return;
    }
    if (kLink.hasMatch(v)) {
      done = true;
      widget.onPaired(v);
    } else if (v.isNotEmpty) {
      setState(() => note = 'That is not a NEXA pairing code.');
    }
  }

  @override
  void dispose() {
    typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 8),
              const Text('NEXA AI', style: TextStyle(color: kPrimary, letterSpacing: 6, fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 18),
              const Text('Pair with your laptop', style: TextStyle(color: kText, fontSize: 24, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text(
                'On the laptop open NEXA AI, Settings. Point this phone at the code under Phone link (home Wi-Fi) or Away link (anywhere).',
                style: TextStyle(color: kLow, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: MobileScanner(
                    onDetect: (BarcodeCapture capture) {
                      for (final Barcode b in capture.barcodes) {
                        _try(b.rawValue ?? '');
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: typed,
                style: const TextStyle(color: kText, fontSize: 14),
                decoration: fieldLook('Or paste the address here').copyWith(
                  suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward, color: kPrimary), onPressed: () => _try(typed.text)),
                ),
                onSubmitted: _try,
              ),
              if (note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note, style: const TextStyle(color: kWarn))),
              if (widget.onCancel != null) TextButton(onPressed: widget.onCancel, child: const Text('Cancel', style: TextStyle(color: kLow))),
            ],
          ),
        ),
      ),
    );
  }
}
