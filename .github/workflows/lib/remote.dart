// The remote control itself: finds the laptop, keeps a fresh copy of what NEXA is doing, and shows the five screens.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'link.dart';
import 'ui.dart';

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key, required this.links, required this.onUnpair, required this.onScan});

  final List<String> links;
  final VoidCallback onUnpair;
  final VoidCallback onScan;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> with WidgetsBindingObserver {
  Link? link;
  Map<String, dynamic>? st;
  bool searching = true;
  bool paused = false;
  bool polling = false;
  bool grabbing = false;
  bool showScreen = false;
  bool hearing = false;
  bool speechReady = false;
  int tab = 0;
  int tasksView = 0;
  int fails = 0;
  int ticks = 0;
  int openTask = -1;
  String note = '';
  Uint8List? shot;
  Timer? timer;
  List<dynamic> history = <dynamic>[];
  List<dynamic> cafeLog = <dynamic>[];
  List<dynamic> notes = <dynamic>[];
  List<dynamic> learned = <dynamic>[];
  List<dynamic> models = <dynamic>[];
  final SpeechToText speech = SpeechToText();
  final TextEditingController input = TextEditingController();
  final TextEditingController pin = TextEditingController();
  final TextEditingController queueText = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connect();
    timer = Timer.periodic(const Duration(milliseconds: 1300), (Timer t) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    speech.cancel();
    link?.close();
    input.dispose();
    pin.dispose();
    queueText.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    paused = state != AppLifecycleState.resumed;
    if (!paused && link == null && !searching) {
      _connect();
    }
  }

  // ------------------------------------------------------------ connection
  Future<void> _connect() async {
    if (!mounted) {
      return;
    }
    setState(() => searching = true);
    // the laptop's own address first (fastest, when at home), then the away link
    final List<String> order = <String>[
      ...widget.links.where((String l) => l.startsWith('http://')),
      ...widget.links.where((String l) => l.startsWith('https://')),
    ];
    for (final String code in order) {
      final Link candidate = makeLink(code);
      final bool ok = await candidate.reachable();
      if (!mounted) {
        candidate.close();
        return;
      }
      if (ok) {
        link?.close();
        setState(() {
          link = candidate;
          searching = false;
          fails = 0;
        });
        _poll();
        return;
      }
      candidate.close();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      link?.close();
      link = null;
      searching = false;
    });
  }

  void _tick() {
    if (paused || link == null) {
      return;
    }
    ticks++;
    final bool away = link!.away;
    if (!away || ticks % 2 == 0) {
      _poll();
    }
    if (showScreen && ticks % (away ? 3 : 2) == 0) {
      _grab();
    }
    if (ticks % 7 == 0) {
      _refresh();
    }
  }

  Future<void> _poll() async {
    final Link? l = link;
    if (l == null || polling) {
      return;
    }
    polling = true;
    final Reply r = await l.call('GET', '/api/state');
    polling = false;
    if (!mounted || l != link) {
      return;
    }
    if (r.ok) {
      final bool had = st != null && st!['approval'] != null;
      setState(() {
        st = r.map;
        fails = 0;
      });
      if (!had && st!['approval'] != null) {
        HapticFeedback.heavyImpact();
      }
      return;
    }
    fails++;
    if (r.status == 401 && fails > 2) {
      widget.onUnpair();   // the laptop made a new code: this pairing is over
      return;
    }
    if (fails == 4) {
      setState(() {
        if (st != null) {
          st!['alive'] = false;
        }
      });
    }
    if (fails == 6 && widget.links.length > 1) {
      _connect();   // left home or came back: try the other way to the laptop
    }
  }

  Future<void> _grab() async {
    final Link? l = link;
    if (l == null || grabbing) {
      return;
    }
    grabbing = true;
    final Reply r = await l.call('GET', l.away ? '/api/screen?w=760' : '/api/screen');
    grabbing = false;
    if (mounted && r.ok && r.bytes != null && showScreen) {
      setState(() => shot = r.bytes);
    }
  }

  Future<void> _refresh() async {
    final Link? l = link;
    if (l == null || st == null) {
      return;
    }
    if (tab == 1 && tasksView == 0) {
      final Reply r = await l.call('GET', '/api/tasks');
      if (mounted && r.ok) {
        setState(() => history = lst(r.map['list']));
      }
    } else if (tab == 2) {
      final Reply r = await l.call('GET', '/api/cafe');
      if (mounted && r.ok) {
        setState(() => cafeLog = lst(r.map['list']));
      }
    } else if (tab == 4) {
      final Reply a = await l.call('GET', '/api/memory');
      final Reply b = await l.call('GET', '/api/models');
      if (mounted) {
        setState(() {
          if (a.ok) {
            notes = lst(a.map['notes']);
            learned = lst(a.map['learned']);
          }
          if (b.ok) {
            models = lst(b.map['list']);
          }
        });
      }
    }
  }

  /// Sends one command to NEXA and refreshes soon after.
  Future<void> _act(Map<String, dynamic> command) async {
    final Link? l = link;
    if (l == null) {
      return;
    }
    final Reply r = await l.call('POST', '/api/do', jsonEncode(command));
    if (!mounted) {
      return;
    }
    if (!r.ok) {
      setState(() => note = 'That did not reach the laptop. Try again.');
    } else if (note.isNotEmpty) {
      setState(() => note = '');
    }
    Timer(const Duration(milliseconds: 400), _poll);
  }

  String get _focus => str(st == null ? '' : st!['focus']);

  bool get _cafe => st != null && st!['mode'] == 'cafe';

  void _say(String text) {
    final String t = text.trim();
    if (t.isEmpty) {
      return;
    }
    final Map<String, dynamic> command = <String, dynamic>{'text': t};
    if (!_cafe && _focus.isNotEmpty) {
      command['to'] = _focus;
    }
    _act(command);
    input.clear();
  }

  // ------------------------------------------------------------ voice
  Future<void> _listen() async {
    if (speech.isListening) {
      await speech.stop();
      if (mounted) {
        setState(() => hearing = false);
      }
      return;
    }
    if (!speechReady) {
      speechReady = await speech.initialize(
        onStatus: (String s) {
          if ((s == 'done' || s == 'notListening') && mounted) {
            setState(() => hearing = false);
          }
        },
        onError: (Object _) {
          if (mounted) {
            setState(() => hearing = false);
          }
        },
      );
    }
    if (!mounted) {
      return;
    }
    if (!speechReady) {
      setState(() => note = 'Speech recognition is not available on this phone. Use the microphone key on the keyboard.');
      return;
    }
    setState(() {
      hearing = true;
      note = '';
    });
    final bool urdu = st != null && st!['lang'] == 'ur';
    await speech.listen(
      localeId: urdu ? 'ur_PK' : 'en_US',
      onResult: (SpeechRecognitionResult r) {
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          _say(r.recognizedWords);
        }
      },
    );
  }

  // ------------------------------------------------------------ frame
  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? s = st;
    if (link == null || s == null) {
      return _waiting();
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _top(s),
            Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 14), children: _page(s))),
            if (tab == 0) _bar(s),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: tab,
        type: BottomNavigationBarType.fixed,
        backgroundColor: kPanel,
        selectedItemColor: kPrimary,
        unselectedItemColor: kLow,
        onTap: (int i) {
          setState(() => tab = i);
          _refresh();
        },
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'Tasks'),
          BottomNavigationBarItem(icon: Icon(Icons.local_cafe_outlined), label: 'Fun'),
          BottomNavigationBarItem(icon: Icon(Icons.groups_outlined), label: 'Team'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }

  Widget _waiting() {
    final bool found = link != null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('NEXA AI', style: TextStyle(color: kPrimary, letterSpacing: 6, fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 22),
                if (searching || (found && fails < 4)) const CircularProgressIndicator(color: kPrimary),
                const SizedBox(height: 18),
                Text(
                  searching ? 'Looking for your laptop…' : (found && fails < 4 ? 'Connecting to NEXA…' : 'Cannot reach your laptop'),
                  style: const TextStyle(color: kText, fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                if (!searching && !(found && fails < 4))
                  const Text(
                    'Check that the laptop is on and NEXA AI is running. At home the phone must be on the same Wi-Fi with Phone link on. Away from home, Away link must be on in Settings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kLow, fontSize: 15, height: 1.4),
                  ),
                const SizedBox(height: 22),
                if (!searching) FilledButton(onPressed: _connect, child: const Text('Try again')),
                if (!searching) TextButton(onPressed: widget.onScan, child: const Text('Scan a code')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _top(Map<String, dynamic> s) {
    final bool cafe = s['mode'] == 'cafe';
    final bool alive = yes(s['alive']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Row(
        children: <Widget>[
          Container(width: 9, height: 9, decoration: BoxDecoration(color: alive ? kGood : kBad, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          const Text('NEXA AI', style: TextStyle(color: kPrimary, letterSpacing: 4, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(width: 10),
          Expanded(child: Text(link == null ? '' : link!.label, style: tLow, overflow: TextOverflow.ellipsis)),
          pill('Office', on: !cafe, onTap: () => _act(<String, dynamic>{'mode': 'office'})),
          const SizedBox(width: 6),
          pill('Café', on: cafe, color: kCafe, onTap: () => _act(<String, dynamic>{'mode': 'cafe'})),
        ],
      ),
    );
  }

  Widget _bar(Map<String, dynamic> s) {
    final bool cafe = s['mode'] == 'cafe';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(color: kPanel, border: Border(top: BorderSide(color: kLine))),
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTap: _listen,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: hearing ? kGood : kPrimary, shape: BoxShape.circle),
              child: Icon(hearing ? Icons.graphic_eq : Icons.mic, color: kBg),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: input,
              style: tBody,
              textInputAction: TextInputAction.send,
              onSubmitted: _say,
              decoration: fieldLook(hearing ? 'Listening… speak now' : (cafe ? 'Talk to the table…' : 'Tell NEXA what to do…')),
            ),
          ),
          IconButton(icon: const Icon(Icons.send, color: kPrimary), onPressed: () => _say(input.text)),
        ],
      ),
    );
  }

  List<Widget> _page(Map<String, dynamic> s) {
    switch (tab) {
      case 1:
        return _tasks(s);
      case 2:
        return _fun(s);
      case 3:
        return _team(s);
      case 4:
        return _more(s);
      default:
        return _home(s);
    }
  }

  Map<String, dynamic> _current(Map<String, dynamic> s) {
    Map<String, dynamic> cur = <String, dynamic>{};
    for (final dynamic w in lst(s['workers'])) {
      final Map<String, dynamic> m = mp(w);
      if (cur.isEmpty || m['id'] == s['focus']) {
        cur = m;
      }
    }
    return cur;
  }

  // ------------------------------------------------------------ Home
  List<Widget> _home(Map<String, dynamic> s) {
    final bool cafe = s['mode'] == 'cafe';
    final List<dynamic> workers = lst(s['workers']);
    final Map<String, dynamic> cur = _current(s);
    final Map<String, dynamic> approval = mp(s['approval']);
    final Map<String, dynamic> saying = mp(s['say']);
    final Map<String, dynamic> task = mp(cur['task']);
    final List<dynamic> steps = lst(task['steps']);
    final String agent = str(cur['agent']);
    final List<Widget> out = <Widget>[];

    if (!yes(s['alive'])) {
      out.add(card(border: kBad, child: const Text('NEXA AI is not answering. Check that the laptop is on and NEXA is running.', style: tBody)));
    }
    if (note.isNotEmpty) {
      out.add(card(border: kWarn, child: Text(note, style: tBody)));
    }
    if (approval.isNotEmpty) {
      out.add(_approval(approval));
    }

    // the team: tap to talk to someone (office) or to invite them to the table (café)
    out.add(Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final dynamic w in workers) _chip(mp(w), cafe, str(cur['id'])),
        ],
      ),
    ));

    out.add(card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: stateColor(agent).withAlpha(36), shape: BoxShape.circle, border: Border.all(color: stateColor(agent))),
                child: Icon(Icons.smart_toy_outlined, color: stateColor(agent)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(str(cur['name']), style: tHead),
                    Text(cafe ? 'At the table' : (kStateName[agent] ?? agent), style: TextStyle(color: stateColor(agent), fontSize: 13.5)),
                    Text('${str(cur['dutyLabel'])}${str(cur['done']) != '0' && str(cur['done']).isNotEmpty ? ' · ${str(cur['done'])} done' : ''}', style: tLow),
                  ],
                ),
              ),
            ],
          ),
          if (str(s['heard']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Heard: ${str(s['heard'])}', style: tLow)),
          if (saying.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kPanel2, borderRadius: BorderRadius.circular(12)),
              child: Text('${str(saying['name'])}: ${str(saying['text'])}', style: tBody),
            ),
        ],
      ),
    ));

    if (!cafe && task.isNotEmpty) {
      out.add(card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            label('Task'),
            Text(str(task['goal']), style: tBody),
            const SizedBox(height: 6),
            for (final dynamic x in steps) _step(mp(x)),
          ],
        ),
      ));
    }

    if (cafe) {
      final List<dynamic> chat = lst(s['chat']);
      out.add(card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            label('At the table'),
            if (chat.isEmpty) empty('Say something to start the conversation.'),
            for (final dynamic c in chat.length > 14 ? chat.sublist(chat.length - 14) : chat) _bubble(mp(c)),
          ],
        ),
      ));
    } else {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String q in const <String>['Open Notepad', 'What is on my screen', 'Check my system', 'Open Downloads', 'What time is it']) pill(q, onTap: () => _say(q)),
            for (final dynamic k in lst(s['skills'])) pill(str(k), color: kCafe, on: true, onTap: () => _say(str(k))),
          ],
        ),
      ));
    }

    out.add(Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                showScreen = !showScreen;
                if (!showScreen) {
                  shot = null;
                }
              });
              if (showScreen) {
                _grab();
              }
            },
            icon: const Icon(Icons.desktop_windows_outlined, size: 18),
            label: Text(showScreen ? 'Hide screen' : 'Show screen'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _act(<String, dynamic>{'stop': true}),
            style: OutlinedButton.styleFrom(foregroundColor: kBad),
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('Stop everyone'),
          ),
        ),
      ],
    ));
    if (showScreen) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: shot == null
              ? Container(height: 180, color: kPanel, alignment: Alignment.center, child: const Text('Loading the laptop screen…', style: tLow))
              : InteractiveViewer(maxScale: 4, child: Image.memory(shot!, gaplessPlayback: true, fit: BoxFit.fitWidth)),
        ),
      ));
    }
    return out;
  }

  Widget _chip(Map<String, dynamic> w, bool cafe, String currentId) {
    final String id = str(w['id']);
    final String agent = str(w['agent']);
    final bool on = cafe ? yes(w['here']) : id == currentId;
    final String sub = cafe ? (yes(w['here']) ? 'At the table' : 'Tap to invite') : (kStateName[agent] ?? agent);
    return GestureDetector(
      onTap: () => _act(cafe ? <String, dynamic>{'guest': id} : <String, dynamic>{'focus': id}),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? kPrimary.withAlpha(30) : kPanel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? kPrimary : kLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(str(w['name']), style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w600)),
            Text(sub, style: TextStyle(color: cafe ? kLow : stateColor(agent), fontSize: 11.5)),
          ],
        ),
      ),
    );
  }

  Widget _step(Map<String, dynamic> x) {
    final String status = str(x['status']);
    final Color c = status == 'done' ? kGood : (status == 'active' ? kPrimary : (status == 'denied' ? kBad : kLow));
    final String mark = status == 'done' ? '✓' : (status == 'active' ? '▸' : (status == 'denied' ? '✕' : '·'));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 20, child: Text(mark, style: TextStyle(color: c, fontSize: 14))),
          Expanded(child: Text(str(x['name']), style: TextStyle(color: status == 'pending' ? kLow : kText, fontSize: 14, height: 1.3))),
        ],
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> c) {
    final bool mine = c['who'] == 'you';
    final String name = mine ? '' : (str(c['name']).isEmpty ? 'NEXA' : str(c['name']));
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(color: mine ? kPrimary.withAlpha(36) : kPanel2, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (name.isNotEmpty) Text(name, style: const TextStyle(color: kCafe, fontSize: 11.5, fontWeight: FontWeight.w600)),
            Text(str(c['text']), style: tBody),
          ],
        ),
      ),
    );
  }

  Widget _approval(Map<String, dynamic> a) {
    return card(
      border: kWarn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          label('Permission required · ${str(a['risk'])}'),
          Text('${str(a['who'])} wants to: ${str(a['text'])}', style: tHead),
          const SizedBox(height: 8),
          Text('Where: ${str(a['where']).isEmpty ? 'This laptop' : str(a['where'])}', style: tLow),
          Text('Can it be undone: ${str(a['undo']).isEmpty ? 'No' : str(a['undo'])}', style: tLow),
          if (yes(a['needPin']))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                style: tBody,
                decoration: fieldLook(yes(a['bad']) ? 'Wrong PIN. Try again' : 'Approval PIN'),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final Map<String, dynamic> command = <String, dynamic>{'approve': true};
                    if (pin.text.isNotEmpty) {
                      command['pin'] = pin.text;
                    }
                    pin.clear();
                    _act(command);
                  },
                  child: const Text('Allow'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton(onPressed: () => _act(<String, dynamic>{'approve': false}), child: const Text('Deny'))),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ Tasks
  List<Widget> _tasks(Map<String, dynamic> s) {
    const List<String> views = <String>['History', 'Queue', 'Schedule'];
    final List<Widget> out = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(
          spacing: 8,
          children: <Widget>[
            for (int i = 0; i < 3; i++)
              pill(views[i], on: tasksView == i, onTap: () {
                setState(() => tasksView = i);
                _refresh();
              }),
          ],
        ),
      ),
    ];
    if (tasksView == 0) {
      if (history.isEmpty) {
        out.add(empty('No finished tasks yet. Everything the robots do in the office is listed here.'));
      }
      for (int i = 0; i < history.length; i++) {
        final Map<String, dynamic> t = mp(history[i]);
        final bool ok = yes(t['ok']);
        out.add(card(
          pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              rowItem(
                str(t['text']),
                '${str(t['who'])} · ${str(t['when'])}',
                end: Text(ok ? '✓' : '✕', style: TextStyle(color: ok ? kGood : kBad, fontSize: 16)),
                onTap: () => setState(() => openTask = openTask == i ? -1 : i),
              ),
              if (openTask == i && str(t['say']).isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(str(t['say']), style: tLow)),
              if (openTask == i)
                for (final dynamic x in lst(t['steps'])) _step(mp(x)),
              if (openTask == i)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: () => _say(str(t['text'])), child: const Text('Run again')),
                ),
            ],
          ),
        ));
      }
    } else if (tasksView == 1) {
      out.addAll(_queue(s));
    } else {
      out.addAll(_schedule(s));
    }
    return out;
  }

  List<Widget> _queue(Map<String, dynamic> s) {
    final Map<String, dynamic> cur = _current(s);
    final String id = str(cur['id']);
    final List<dynamic> queue = lst(cur['queue']);
    final bool running = yes(cur['queueRunning']);
    return <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final dynamic w in lst(s['workers'])) pill(str(mp(w)['name']), on: mp(w)['id'] == id, onTap: () => _act(<String, dynamic>{'focus': str(mp(w)['id'])})),
          ],
        ),
      ),
      card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            label('Queue for ${str(cur['name'])}'),
            if (queue.isEmpty) empty('Nothing waiting. Add tasks and they run one after another.'),
            for (final dynamic q in queue)
              rowItem(
                str(mp(q)['text']),
                str(mp(q)['status']),
                end: IconButton(
                  icon: const Icon(Icons.close, color: kLow, size: 20),
                  onPressed: () => _act(<String, dynamic>{'queueRemove': mp(q)['id'], 'to': id}),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(child: TextField(controller: queueText, style: tBody, decoration: fieldLook('Add a task to the queue'))),
                IconButton(
                  icon: const Icon(Icons.add, color: kPrimary),
                  onPressed: () {
                    final String t = queueText.text.trim();
                    if (t.isNotEmpty) {
                      _act(<String, dynamic>{'queueAdd': t, 'to': id});
                      queueText.clear();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: queue.isEmpty ? null : () => _act(running ? <String, dynamic>{'queuePause': id} : <String, dynamic>{'queueStart': id}),
              icon: Icon(running ? Icons.pause : Icons.play_arrow, size: 18),
              label: Text(running ? 'Pause the queue' : 'Start the queue'),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _schedule(Map<String, dynamic> s) {
    final List<dynamic> items = lst(s['schedules']);
    const Map<String, String> repeatName = <String, String>{'once': 'Once', 'daily': 'Every day', 'weekdays': 'Weekdays', 'weekly': 'Every week'};
    return <Widget>[
      card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            label('Timed tasks'),
            if (items.isEmpty) empty('Nothing is scheduled.'),
            for (final dynamic x in items)
              rowItem(
                str(mp(x)['text']),
                '${str(mp(x)['whoName'])} · ${str(mp(x)['date'])} ${str(mp(x)['time'])} · ${repeatName[str(mp(x)['repeat'])] ?? str(mp(x)['repeat'])}',
                end: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Switch(value: yes(mp(x)['enabled']), onChanged: (bool v) => _act(<String, dynamic>{'schedToggle': mp(x)['id']})),
                    IconButton(icon: const Icon(Icons.delete_outline, color: kLow, size: 20), onPressed: () => _act(<String, dynamic>{'schedRemove': mp(x)['id']})),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: () => _addSchedule(s), icon: const Icon(Icons.add, size: 18), label: const Text('Add a timed task')),
          ],
        ),
      ),
    ];
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _addSchedule(Map<String, dynamic> s) async {
    final TextEditingController what = TextEditingController();
    final DateTime now = DateTime.now();
    DateTime day = now;
    TimeOfDay time = TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
    String repeat = 'once';
    String who = _focus.isEmpty ? 'nexa' : _focus;
    final List<dynamic> workers = lst(s['workers']);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => StatefulBuilder(
        builder: (BuildContext c2, StateSetter setD) => AlertDialog(
          backgroundColor: kPanel,
          title: const Text('Timed task', style: tHead),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(controller: what, style: tBody, decoration: fieldLook('What should be done?')),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    pill('${day.year}-${_two(day.month)}-${_two(day.day)}', onTap: () async {
                      final DateTime? d = await showDatePicker(context: c2, initialDate: day, firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 2));
                      if (d != null) {
                        setD(() => day = d);
                      }
                    }),
                    pill('${_two(time.hour)}:${_two(time.minute)}', onTap: () async {
                      final TimeOfDay? t = await showTimePicker(context: c2, initialTime: time);
                      if (t != null) {
                        setD(() => time = t);
                      }
                    }),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final String r in const <String>['once', 'daily', 'weekdays', 'weekly']) pill(r, on: repeat == r, onTap: () => setD(() => repeat = r)),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final dynamic w in workers) pill(str(mp(w)['name']), on: who == str(mp(w)['id']), color: kCafe, onTap: () => setD(() => who = str(mp(w)['id']))),
                  ],
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(c2).pop(false), child: const Text('Cancel', style: TextStyle(color: kLow))),
            TextButton(onPressed: () => Navigator.of(c2).pop(true), child: const Text('Add')),
          ],
        ),
      ),
    );
    final String text = what.text.trim();
    if (ok == true && text.isNotEmpty) {
      _act(<String, dynamic>{
        'schedAdd': <String, dynamic>{
          'text': text,
          'date': '${day.year}-${_two(day.month)}-${_two(day.day)}',
          'time': '${_two(time.hour)}:${_two(time.minute)}',
          'repeat': repeat,
          'who': who,
        },
      });
    }
  }

  // ------------------------------------------------------------ Fun (café conversations)
  List<Widget> _fun(Map<String, dynamic> s) {
    final List<Widget> out = <Widget>[];
    if (cafeLog.isEmpty) {
      out.add(empty('Nothing yet. Everything said in the café is kept here, apart from office tasks.'));
      return out;
    }
    String lastDay = '';
    final List<dynamic> recent = cafeLog.length > 120 ? cafeLog.sublist(cafeLog.length - 120) : cafeLog;
    for (final dynamic x in recent) {
      final Map<String, dynamic> m = mp(x);
      final String when = str(m['t']);
      final String day = when.length >= 10 ? when.substring(0, 10) : when;
      if (day != lastDay) {
        lastDay = day;
        out.add(Padding(padding: const EdgeInsets.only(top: 8), child: label(day)));
      }
      out.add(_bubble(m));
    }
    return out;
  }

  // ------------------------------------------------------------ Team
  List<Widget> _team(Map<String, dynamic> s) {
    final List<dynamic> workers = lst(s['workers']);
    final List<dynamic> duties = lst(s['duties']);
    final dynamic maxValue = s['maxEmployees'];
    final int max = maxValue is int ? maxValue : 6;
    String dutyName(String key) {
      for (final dynamic d in duties) {
        final List<dynamic> pair = lst(d);
        if (pair.length > 1 && str(pair[0]) == key) {
          return str(pair[1]);
        }
      }
      return key;
    }

    final List<Widget> out = <Widget>[];
    for (final dynamic x in workers) {
      final Map<String, dynamic> w = mp(x);
      final String id = str(w['id']);
      final bool boss = id == 'nexa';
      final String agent = str(w['agent']);
      final bool blocked = w['perm'] == 'blocked';
      out.add(card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(str(w['name']), style: tHead)),
                Text(kStateName[agent] ?? agent, style: TextStyle(color: stateColor(agent), fontSize: 13)),
              ],
            ),
            Text('${boss ? 'Manager' : dutyName(str(w['duty']))} · ${str(w['gender'])} · ${str(w['done'])} tasks done', style: tLow),
            if (!boss) const SizedBox(height: 10),
            if (!boss)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  PopupMenuButton<String>(
                    color: kPanel2,
                    onSelected: (String v) => _act(<String, dynamic>{'duty': id, 'value': v}),
                    itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
                      for (final dynamic d in duties)
                        if (lst(d).length > 1 && str(lst(d)[0]) != 'manager') PopupMenuItem<String>(value: str(lst(d)[0]), child: Text(str(lst(d)[1]), style: tBody)),
                    ],
                    child: pill('Speciality: ${dutyName(str(w['duty']))}'),
                  ),
                  pill(blocked ? 'Risky actions: blocked' : 'Risky actions: ask me', on: blocked, color: kWarn, onTap: () => _act(<String, dynamic>{'perm': id, 'value': blocked ? 'ask' : 'blocked'})),
                  pill('Retire', color: kBad, on: true, onTap: () async {
                    final bool sure = await confirm(context, 'Retire ${str(w['name'])}?', 'Their queue is removed. Their finished tasks stay in the history.', 'Retire');
                    if (sure) {
                      _act(<String, dynamic>{'retire': id});
                    }
                  }),
                ],
              ),
          ],
        ),
      ));
    }
    if (workers.length - 1 < max) {
      out.add(FilledButton.icon(onPressed: () => _hire(duties), icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Hire an employee')));
    } else {
      out.add(empty('The office is full ($max employees). Retire one to hire another.'));
    }
    return out;
  }

  Future<void> _hire(List<dynamic> duties) async {
    final TextEditingController name = TextEditingController();
    String gender = 'female';
    String duty = 'all';
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => StatefulBuilder(
        builder: (BuildContext c2, StateSetter setD) => AlertDialog(
          backgroundColor: kPanel,
          title: const Text('Hire an employee', style: tHead),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(controller: name, maxLength: 14, style: tBody, decoration: fieldLook('Name')),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    pill('Female', on: gender == 'female', onTap: () => setD(() => gender = 'female')),
                    pill('Male', on: gender == 'male', onTap: () => setD(() => gender = 'male')),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Speciality', style: tLow),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final dynamic d in duties)
                      if (lst(d).length > 1 && str(lst(d)[0]) != 'manager') pill(str(lst(d)[1]), on: duty == str(lst(d)[0]), color: kCafe, onTap: () => setD(() => duty = str(lst(d)[0]))),
                  ],
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(c2).pop(false), child: const Text('Cancel', style: TextStyle(color: kLow))),
            TextButton(onPressed: () => Navigator.of(c2).pop(true), child: const Text('Hire')),
          ],
        ),
      ),
    );
    final String n = name.text.trim();
    if (ok == true && n.isNotEmpty) {
      _act(<String, dynamic>{
        'hire': <String, dynamic>{'name': n, 'gender': gender, 'duty': duty},
      });
    }
  }

  // ------------------------------------------------------------ More
  List<Widget> _more(Map<String, dynamic> s) {
    final bool urdu = s['lang'] == 'ur';
    final List<dynamic> skills = lst(s['skills']);
    return <Widget>[
      card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            label('NEXA on the laptop'),
            rowItem('Language', 'What NEXA speaks and listens for', end: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                pill('English', on: !urdu, onTap: () => _act(<String, dynamic>{'lang': 'en'})),
                const SizedBox(width: 6),
                pill('اردو', on: urdu, onTap: () => _act(<String, dynamic>{'lang': 'ur'})),
              ],
            )),
            rowItem('Hey NEXA (hands-free)', 'The laptop listens for his name', end: Switch(value: yes(s['handsFree']), onChanged: (bool v) => _act(<String, dynamic>{'handsFree': v}))),
            rowItem('Mute the laptop voice', 'Robots answer in text only', end: Switch(value: yes(s['muted']), onChanged: (bool v) => _act(<String, dynamic>{'mute': v}))),
          ],
        ),
      ),
      card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            label('Skills · tap to run'),
            if (skills.isEmpty) empty('No skills yet. Make them on the laptop, on the Skills page.'),
            if (skills.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final dynamic k in skills)
                    pill(str(k), color: kCafe, on: true, onTap: () {
                      _act(<String, dynamic>{'text': str(k)});
                      setState(() => tab = 0);
                    }),
                ],
              ),
          ],
        ),
      ),
      card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            label('What NEXA remembers · ${notes.length}'),
            if (notes.isEmpty) empty('Nothing yet.'),
            for (final dynamic n in notes.length > 20 ? notes.sublist(0, 20) : notes) rowItem(str(mp(n)['text']), str(mp(n)['when'])),
          ],
        ),
      ),
      card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            label('Learned from tasks · ${learned.length}'),
            if (learned.isEmpty) empty('Nothing yet.'),
            for (final dynamic n in learned.length > 12 ? learned.sublist(0, 12) : learned) rowItem(str(mp(n)['text']), '${str(mp(n)['steps'])} steps'),
          ],
        ),
      ),
      card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            label('AI services'),
            if (models.isEmpty) empty('Loading…'),
            for (final dynamic m in models)
              rowItem(
                str(mp(m)['name']),
                str(mp(m)['kind']),
                end: Text(yes(mp(m)['key']) ? 'Key saved' : 'No key', style: TextStyle(color: yes(mp(m)['key']) ? kGood : kLow, fontSize: 13)),
              ),
          ],
        ),
      ),
      card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            label('This phone'),
            Text('Connected through: ${link == null ? '' : link!.label}', style: tBody),
            Text('${widget.links.length} pairing code${widget.links.length == 1 ? '' : 's'} saved. The app uses home Wi-Fi when it can, and the away link otherwise.', style: tLow),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                pill('Scan another code', onTap: widget.onScan),
                pill('Look for the laptop again', onTap: _connect),
                pill('Unpair this phone', color: kBad, on: true, onTap: () async {
                  final bool sure = await confirm(context, 'Unpair this phone?', 'You will need to scan the codes on the laptop again.', 'Unpair');
                  if (sure) {
                    widget.onUnpair();
                  }
                }),
              ],
            ),
          ],
        ),
      ),
    ];
  }
}
