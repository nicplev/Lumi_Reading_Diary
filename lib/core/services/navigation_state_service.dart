import 'package:flutter/foundation.dart';

/// Temporary service to handle passing complex objects during navigation
/// This is a workaround for GoRouter's limitation with serializing complex types
class NavigationStateService {
  static final NavigationStateService _instance = NavigationStateService._internal();
  factory NavigationStateService() => _instance;
  NavigationStateService._internal();

  // Temporary storage for navigation data
  Map<String, dynamic>? _tempData;

  void setTempData(Map<String, dynamic> data) {
    debugPrint('NavigationStateService: setTempData called with ${data.keys}');
    _tempData = data;
    debugPrint('NavigationStateService: _tempData is now: ${_tempData != null ? "not null" : "null"}');
  }

  Map<String, dynamic>? getTempData() {
    debugPrint('NavigationStateService: getTempData called, _tempData is: ${_tempData != null ? "not null" : "null"}');
    final data = _tempData;
    _tempData = null; // Clear after reading
    return data;
  }

  void clearTempData() {
    _tempData = null;
  }
}
