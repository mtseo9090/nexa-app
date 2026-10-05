// Colours and the small building blocks every screen uses.
import 'package:flutter/material.dart';

const Color kBg = Color(0xFF080A0E);
const Color kPanel = Color(0xFF10141B);
const Color kPanel2 = Color(0xFF171C25);
const Color kLine = Color(0xFF232A36);
const Color kPrimary = Color(0xFF22D3EE);
const Color kText = Color(0xFFE8ECF2);
const Color kLow = Color(0xFF8A94A6);
const Color kWarn = Color(0xFFFBBF24);
const Color kBad = Color(0xFFF87171);
const Color kGood = Color(0xFF34D399);
const Color kCafe = Color(0xFFF59E0B);

const TextStyle tBody = TextStyle(color: kText, fontSize: 15, height: 1.35);
const TextStyle tLow = TextStyle(color: kLow, fontSize: 13, height: 1.35);
const TextStyle tHead = TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w600);

// ---- reading the laptop's answers safely, whatever shape they have
String str(dynamic v) => v == null ? '' : v.toString();

List<dynamic> lst(dynamic v) => v is List ? v : const <dynamic>[];

Map<String, dynamic> mp(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

bool yes(dynamic v) => v == true;

const Map<String, String> kStateName = <String, String>{
  'idle': 'Ready',
  'listening': 'Listening',
  'thinking': 'Thinking',
  'working': 'Working',
  'speaking': 'Speaking',
  'approval': 'Needs you',
  'done': 'Done',
  'error': 'Stopped',
};

Color stateColor(String agent) {
  switch (agent) {
    case 'working':
    case 'thinking':
      return kPrimary;
    case 'speaking':
    case 'listening':
      return kGood;
    case 'approval':
      return kWarn;
    case 'error':
      return kBad;
    default:
      return kLow;
  }
}

Widget card({required Widget child, Color border = kLine, EdgeInsetsGeometry pad = const EdgeInsets.all(14)}) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: pad,
    decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
    child: child,
  );
}

Widget label(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text.toUpperCase(), style: const TextStyle(color: kLow, fontSize: 11, letterSpacing: 1.3, fontWeight: FontWeight.w600)),
  );
}

Widget pill(String text, {bool on = false, VoidCallback? onTap, Color color = kPrimary}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: on ? color.withAlpha(40) : kPanel2,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: on ? color : kLine),
      ),
      child: Text(text, style: TextStyle(color: on ? color : kText, fontSize: 13.5, fontWeight: FontWeight.w500)),
    ),
  );
}

Widget empty(String text) {
  return Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Center(child: Text(text, textAlign: TextAlign.center, style: tLow)));
}

InputDecoration fieldLook(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: kLow),
    filled: true,
    fillColor: kPanel2,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
  );
}

/// One row in a list: a title, a smaller line under it, and something at the end.
Widget rowItem(String title, String sub, {Widget? end, VoidCallback? onTap}) {
  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: tBody),
                if (sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub, style: tLow)),
              ],
            ),
          ),
          if (end != null) Padding(padding: const EdgeInsets.only(left: 10), child: end),
        ],
      ),
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body, String yesText) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext c) => AlertDialog(
      backgroundColor: kPanel,
      title: Text(title, style: tHead),
      content: Text(body, style: tBody),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel', style: TextStyle(color: kLow))),
        TextButton(onPressed: () => Navigator.of(c).pop(true), child: Text(yesText, style: const TextStyle(color: kBad))),
      ],
    ),
  );
  return ok == true;
}
