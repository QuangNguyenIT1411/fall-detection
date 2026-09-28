import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

import '../core/config/mqtt_config.dart';
import '../models/realtime_update.dart';
import '../models/telemetry.dart';
import 'telemetry_data_source.dart';

class MqttService implements TelemetryDataSource {
  MqttService(this.config);

  final MqttConfig config;
  final _updatesController = StreamController<RealtimeUpdate>.broadcast();
  final _reconnectDelays = const [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  MqttBrowserClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>?
  _messageSubscription;
  Timer? _reconnectTimer;
  var _reconnectAttempt = 0;
  var _connecting = false;
  var _isConnected = false;
  var _manualDisconnect = false;
  var _disposed = false;

  @override
  TelemetrySource get source => TelemetrySource.mqtt;

  @override
  String get deviceCode => config.deviceCode;

  @override
  Stream<RealtimeUpdate> get updates => _updatesController.stream;

  @override
  bool get supportsSimulation => false;

  @override
  bool get isSimulating => false;

  @override
  Future<void> start() => connect();

  Future<void> connect({bool isReconnect = false}) async {
    if (_disposed || _connecting) return;
    _manualDisconnect = false;
    _connecting = true;
    _isConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _emitBrokerState(
      isReconnect
          ? BrokerConnectionState.reconnecting
          : BrokerConnectionState.connecting,
    );

    final clientId = 'fallguard-web-${DateTime.now().microsecondsSinceEpoch}';
    debugPrint(
      'MQTT Web connect: host=${config.host.trim()} port=${config.port} '
      'path=${config.normalizedPath} tls=${config.useTls} '
      'url=${config.websocketUrl} clientId=$clientId',
    );

    await _messageSubscription?.cancel();
    _messageSubscription = null;
    final previousClient = _client;
    if (previousClient != null) {
      previousClient.onConnected = null;
      previousClient.onDisconnected = null;
      previousClient.disconnect();
    }

    final client =
        MqttBrowserClient.withPort(
            config.websocketUrl,
            clientId,
            config.port,
            maxConnectionAttempts: 1,
          )
          ..logging(on: false, logPayloads: false)
          ..setProtocolV311()
          ..keepAlivePeriod = 20
          ..connectTimeoutPeriod = 5000
          ..autoReconnect = false
          ..websocketProtocols = MqttClientConstants.protocolsSingleDefault
          ..connectionMessage = MqttConnectMessage()
              .withClientIdentifier(clientId)
              .startClean()
              .withWillQos(MqttQos.atMostOnce);

    client.onConnected = () => _handleConnected(client);
    client.onDisconnected = () => _handleDisconnected(client);
    client.onFailedConnectionAttempt = (attempt) {
      debugPrint('MQTT connection attempt failed: attempt=$attempt');
    };
    client.onSubscribed = (topic) {
      debugPrint('MQTT subscribed: $topic');
    };
    client.onSubscribeFail = (topic) {
      debugPrint('MQTT subscribe failed: $topic');
    };
    _client = client;

    try {
      final result = await client.connect(config.username, config.password);
      if (result?.state != MqttConnectionState.connected) {
        throw StateError(
          'Broker từ chối kết nối MQTT: state=${result?.state}, '
          'returnCode=${result?.returnCode}',
        );
      }
      debugPrint(
        'MQTT connected: state=${result?.state} '
        'returnCode=${result?.returnCode}',
      );
      _handleConnected(client);
    } catch (error) {
      final status = client.connectionStatus;
      debugPrint('MQTT connect failed: ${error.runtimeType}; '
          'state=${status?.state}; returnCode=${status?.returnCode}');
      if (identical(client, _client)) {
        _scheduleReconnect('Không thể kết nối broker.');
      }
    } finally {
      _connecting = false;
    }
  }

  void _handleConnected(MqttBrowserClient client) {
    if (_disposed ||
        !identical(client, _client) ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    if (_isConnected) return;
    _isConnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _emitBrokerState(BrokerConnectionState.connected);
    _subscribeToTopics();
    _listenForMessages();
  }

  void _subscribeToTopics() {
    final client = _client;
    if (client == null) return;
    client.subscribe(config.telemetryTopic, MqttQos.atMostOnce);
    client.subscribe(config.stateTopic, MqttQos.atMostOnce);
    client.subscribe(config.statusTopic, MqttQos.atMostOnce);
  }

  void _listenForMessages() {
    _messageSubscription?.cancel();
    final stream = _client?.updates;
    if (stream == null) return;
    _messageSubscription = stream.listen((messages) {
      for (final message in messages) {
        final payload = message.payload;
        if (payload is! MqttPublishMessage) continue;
        final text = MqttPublishPayload.bytesToStringAsString(
          payload.payload.message,
        );
        _parseMessage(message.topic, text);
      }
    });
  }

  void _parseMessage(String topic, String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        throw const FormatException('Payload MQTT phải là JSON object.');
      }
      final json = Map<String, dynamic>.from(decoded);
      final RealtimeUpdate update;
      if (topic == config.telemetryTopic) {
        update = TelemetryUpdate(Telemetry.fromJson(json));
      } else if (topic == config.stateTopic) {
        update = FallStateUpdate.fromJson(json);
      } else if (topic == config.statusTopic) {
        update = DeviceStatusUpdate.fromJson(json);
      } else {
        return;
      }

      final messageDeviceId = switch (update) {
        TelemetryUpdate(:final telemetry) => telemetry.deviceId,
        FallStateUpdate(:final deviceId) => deviceId,
        DeviceStatusUpdate(:final deviceId) => deviceId,
        BrokerStatusUpdate() => config.deviceCode,
      };
      if (messageDeviceId != config.deviceCode) {
        throw FormatException('device_id không khớp topic đã cấu hình.');
      }
      _updatesController.add(update);
    } catch (error) {
      debugPrint('Bỏ qua MQTT payload không hợp lệ trên topic $topic: $error');
    }
  }

