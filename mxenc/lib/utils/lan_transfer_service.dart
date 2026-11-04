import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 局域网换机传输：旧机 HTTP 提供包体 + UDP 广播，新机自动发现并下载。
///
/// 协议（仅内网，明文 HTTP）：
///   UDP 47821  <- 旧机每 1.2s 广播一次 `{"mxenc":"transfer", "port":...}`
///   TCP `<port>` <- 新机 `GET /package?code=xxxxxx` 取回 .mxbak 字节
const int kTransferDiscoveryPort = 47821;

class TransferException implements Exception {
  /// bind_failed / wrong_code / server_error / connect_failed / empty
  final String code;
  TransferException(this.code);
  @override
  String toString() => 'TransferException: $code';
}

class DiscoveredPeer {
  final String name;
  final String address;
  final int port;
  final int size;
  final int itemCount;
  final String platform;
  DateTime lastSeen;

  DiscoveredPeer({
    required this.name,
    required this.address,
    required this.port,
    required this.size,
    required this.itemCount,
    required this.platform,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  String get key => '$address:$port';
}

/// 旧机（发送端）：把已生成的包体通过本机 HTTP 提供给新机下载。
///
/// 包体以文件流的方式发送，不整体读入内存（大书架也能稳定传输）。
class TransferSender {
  final HttpServer _server;
  final RawDatagramSocket _socket;
  final String packagePath;
  final int size;
  final String deviceName;
  final String code;
  final int itemCount;
  final void Function()? onServed;

  Timer? _timer;
  bool _disposed = false;

  TransferSender._({
    required HttpServer server,
    required RawDatagramSocket socket,
    required this.packagePath,
    required this.size,
    required this.deviceName,
    required this.code,
    required this.itemCount,
    this.onServed,
  })  : _server = server,
        _socket = socket;

  static Future<TransferSender> start({
    required String packagePath,
    required String deviceName,
    required String code,
    int itemCount = 0,
    void Function()? onServed,
  }) async {
    final size = await File(packagePath).length();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final sender = TransferSender._(
      server: server,
      socket: socket,
      packagePath: packagePath,
      size: size,
      deviceName: deviceName,
      code: code,
      itemCount: itemCount,
      onServed: onServed,
    );
    server.listen(sender._handle);
    sender._timer =
        Timer.periodic(const Duration(milliseconds: 1200), (_) => sender._broadcast());
    sender._broadcast();
    return sender;
  }

  int get totalBytes => size;

  void _broadcast() {
    if (_disposed) return;
    final payload = utf8.encode(jsonEncode({
      'mxenc': 'transfer',
      'v': 1,
      'name': deviceName,
      'port': _server.port,
      'size': size,
      'itemCount': itemCount,
      'platform': Platform.operatingSystem,
    }));
    try {
      _socket.send(
        payload,
        InternetAddress('255.255.255.255'),
        kTransferDiscoveryPort,
      );
    } catch (_) {
      // 部分网络禁用广播，忽略即可；仍可通过导出的离线包迁移
    }
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.uri.path == '/package') {
        final provided = req.uri.queryParameters['code'] ?? '';
        if (provided != code) {
          req.response.statusCode = HttpStatus.forbidden;
          req.response.write('code mismatch');
          await req.response.close();
          return;
        }
        req.response.headers.contentType = ContentType.binary;
        req.response.contentLength = size;
        try {
          await req.response.addStream(File(packagePath).openRead());
        } catch (_) {
          // 传输被对端中断，忽略
        }
        await req.response.close();
        onServed?.call();
        return;
      }
      if (req.uri.path == '/info') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'name': deviceName,
          'size': size,
          'itemCount': itemCount,
          'platform': Platform.operatingSystem,
        }));
        await req.response.close();
        return;
      }
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    try {
      _socket.close();
    } catch (_) {}
    try {
      await _server.close(force: true);
    } catch (_) {}
  }
}

/// 新机（接收端）：监听广播、自动发现旧机、下载包体。
class TransferReceiver {
  final void Function(List<DiscoveredPeer> peers)? onUpdate;

  RawDatagramSocket? _socket;
  Timer? _cleanupTimer;
  final Map<String, DiscoveredPeer> _peers = {};

  TransferReceiver({this.onUpdate});

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kTransferDiscoveryPort,
        reuseAddress: true,
      );
    } on SocketException {
      throw TransferException('bind_failed');
    }
    _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket!.receive();
      if (datagram == null) return;
      _handleDatagram(datagram);
    });
    _cleanupTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final now = DateTime.now();
      final before = _peers.length;
      _peers.removeWhere(
        (_, peer) => now.difference(peer.lastSeen).inSeconds > 8,
      );
      if (_peers.length != before) _emit();
    });
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final obj = jsonDecode(utf8.decode(datagram.data));
      if (obj is! Map || obj['mxenc'] != 'transfer') return;
      final port = (obj['port'] as num?)?.toInt() ?? 0;
      if (port <= 0) return;
      final peer = DiscoveredPeer(
        name: (obj['name'] ?? '').toString(),
        address: datagram.address.address,
        port: port,
        size: (obj['size'] as num?)?.toInt() ?? 0,
        itemCount: (obj['itemCount'] as num?)?.toInt() ?? 0,
        platform: (obj['platform'] ?? '').toString(),
        lastSeen: DateTime.now(),
      );
      _peers[peer.key] = peer;
      _emit();
    } catch (_) {
      // 非本协议的广播，忽略
    }
  }

  void _emit() {
    final list = _peers.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    onUpdate?.call(List<DiscoveredPeer>.unmodifiable(list));
  }

  /// 下载包体到临时文件，返回文件路径（边收边写，不整体驻留内存）。
  Future<String> download(
    DiscoveredPeer peer,
    String code, {
    void Function(double progress)? onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    final tempDir = await getTemporaryDirectory();
    final target = p.join(
      tempDir.path,
      'mxrecv_${DateTime.now().millisecondsSinceEpoch}.mxbak',
    );
    IOSink? sink;
    try {
      final uri = Uri(
        scheme: 'http',
        host: peer.address,
        port: peer.port,
        path: '/package',
        queryParameters: {'code': code},
      );
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode == HttpStatus.forbidden) {
        throw TransferException('wrong_code');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw TransferException('server_error');
      }
      final total = response.contentLength;
      final file = File(target);
      sink = file.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received == 0) throw TransferException('empty');
      return target;
    } on TransferException {
      try {
        await sink?.close();
      } catch (_) {}
      await _deleteQuietly(target);
      rethrow;
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      await _deleteQuietly(target);
      throw TransferException('connect_failed');
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}
