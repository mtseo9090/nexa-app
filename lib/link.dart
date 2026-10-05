// How the app talks to NEXA on the laptop.
// WifiLink: straight to the laptop (home Wi-Fi), every request signed with the pairing secret.
// RelayLink: through the relay file on the user's website, every message locked with AES-256-GCM.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

/// A pairing code is either the laptop's own address or the away link through the user's website.
final RegExp kLink = RegExp(r'^(?:http://[0-9.]+:[0-9]+/|https://[A-Za-z0-9.-]+/[A-Za-z0-9._~/-]*\?nexa=app)#[0-9a-f]{32}$');

String hexOf(List<int> bytes) {
  final StringBuffer out = StringBuffer();
  for (final int b in bytes) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List sha256Of(String text) => pc.SHA256Digest().process(bytesOf(text));

String hmacHex(String key, String message) {
  final pc.HMac mac = pc.HMac(pc.SHA256Digest(), 64);
  mac.init(pc.KeyParameter(bytesOf(key)));
  return hexOf(mac.process(bytesOf(message)));
}

class RawReply {
  RawReply(this.status, this.bytes, this.type);
  final int status;
  final Uint8List bytes;
  final String type;
}

Future<RawReply> httpSend(HttpClient client, String method, Uri url, Map<String, String> headers, List<int>? body, int seconds) async {
  final Duration limit = Duration(seconds: seconds);
  final HttpClientRequest req = await client.openUrl(method, url).timeout(limit);
  for (final MapEntry<String, String> h in headers.entries) {
    req.headers.set(h.key, h.value);
  }
  if (body != null) {
    req.contentLength = body.length;
    req.add(body);
  }
  final HttpClientResponse res = await req.close().timeout(limit);
  final BytesBuilder all = BytesBuilder();
  await for (final List<int> chunk in res.timeout(limit)) {
    all.add(chunk);
  }
  final ContentType? kind = res.headers.contentType;
  return RawReply(res.statusCode, all.toBytes(), kind == null ? '' : kind.mimeType);
}

dynamic jsonOf(Uint8List bytes) {
  try {
    return jsonDecode(utf8.decode(bytes));
  } catch (_) {
    return null;
  }
}

/// The answer to one request. status 0 means the laptop could not be reached at all.
class Reply {
  Reply(this.status, {this.json, this.bytes});
  final int status;
  final dynamic json;
  final Uint8List? bytes;

  bool get ok => status >= 200 && status < 300;

  Map<String, dynamic> get map {
    final dynamic j = json;
    return j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
  }
}

abstract class Link {
  bool get away;
  String get label;
  Future<bool> reachable();
  Future<Reply> call(String method, String path, [String body = '']);
  void close();
}

Link makeLink(String code) => code.startsWith('https://') ? RelayLink(code) : WifiLink(code);

class WifiLink implements Link {
  WifiLink(String code)
      : base = Uri.parse(code.split('#').first),
        token = code.split('#').last;

  final Uri base;
  final String token;
  final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  double skew = 0;

  String get origin => '${base.scheme}://${base.host}:${base.port}';

  @override
  bool get away => false;

  @override
  String get label => base.host.startsWith('100.') ? 'Tailscale' : 'Home Wi-Fi';

  @override
  Future<bool> reachable() async {
    try {
      final RawReply r = await httpSend(client, 'GET', Uri.parse('$origin/api/time'), const <String, String>{}, null, 4);
      if (r.status != 200) {
        return false;
      }
      final dynamic d = jsonOf(r.bytes);
      if (d is Map && d['t'] is num) {
        skew = (d['t'] as num).toDouble() - DateTime.now().millisecondsSinceEpoch / 1000;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Reply> call(String method, String path, [String body = '']) async {
    final String ts = (DateTime.now().millisecondsSinceEpoch / 1000 + skew).toStringAsFixed(3);
    final Map<String, String> headers = <String, String>{'X-Ts': ts, 'X-Sig': hmacHex(token, '$ts\n$method\n$path\n$body')};
    if (method == 'POST') {
      headers['Content-Type'] = 'application/json';
    }
    try {
      final RawReply r = await httpSend(client, method, Uri.parse('$origin$path'), headers, method == 'POST' ? utf8.encode(body) : null, 12);
      if (r.type == 'image/jpeg') {
        return Reply(r.status, bytes: r.bytes);
      }
      return Reply(r.status, json: jsonOf(r.bytes));
    } catch (_) {
      return Reply(0);
    }
  }

  @override
  void close() => client.close(force: true);
}

class RelayLink implements Link {
  RelayLink(String code)
      : endpoint = code.split('?').first,
        token = code.split('#').last {
    room = hexOf(sha256Of('nexa-room:$token')).substring(0, 32);
    key = sha256Of('nexa-key:$token');
    client.userAgent = 'Mozilla/5.0 (NEXA-AI app)';
  }

  final String endpoint;
  final String token;
  late final String room;
  late final Uint8List key;
  final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  final Map<String, Completer<Map<String, dynamic>?>> waiting = <String, Completer<Map<String, dynamic>?>>{};
  final Random random = Random.secure();
  bool listening = false;
  bool closed = false;
  int drift = 0;
  int seq = 0;

  @override
  bool get away => true;

  @override
  String get label => 'Away link';

  pc.GCMBlockCipher _cipher(bool lock, Uint8List iv) {
    final pc.GCMBlockCipher c = pc.GCMBlockCipher(pc.AESEngine());
    c.init(lock, pc.AEADParameters<pc.KeyParameter>(pc.KeyParameter(key), 128, iv, Uint8List(0)));
    return c;
  }

  String seal(Map<String, dynamic> message) {
    final Uint8List iv = Uint8List(12);
    for (int i = 0; i < 12; i++) {
      iv[i] = random.nextInt(256);
    }
    final Uint8List locked = _cipher(true, iv).process(bytesOf(jsonEncode(message)));
    final Uint8List packed = Uint8List(12 + locked.length);
    packed.setRange(0, 12, iv);
    packed.setRange(12, packed.length, locked);
    return base64Encode(packed);
  }

  Map<String, dynamic>? unseal(String text) {
    try {
      final Uint8List raw = base64Decode(text);
      final Uint8List iv = Uint8List.fromList(raw.sublist(0, 12));
      final Uint8List body = Uint8List.fromList(raw.sublist(12));
      final dynamic d = jsonDecode(utf8.decode(_cipher(false, iv).process(body)));
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> reachable() async {
    try {
      final RawReply r = await httpSend(client, 'GET', Uri.parse('$endpoint?nexa=ping'), const <String, String>{}, null, 10);
      final dynamic d = jsonOf(r.bytes);
      return r.status == 200 && d is Map && d['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Reply> call(String method, String path, [String body = '']) => _call(method, path, body, false);

  Future<Reply> _call(String method, String path, String body, bool again) async {
    seq++;
    final String id = '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$seq-${random.nextInt(1 << 30).toRadixString(36)}';
    final Completer<Map<String, dynamic>?> done = Completer<Map<String, dynamic>?>();
    waiting[id] = done;
    try {
      final String locked = seal(<String, dynamic>{'id': id, 't': DateTime.now().millisecondsSinceEpoch + drift, 'm': method, 'p': path, 'b': body});
      final RawReply sent = await httpSend(client, 'POST', Uri.parse('$endpoint?nexa=send&room=$room&side=pc'), const <String, String>{'Content-Type': 'text/plain'}, utf8.encode(locked), 15);
      if (sent.status != 200) {
        waiting.remove(id);
        return Reply(sent.status == 404 ? 502 : sent.status);   // 404: the laptop has not opened the line
      }
    } catch (_) {
      waiting.remove(id);
      return Reply(0);
    }
    _listen();
    final Map<String, dynamic>? o = await done.future.timeout(const Duration(seconds: 30), onTimeout: () => null);
    waiting.remove(id);
    if (o == null) {
      return Reply(504);
    }
    final dynamic code = o['s'];
    final int status = code is int ? code : 500;
    final dynamic j = o['j'];
    if (status == 409 && !again && j is Map && j['now'] is num) {
      drift = (j['now'] as num).toInt() - DateTime.now().millisecondsSinceEpoch;   // this phone's clock is off: correct and retry once
      return _call(method, path, body, true);
    }
    final dynamic img = o['img'];
    if (img is String) {
      return Reply(status, bytes: base64Decode(img));
    }
    return Reply(status, json: j);
  }

  /// One open line that brings the laptop's answers back while any request is waiting.
  Future<void> _listen() async {
    if (listening) {
      return;
    }
    listening = true;
    int bad = 0;
    while (waiting.isNotEmpty && !closed) {
      try {
        final Uri url = Uri.parse('$endpoint?nexa=recv&room=$room&side=app&wait=20&_=${DateTime.now().millisecondsSinceEpoch}');
        final RawReply r = await httpSend(client, 'GET', url, const <String, String>{}, null, 32);
        final dynamic d = jsonOf(r.bytes);
        if (d is! Map) {
          throw const FormatException('not a relay answer');
        }
        bad = 0;
        if (d['m'] is List) {
          for (final dynamic m in d['m'] as List<dynamic>) {
            final Map<String, dynamic>? o = m is String ? unseal(m) : null;
            if (o == null) {
              continue;
            }
            final Completer<Map<String, dynamic>?>? w = waiting.remove(o['id']);
            if (w != null && !w.isCompleted) {
              w.complete(o);
            }
          }
        }
      } catch (_) {
        bad++;
        if (bad > 3) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    }
    listening = false;
  }

  @override
  void close() {
    closed = true;
    client.close(force: true);
  }
}
