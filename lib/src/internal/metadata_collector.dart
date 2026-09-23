import 'dart:io';
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'sdk_info.dart';

class MetadataCollector {
  static Future<Map<String, dynamic>> collect() async {
    final packageInfo = await PackageInfo.fromPlatform();

    Map<String, dynamic> os;
    Map<String, dynamic> device;

    if (!kIsWeb && Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      os = {
        'name': 'Android',
        'version': info.version.release,
        'sdkInt': info.version.sdkInt,
      };
      device = {
        'manufacturer': info.manufacturer,
        'model': info.model,
        'brand': info.brand,
        'type': _androidDeviceType(),
      };
    } else if (!kIsWeb && Platform.isIOS) {
      final info = await DeviceInfoPlugin().iosInfo;
      os = {
        'name': 'iOS',
        'version': info.systemVersion,
      };
      device = {
        'model': info.model,
        'type': info.model.toLowerCase().contains('ipad') ? 'tablet' : 'mobile',
      };
    } else {
      os = {
        'name': kIsWeb ? 'web' : Platform.operatingSystem,
        if (!kIsWeb) 'version': Platform.operatingSystemVersion,
      };
      device = {'type': 'unknown'};
    }

    return {
      'os': os,
      'device': device,
      'screen': _screenInfo(),
      'locale': _localeInfo(),
      'app': {
        'packageName': packageInfo.packageName,
        'versionName': packageInfo.version,
        'versionCode': packageInfo.buildNumber,
      },
      'sdk': sdkName,
      'sdkVersion': sdkVersion,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static Map<String, dynamic> _screenInfo() {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) return {};
    final view = views.first;
    return {
      'widthPx': view.physicalSize.width.toInt(),
      'heightPx': view.physicalSize.height.toInt(),
      'density': view.devicePixelRatio,
    };
  }

  static Map<String, dynamic> _localeInfo() {
    final locale = ui.PlatformDispatcher.instance.locale;
    return {
      'language': locale.languageCode,
      'country': locale.countryCode ?? '',
      'timezone': DateTime.now().timeZoneName,
    };
  }

  static String _androidDeviceType() {
    // Tablets typically have a smallest screen width >= 600 dp.
    // dp = physical px / devicePixelRatio (the logical display scale factor).
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) return 'mobile';
    final view = views.first;
    final size = view.physicalSize;
    final shortSidePx = size.height < size.width ? size.height : size.width;
    final shortSideDp = shortSidePx / view.devicePixelRatio;
    return shortSideDp >= 600 ? 'tablet' : 'mobile';
  }
}
