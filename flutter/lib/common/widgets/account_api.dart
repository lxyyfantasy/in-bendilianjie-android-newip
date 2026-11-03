import 'dart:async';
import 'dart:convert';

import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;

class AccountApiResult {
  final String code;
  final String msg;
  AccountApiResult(this.code, this.msg);

  bool get isOk => code == 'OK';

  factory AccountApiResult.fromJson(Map<String, dynamic> json) {
    return AccountApiResult(
      (json['code'] ?? '').toString(),
      (json['msg'] ?? '').toString(),
    );
  }
}

class DeviceLedgerInfo {
  final int leaseExpire;
  final int hostExpire;
  final String ip;
  final bool leaseExpired;
  DeviceLedgerInfo(
      this.leaseExpire, this.hostExpire, this.ip, this.leaseExpired);

  factory DeviceLedgerInfo.fromJson(Map<String, dynamic> json) {
    return DeviceLedgerInfo(
      (json['lease_expire'] ?? 0) as int,
      (json['host_expire'] ?? 0) as int,
      (json['ip'] ?? '').toString(),
      json['lease_expired'] == true,
    );
  }
}

class AccountApi {
  static const _timeout = Duration(seconds: 10);

  static Future<String> _base() async {
    String host = '';
    try {
      host = await bind.mainGetOption(key: 'external-primary-server');
    } catch (_) {}
    if (host.isEmpty) {
      throw Exception('账号服务地址未配置');
    }
    return 'http://$host:23399';
  }

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
      };

  static Future<DeviceLedgerInfo?> deviceInfo(String deviceId) async {
    try {
      final base = await _base();
      final resp = await http
          .get(
            Uri.parse(
                '$base/api/device/info?device_id=${Uri.encodeQueryComponent(deviceId)}'),
            headers: _headers(),
          )
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is Map<String, dynamic> && data['code'] == 'OK') {
        return DeviceLedgerInfo.fromJson(data);
      }
    } catch (_) {}
    return null;
  }

  static Future<AccountApiResult> activate(
      String code, String kind, String deviceId, String account) async {
    try {
      final base = await _base();
      final resp = await http
          .post(
            Uri.parse('$base/api/activate'),
            headers: _headers(),
            body: jsonEncode({
              'code': code,
              'kind': kind,
              'device_id': deviceId,
              'account': account,
            }),
          )
          .timeout(_timeout);
      return _parse(resp);
    } catch (_) {
      return AccountApiResult('NETWORK_ERROR', '网络异常');
    }
  }

  static Future<AccountApiResult> checkInvite(String invite) async {
    try {
      final base = await _base();
      final resp = await http
          .post(
            Uri.parse('$base/check-invite'),
            headers: _headers(),
            body: jsonEncode({'invite_code': invite}),
          )
          .timeout(_timeout);
      return _parse(resp);
    } catch (_) {
      return AccountApiResult('NETWORK_ERROR', '网络异常');
    }
  }

  static AccountApiResult _parse(http.Response resp) {
    try {
      final data = jsonDecode(resp.body);
      if (data is Map<String, dynamic>) {
        return AccountApiResult.fromJson(data);
      }
    } catch (_) {}
    return AccountApiResult('SERVER_ERROR', '服务器异常');
  }
}