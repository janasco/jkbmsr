import 'package:flutter/material.dart';

import '../../../services/device_groups_service.dart';
import '../../../widgets/shared/design_system/colors.dart';
import '../../../widgets/shared/design_system/tokens.dart';

/// Horizontal "All / <group> / New group" filter chips shown above the gateway
/// list.
///
/// Extracted from `DeviceListScreen` so it can be pumped in accessibility
/// tests without the screen's network-backed state. Its height scales with the
/// OS text size (like the rest of the large-text fixes) so the chips neither
/// clip nor shrink below the 48dp tap target at high accessibility scales.
class DeviceGroupFilterChips extends StatelessWidget {
  const DeviceGroupFilterChips({
    super.key,
    required this.groups,
    required this.selectedGroupId,
    required this.onSelected,
    required this.onCreateGroup,
    required this.onEditGroup,
  });

  final List<DeviceGroup> groups;
  final String? selectedGroupId;
  final ValueChanged<String?> onSelected;
  final VoidCallback onCreateGroup;
  final ValueChanged<DeviceGroup> onEditGroup;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return SizedBox(
      height: 48 * textScale,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: JKBMSRTokens.space8),
            child: Center(
              child: ChoiceChip(
                label: const Text('All'),
                selected: selectedGroupId == null,
                onSelected: (_) => onSelected(null),
              ),
            ),
          ),
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(right: JKBMSRTokens.space8),
              child: Center(
                child: GestureDetector(
                  onLongPress: () => onEditGroup(group),
                  child: ChoiceChip(
                    label: Text(group.name),
                    selected: selectedGroupId == group.id,
                    onSelected: (_) =>
                        onSelected(selectedGroupId == group.id ? null : group.id),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: JKBMSRTokens.space8),
            child: Center(
              child: ActionChip(
                avatar: Icon(Icons.add, size: 16, color: context.colors.accent),
                label: const Text('New group'),
                onPressed: onCreateGroup,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
