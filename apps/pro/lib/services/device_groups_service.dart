import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing device groups. Allows users to organize their
/// gateways into logical groups (e.g., "House", "Workshop", "RV").
/// Groups are stored locally and synced with the device list.
class DeviceGroupsService {
  static const String _prefsKey = 'jkbmsr.deviceGroups';

  static final DeviceGroupsService instance = DeviceGroupsService._();
  DeviceGroupsService._();

  List<DeviceGroup> _groups = [];

  /// Load groups from local storage.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_prefsKey);
    if (jsonStr != null) {
      try {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        _groups = list.map((item) => DeviceGroup.fromJson(item as Map<String, dynamic>)).toList();
      } catch (_) {
        _groups = [];
      }
    }
  }

  /// Get all groups.
  List<DeviceGroup> get groups => List.unmodifiable(_groups);

  /// Get a group by ID.
  DeviceGroup? getGroup(String id) {
    try {
      return _groups.firstWhere((g) => g.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get the group for a specific device.
  DeviceGroup? getGroupForDevice(String deviceId) {
    try {
      return _groups.firstWhere((g) => g.deviceIds.contains(deviceId));
    } catch (_) {
      return null;
    }
  }

  /// Create a new group.
  Future<DeviceGroup> createGroup({
    required String name,
    String? color,
    List<String> deviceIds = const [],
  }) async {
    final group = DeviceGroup(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      color: color,
      deviceIds: List.from(deviceIds),
    );
    _groups.add(group);
    await _save();
    return group;
  }

  /// Update a group.
  Future<void> updateGroup(DeviceGroup group) async {
    final index = _groups.indexWhere((g) => g.id == group.id);
    if (index != -1) {
      _groups[index] = group;
      await _save();
    }
  }

  /// Delete a group.
  Future<void> deleteGroup(String groupId) async {
    _groups.removeWhere((g) => g.id == groupId);
    await _save();
  }

  /// Add a device to a group.
  Future<void> addDeviceToGroup(String groupId, String deviceId) async {
    final group = getGroup(groupId);
    if (group != null && !group.deviceIds.contains(deviceId)) {
      group.deviceIds.add(deviceId);
      await _save();
    }
  }

  /// Remove a device from a group.
  Future<void> removeDeviceFromGroup(String groupId, String deviceId) async {
    final group = getGroup(groupId);
    if (group != null) {
      group.deviceIds.remove(deviceId);
      await _save();
    }
  }

  /// Remove a device from all groups (used when deleting a device).
  Future<void> removeDeviceFromAllGroups(String deviceId) async {
    for (final group in _groups) {
      group.deviceIds.remove(deviceId);
    }
    await _save();
  }

  /// Get devices that are not in any group.
  List<String> getUngroupedDeviceIds(List<String> allDeviceIds) {
    final groupedIds = _groups.expand((g) => g.deviceIds).toSet();
    return allDeviceIds.where((id) => !groupedIds.contains(id)).toList();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_groups.map((g) => g.toJson()).toList());
    await prefs.setString(_prefsKey, jsonStr);
  }
}

/// A group of devices.
class DeviceGroup {
  final String id;
  final String name;
  final String? color;
  final List<String> deviceIds;

  DeviceGroup({
    required this.id,
    required this.name,
    this.color,
    List<String>? deviceIds,
  }) : deviceIds = deviceIds ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (color != null) 'color': color,
        'deviceIds': deviceIds,
      };

  factory DeviceGroup.fromJson(Map<String, dynamic> json) => DeviceGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        color: json['color'] as String?,
        deviceIds: (json['deviceIds'] as List<dynamic>?)
                ?.map((item) => item as String)
                .toList() ??
            [],
      );
}