  void _handleDisconnected(MqttBrowserClient client) {
    if (!identical(client, _client)) return;
    _isConnected = false;
    _messageSubscription?.cancel();
    _messageSubscription = null;
    if (_disposed || _manualDisconnect) {
      _emitBrokerState(BrokerConnectionState.disconnected);
      return;
    }
    _scheduleReconnect('Mất kết nối broker.');
  }

  void _scheduleReconnect(String message) {
    if (_disposed || _manualDisconnect || _reconnectTimer?.isActive == true) {
      return;
    }
    final delay =
        _reconnectDelays[_reconnectAttempt.clamp(
          0,
          _reconnectDelays.length - 1,
        )];
    _reconnectAttempt++;
    _emitBrokerState(BrokerConnectionState.reconnecting, message: message);
    debugPrint(
      'MQTT reconnect scheduled: delay=${delay.inSeconds}s '
      'attempt=$_reconnectAttempt',
    );
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      connect(isReconnect: true);
    });
  }

  void _emitBrokerState(BrokerConnectionState state, {String? message}) {
    if (_updatesController.isClosed) return;
    _updatesController.add(BrokerStatusUpdate(state, message: message));
  }

  @override
  Future<void> simulateFall() async {
    throw UnsupportedError('MQTT mode không hỗ trợ mô phỏng local.');
  }

  @override
  void resetSimulation() {}

  @override
  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    final client = _client;
    if (client != null) {
      client.onConnected = null;
      client.onDisconnected = null;
      client.disconnect();
    }
    _client = null;
    _isConnected = false;
    _emitBrokerState(BrokerConnectionState.disconnected);
  }

  @override
  void dispose() {
    _disposed = true;
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _messageSubscription?.cancel();
    final client = _client;
    if (client != null) {
      client.onConnected = null;
      client.onDisconnected = null;
      client.disconnect();
    }
    _client = null;
    _updatesController.close();
  }
}
