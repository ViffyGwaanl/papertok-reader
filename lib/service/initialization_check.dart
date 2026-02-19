import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/version_check_type.dart';
import 'package:anx_reader/utils/app_version.dart';
import 'package:anx_reader/utils/log/common.dart';

class InitializationCheck {
  static String? _lastVersion;
  static String? _currentVersion;

  static Future<String> get lastVersion async {
    if (_lastVersion == null) {
      await _checkVersion();
    }
    return _lastVersion!;
  }

  static Future<String> get currentVersion async {
    if (_currentVersion == null) {
      await _checkVersion();
    }
    return _currentVersion!;
  }

  static Future<void> check() async {
    final result = await _checkVersion();
    AnxLog.info('Version check result: $result');
    if (result == VersionCheckType.firstLaunch) {
      _handleFirstLaunch();
    } else if (result == VersionCheckType.updated) {
      _handleUpdateAvailable();
    } else {
      _handleNormalStartup();
    }
  }

  static Future<VersionCheckType> _checkVersion() async {
    _lastVersion = Prefs().lastAppVersion;
    _currentVersion = await getAppVersion();
    if (_lastVersion == null) {
      return VersionCheckType.firstLaunch;
    } else {
      if (_lastVersion != _currentVersion) {
        return VersionCheckType.updated;
      } else {
        return VersionCheckType.normal;
      }
    }
  }

  static Future<void> _handleFirstLaunch() async {
    AnxLog.info('First launch detected, skipping onboarding');
    final cv = await currentVersion;
    Prefs().lastAppVersion = cv;
  }

  static Future<void> _handleUpdateAvailable() async {
    final cv = await currentVersion;
    AnxLog.info('Version update detected, skipping changelog');
    Prefs().lastAppVersion = cv;
  }

  static void _handleNormalStartup() {
    AnxLog.info('Normal startup, proceeding to main app');
  }
}
