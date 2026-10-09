import 'package:flutter/material.dart';
import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';
import '../../../utils/haptics.dart';

// ==========================================
// 1. NAVIGATION BAR
// ==========================================
class JKBMSRNavigationBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  const JKBMSRNavigationBar({
    Key? key,
    required this.title,
    this.actions,
    this.leading,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title, style: JKBMSRTypography.sectionHeading),
      actions: actions,
      leading: leading,
      backgroundColor: context.colors.canvas,
      elevation: 0,
      shape: Border(
        bottom: BorderSide(color: context.colors.line, width: 1.0),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// ==========================================
// 2. SIDEBAR
// ==========================================
class JKBMSRSidebar extends StatelessWidget {
  final String currentRoute;
  final Function(String) onNavigate;

  const JKBMSRSidebar({
    Key? key,
    required this.currentRoute,
    required this.onNavigate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.panel,
      child: SizedBox(
        width: 260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(JKBMSRTokens.space24),
              child: Text(
                'JK BMS Remote',
                style: JKBMSRTypography.pageHeading.copyWith(
                  color: context.colors.accent,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Divider(color: context.colors.line),
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(vertical: JKBMSRTokens.space8),
                children: [
                  _buildItem(context, Icons.devices_other_outlined, 'Gateways',
                      '/devices'),
                  _buildItem(context, Icons.dashboard_outlined, 'Dashboard',
                      '/dashboard'),
                  _buildItem(context, Icons.battery_charging_full_outlined,
                      'Cell Voltages', '/cells'),
                  _buildItem(context, Icons.warning_amber_outlined, 'Alerts',
                      '/alerts'),
                  _buildItem(context, Icons.settings_outlined, 'Settings',
                      '/settings'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(
      BuildContext context, IconData icon, String title, String route) {
    final isSelected = currentRoute == route;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? context.colors.accent : context.colors.textMuted,
      ),
      title: Text(
        title,
        style: JKBMSRTypography.body.copyWith(
          color: isSelected
              ? context.colors.textSecondary
              : context.colors.textMuted,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      selected: isSelected,
      selectedTileColor: context.colors.line.withValues(alpha: 0.5),
      onTap: () => onNavigate(route),
    );
  }
}

// ==========================================
// 3. BREADCRUMB
// ==========================================
class JKBMSRBreadcrumb extends StatelessWidget {
  final List<String> paths;
  final Function(int) onTap;

  const JKBMSRBreadcrumb({
    Key? key,
    required this.paths,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(paths.length * 2 - 1, (index) {
          if (index.isOdd) {
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: JKBMSRTokens.space4),
              child: Icon(
                Icons.chevron_right,
                size: 16,
                color: context.colors.textMuted,
              ),
            );
          }
          final pathIndex = index ~/ 2;
          final isLast = pathIndex == paths.length - 1;
          return GestureDetector(
            onTap: isLast ? null : () => onTap(pathIndex),
            child: SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  paths[pathIndex],
                  style: JKBMSRTypography.label.copyWith(
                    color: isLast
                        ? context.colors.textSecondary
                        : context.colors.textMuted,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ==========================================
// 4. TABS
// ==========================================
class JKBMSRTabs extends StatelessWidget {
  final List<String> tabTitles;
  final int selectedIndex;
  final Function(int) onTabSelected;

  const JKBMSRTabs({
    Key? key,
    required this.tabTitles,
    required this.selectedIndex,
    required this.onTabSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.colors.line, width: 1.0),
        ),
      ),
      child: Row(
        children: List.generate(tabTitles.length, (index) {
          final isSelected = selectedIndex == index;
          return Expanded(
            child: InkWell(
              onTap: () {
                JKBMSRHaptics.lightImpact();
                onTabSelected(index);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: JKBMSRTokens.space12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected
                          ? context.colors.accent
                          : Colors.transparent,
                      width: 2.0,
                    ),
                  ),
                ),
                child: Text(
                  tabTitles[index],
                  textAlign: TextAlign.center,
                  style: JKBMSRTypography.body.copyWith(
                    color: isSelected
                        ? context.colors.textSecondary
                        : context.colors.textMuted,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ==========================================
// 5. SEGMENTED CONTROL
// ==========================================
class JKBMSRSegmentedControl<T> extends StatelessWidget {
  final Map<T, String> options;
  final T selectedValue;
  final Function(T) onSelected;

  const JKBMSRSegmentedControl({
    Key? key,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(JKBMSRTokens.space4),
      decoration: BoxDecoration(
        color: context.colors.panel,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
        border: Border.all(color: context.colors.line),
      ),
      child: Row(
        children: options.entries.map((entry) {
          final isSelected = entry.key == selectedValue;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                JKBMSRHaptics.lightImpact();
                onSelected(entry.key);
              },
              child: SizedBox(
                height: 48,
                child: Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: JKBMSRTokens.space8),
                    decoration: BoxDecoration(
                      color:
                          isSelected ? context.colors.line : Colors.transparent,
                      borderRadius: BorderRadius.circular(JKBMSRTokens.radius4),
                    ),
                    child: Text(
                      entry.value,
                      textAlign: TextAlign.center,
                      style: JKBMSRTypography.label.copyWith(
                        color: isSelected
                            ? context.colors.textSecondary
                            : context.colors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ==========================================
// 6. COMBOBOX & 7. COMMAND PALETTE
// ==========================================
class JKBMSRCombobox<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) itemToString;
  final T? selectedItem;
  final Function(T) onSelected;
  final String placeholder;

  const JKBMSRCombobox({
    Key? key,
    required this.items,
    required this.itemToString,
    required this.onSelected,
    this.selectedItem,
    this.placeholder = 'Select item...',
  }) : super(key: key);

  @override
  State<JKBMSRCombobox<T>> createState() => _JKBMSRComboboxState<T>();
}

class _JKBMSRComboboxState<T> extends State<JKBMSRCombobox<T>> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showSearchSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: JKBMSRTokens.space16,
          vertical: JKBMSRTokens.space12,
        ),
        decoration: BoxDecoration(
          color: context.colors.panel,
          borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
          border: Border.all(color: context.colors.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.selectedItem != null
                  ? widget.itemToString(widget.selectedItem!)
                  : widget.placeholder,
              style: JKBMSRTypography.body.copyWith(
                color: widget.selectedItem != null
                    ? context.colors.textSecondary
                    : context.colors.textMuted,
              ),
            ),
            Icon(Icons.unfold_more, color: context.colors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  void _showSearchSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return JKBMSRCommandPalette<T>(
          items: widget.items,
          itemToString: widget.itemToString,
          onSelected: (item) {
            widget.onSelected(item);
            Navigator.pop(context);
          },
          placeholder: widget.placeholder,
        );
      },
    );
  }
}

class JKBMSRCommandPalette<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) itemToString;
  final Function(T) onSelected;
  final String placeholder;

  const JKBMSRCommandPalette({
    Key? key,
    required this.items,
    required this.itemToString,
    required this.onSelected,
    required this.placeholder,
  }) : super(key: key);

  @override
  State<JKBMSRCommandPalette<T>> createState() =>
      _JKBMSRCommandPaletteState<T>();
}

class _JKBMSRCommandPaletteState<T> extends State<JKBMSRCommandPalette<T>> {
  final TextEditingController _searchController = TextEditingController();
  List<T> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _searchController.addListener(_filter);
  }

  void _filter() {
    setState(() => _applyFilter(_searchController.text));
  }

  void _applyFilter(String text) {
    final query = text.toLowerCase();
    _filteredItems = widget.items
        .where(
            (item) => widget.itemToString(item).toLowerCase().contains(query))
        .toList();
  }

  @override
  void didUpdateWidget(covariant JKBMSRCommandPalette<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Items can arrive after the sheet opens (e.g. a live gateway fetch);
    // re-apply the current query so they show up without a keystroke.
    if (!identical(oldWidget.items, widget.items)) {
      _applyFilter(_searchController.text);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Material, not Container: the result ListTiles below paint their ink
    // splash on the nearest Material ancestor, and a Container background sits
    // in between and hides it. Same reason as JKBMSRAccordion.
    return Material(
      color: context.colors.canvas,
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(JKBMSRTokens.radius12)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(JKBMSRTokens.radius12)),
            border: Border(top: BorderSide(color: context.colors.line)),
          ),
          child: Column(
            children: [
              // Bar Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(
                      vertical: JKBMSRTokens.space12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.line,
                    borderRadius: BorderRadius.circular(JKBMSRTokens.radius2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: JKBMSRTokens.space16),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixIcon:
                        Icon(Icons.search, color: context.colors.textMuted),
                    hintText: 'Search or type a command...',
                    hintStyle: JKBMSRTypography.bodySecondary,
                  ),
                ),
              ),
              const SizedBox(height: JKBMSRTokens.space8),
              Expanded(
                child: ListView.builder(
                  itemCount: _filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = _filteredItems[index];
                    return ListTile(
                      title: Text(
                        widget.itemToString(item),
                        style: JKBMSRTypography.body,
                      ),
                      onTap: () => widget.onSelected(item),
                      hoverColor: context.colors.line,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 8. DATA TABLE
// ==========================================
class JKBMSRDataTable extends StatelessWidget {
  final List<String> headers;
  final List<List<Widget>> rows;

  const JKBMSRDataTable({
    Key? key,
    required this.headers,
    required this.rows,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: context.colors.line, width: 0.5),
        bottom: BorderSide(color: context.colors.line, width: 0.5),
      ),
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: context.colors.line, width: 1.0)),
          ),
          children: headers.map((header) {
            return Padding(
              padding: const EdgeInsets.symmetric(
                vertical: JKBMSRTokens.space12,
                horizontal: JKBMSRTokens.space16,
              ),
              child: Text(
                header,
                style: JKBMSRTypography.label,
              ),
            );
          }).toList(),
        ),
        ...rows.map((row) {
          return TableRow(
            children: row.map((cell) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: JKBMSRTokens.space12,
                  horizontal: JKBMSRTokens.space16,
                ),
                child: cell,
              );
            }).toList(),
          );
        }).toList(),
      ],
    );
  }
}

// ==========================================
// 9. ACCORDION
// ==========================================
class JKBMSRAccordion extends StatefulWidget {
  final String title;
  final Widget content;

  const JKBMSRAccordion({
    Key? key,
    required this.title,
    required this.content,
  }) : super(key: key);

  @override
  State<JKBMSRAccordion> createState() => _JKBMSRAccordionState();
}

class _JKBMSRAccordionState extends State<JKBMSRAccordion> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    // Material, not Container: the ListTile paints its ink splash on the
    // nearest Material ancestor. A Container/DecoratedBox background sits
    // between the two and hides it, so tapping the header produced no visible
    // feedback — and Flutter asserts on it in debug builds. Material with
    // transparent ink keeps the same look and the same splash.
    return Material(
      color: context.colors.panel,
      borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
          border: Border.all(color: context.colors.line),
        ),
        child: Column(
          children: [
            ListTile(
              title: Text(widget.title,
                  style: JKBMSRTypography.body
                      .copyWith(fontWeight: FontWeight.w500)),
              trailing: AnimatedRotation(
                turns: _isExpanded ? 0.5 : 0.0,
                duration: JKBMSRTokens.durationFast,
                child: Icon(Icons.keyboard_arrow_down,
                    color: context.colors.textMuted),
              ),
              onTap: () {
                JKBMSRHaptics.lightImpact();
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.all(JKBMSRTokens.space16),
                child: widget.content,
              ),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: JKBMSRTokens.durationNormal,
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 10. POPOVER & 11. TOOLTIP
// ==========================================
class JKBMSRTooltip extends StatelessWidget {
  final String message;
  final Widget child;

  const JKBMSRTooltip({
    Key? key,
    required this.message,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      decoration: BoxDecoration(
        color: context.colors.line,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius4),
        border: Border.all(
            color: context.colors.textMuted.withValues(alpha: 0.5), width: 0.5),
      ),
      textStyle:
          JKBMSRTypography.label.copyWith(color: context.colors.textSecondary),
      child: child,
    );
  }
}

// ==========================================
// 12. DRAWER / SHEET
// ==========================================
class JKBMSRBottomSheet extends StatelessWidget {
  final Widget child;
  final String title;

  const JKBMSRBottomSheet({
    Key? key,
    required this.child,
    required this.title,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.panel,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(JKBMSRTokens.radius16)),
        border: Border(top: BorderSide(color: context.colors.line)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin:
                    const EdgeInsets.symmetric(vertical: JKBMSRTokens.space12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.line,
                  borderRadius: BorderRadius.circular(JKBMSRTokens.radius2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: JKBMSRTokens.space24,
                  vertical: JKBMSRTokens.space8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: JKBMSRTypography.cardHeading),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(Icons.close, color: context.colors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: context.colors.line),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 13. DIALOG
// ==========================================
class JKBMSRDialog extends StatelessWidget {
  final String title;
  final String content;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final String confirmText;
  final String cancelText;

  const JKBMSRDialog({
    Key? key,
    required this.title,
    required this.content,
    required this.onConfirm,
    required this.onCancel,
    this.confirmText = 'Confirm',
    this.cancelText = 'Cancel',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        side: BorderSide(color: context.colors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: JKBMSRTypography.cardHeading),
            const SizedBox(height: JKBMSRTokens.space12),
            Text(content,
                style: JKBMSRTypography.body
                    .copyWith(color: context.colors.textMuted)),
            const SizedBox(height: JKBMSRTokens.space24),
            // Wrap, not Row: two long action labels (e.g. "Sign Out Others" +
            // "Cancel") overflow a phone-width dialog. Wrap keeps them
            // right-aligned on one line when they fit and stacks them when they
            // don't, instead of painting an overflow stripe.
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: JKBMSRTokens.space12,
              runSpacing: JKBMSRTokens.space8,
              children: [
                OutlinedButton(
                  onPressed: onCancel,
                  child: Text(cancelText),
                ),
                ElevatedButton(
                  onPressed: onConfirm,
                  child: Text(confirmText),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 14. TOAST
// ==========================================
class JKBMSRToast {
  static void show(BuildContext context, String message,
      {bool isError = false}) {
    if (isError) {
      JKBMSRHaptics.error();
    } else {
      JKBMSRHaptics.success();
    }
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        padding: EdgeInsets.zero,
        content: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: JKBMSRTokens.space16,
            vertical: JKBMSRTokens.space12,
          ),
          decoration: BoxDecoration(
            color: context.colors.panel,
            borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
            border: Border.all(
              color: isError ? context.colors.critical : context.colors.line,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color:
                    isError ? context.colors.critical : context.colors.accent,
              ),
              const SizedBox(width: JKBMSRTokens.space12),
              Expanded(
                child: Text(
                  message,
                  style: JKBMSRTypography.body.copyWith(fontSize: 14.0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 15. SKELETON
// ==========================================
class JKBMSRSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const JKBMSRSkeleton({
    Key? key,
    this.width = double.infinity,
    this.height = 20.0,
    this.borderRadius = 4.0,
  }) : super(key: key);

  @override
  State<JKBMSRSkeleton> createState() => _JKBMSRSkeletonState();
}

/// Whether the OS asks for reduced motion; safe to read in initState.
bool _reduceMotion() => WidgetsBinding
    .instance.platformDispatcher.accessibilityFeatures.disableAnimations;

class _JKBMSRSkeletonState extends State<JKBMSRSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    if (!_reduceMotion()) _controller.repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: context.colors.line,
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
          ),
        );
      },
    );
  }
}

// ==========================================
// 15b. CONTENT-SHAPED SKELETON PRIMITIVES
// ==========================================
// JKBMSRSkeleton is a single pulsing block. Used alone it says "loading"
// without saying *what* is loading, so the placeholder does not resemble the
// content that replaces it and the layout jumps when data lands. These compose
// it into the shapes the real screens actually render — the same card radius,
// panel/inset surface, padding and line counts — so the loading state is a
// faithful silhouette of the loaded content. None of these animates on its
// own; each inherits the pulse (and its reduced-motion behaviour) from the
// JKBMSRSkeleton blocks inside it.

/// A skeleton-filled stand-in for a real [Card]: same panel colour, 1px line
/// border, corner radius and inner padding, so a loading card occupies the same
/// footprint as the [Card] it becomes. Pass [children] shaped to mirror the
/// real card's rows.
class JKBMSRSkeletonCard extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  /// Surface colour; defaults to the panel colour of a real [Card]. Pass
  /// `context.colors.inset` to mirror an inset sub-surface.
  final Color? color;
  final double? width;
  final CrossAxisAlignment crossAxisAlignment;

  const JKBMSRSkeletonCard({
    Key? key,
    required this.children,
    this.padding = const EdgeInsets.all(JKBMSRTokens.space16),
    this.borderRadius = JKBMSRTokens.radius12,
    this.color,
    this.width,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.colors.panel,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxisAlignment,
        children: children,
      ),
    );
  }
}

/// A silhouette of a common list row: an optional leading icon/avatar square, a
/// title line and a shorter subtitle line, plus an optional trailing
/// value/time block. Used for alert rows, sign-in sessions and similar lists.
class JKBMSRSkeletonListRow extends StatelessWidget {
  final double leadingSize;
  final bool leadingIsCircle;
  final double titleHeight;

  /// Width of the trailing value/time block; 0 hides it.
  final double trailingWidth;

  const JKBMSRSkeletonListRow({
    Key? key,
    this.leadingSize = 20,
    this.leadingIsCircle = true,
    this.titleHeight = 14,
    this.trailingWidth = 64,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leadingSize > 0) ...[
          JKBMSRSkeleton(
            width: leadingSize,
            height: leadingSize,
            borderRadius: leadingIsCircle
                ? JKBMSRTokens.radiusFull
                : JKBMSRTokens.radius8,
          ),
          const SizedBox(width: JKBMSRTokens.space12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              JKBMSRSkeleton(
                  height: titleHeight, borderRadius: JKBMSRTokens.radius4),
              const SizedBox(height: JKBMSRTokens.space8),
              const JKBMSRSkeleton(
                  width: 132,
                  height: 12,
                  borderRadius: JKBMSRTokens.radius4),
            ],
          ),
        ),
        if (trailingWidth > 0) ...[
          const SizedBox(width: JKBMSRTokens.space12),
          JKBMSRSkeleton(
              width: trailingWidth,
              height: 12,
              borderRadius: JKBMSRTokens.radius4),
        ],
      ],
    );
  }
}

/// A silhouette of a small stat/metric tile: a short label line, an optional
/// icon blob, a larger value line and a short sub-value line — the shape of the
/// dashboard's 2x2 metric tiles. [showIcon] adds the trailing icon circle.
class JKBMSRSkeletonStat extends StatelessWidget {
  final bool showIcon;

  const JKBMSRSkeletonStat({
    Key? key,
    this.showIcon = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(JKBMSRTokens.space12),
      decoration: BoxDecoration(
        color: context.colors.inset,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: JKBMSRSkeleton(
                    width: 80, height: 11, borderRadius: JKBMSRTokens.radius4),
              ),
              if (showIcon) ...[
                const SizedBox(width: JKBMSRTokens.space8),
                const JKBMSRSkeleton(
                    width: 22,
                    height: 22,
                    borderRadius: JKBMSRTokens.radiusFull),
              ],
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space4),
          const JKBMSRSkeleton(
              width: 72, height: 20, borderRadius: JKBMSRTokens.radius4),
          const SizedBox(height: JKBMSRTokens.space4),
          const JKBMSRSkeleton(
              width: 88, height: 11, borderRadius: JKBMSRTokens.radius4),
        ],
      ),
    );
  }
}

// ==========================================
// 16. PAGINATION
// ==========================================
class JKBMSRPagination extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const JKBMSRPagination({
    Key? key,
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: currentPage > 1 ? onPrevious : null,
          icon: const Icon(Icons.arrow_back_ios_new, size: 16),
          color: context.colors.textSecondary,
          disabledColor: context.colors.line,
          tooltip: 'Previous page',
        ),
        const SizedBox(width: JKBMSRTokens.space12),
        Text(
          'Page $currentPage of $totalPages',
          style: JKBMSRTypography.bodySecondary,
        ),
        const SizedBox(width: JKBMSRTokens.space12),
        IconButton(
          onPressed: currentPage < totalPages ? onNext : null,
          icon: const Icon(Icons.arrow_forward_ios, size: 16),
          color: context.colors.textSecondary,
          disabledColor: context.colors.line,
          tooltip: 'Next page',
        ),
      ],
    );
  }
}

// ==========================================
// 17. EMPTY STATE
// ==========================================
class JKBMSREmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  const JKBMSREmptyState({
    Key? key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: context.colors.textMuted),
            const SizedBox(height: JKBMSRTokens.space16),
            Text(title, style: JKBMSRTypography.cardHeading),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: JKBMSRTypography.bodySecondary,
            ),
            if (action != null) ...[
              const SizedBox(height: JKBMSRTokens.space24),
              action!,
            ]
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 18. DATE PICKER
// ==========================================
class JKBMSRDatePicker extends StatelessWidget {
  final DateTime? selectedDate;
  final Function(DateTime) onDateSelected;

  const JKBMSRDatePicker({
    Key? key,
    this.selectedDate,
    required this.onDateSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: selectedDate ?? DateTime.now(),
          firstDate: DateTime(2025),
          lastDate: DateTime.now(),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.dark(
                  primary: context.colors.accent,
                  onPrimary: context.colors.canvas,
                  surface: context.colors.panel,
                  onSurface: context.colors.textSecondary,
                ),
              ),
              child: child!,
            );
          },
        );
        if (date != null) {
          onDateSelected(date);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: JKBMSRTokens.space16,
          vertical: JKBMSRTokens.space12,
        ),
        decoration: BoxDecoration(
          color: context.colors.panel,
          borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
          border: Border.all(color: context.colors.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              selectedDate != null
                  ? "${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}"
                  : 'Select Date',
              style: JKBMSRTypography.body.copyWith(
                color: selectedDate != null
                    ? context.colors.textSecondary
                    : context.colors.textMuted,
              ),
            ),
            Icon(Icons.calendar_today,
                color: context.colors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 18b. ALERT BANNER
// ==========================================
/// Semantic tone for [JKBMSRAlertBanner]. [warning] is the calm "something
/// needs your attention but the app still works" case (e.g. the gateway is
/// online but its BMS link is down); [critical] is for a hard failure.
enum JKBMSRAlertTone { warning, critical, accent, signal }

/// Inline alert banner — a calm, non-blocking explanation of a condition the
/// user should know about. It carries no show/hide logic: callers decide when
/// to render it, so the healthy state shows no permanent chrome. Mirrors the
/// warning banner already used on the gateways list, factored out so the two
/// stay visually identical.
class JKBMSRAlertBanner extends StatelessWidget {
  final JKBMSRAlertTone tone;
  final IconData icon;
  final String title;
  final String message;

  /// Optional supporting facts, one per line (e.g. "Last error: …").
  final List<String> details;

  final Widget? action;

  const JKBMSRAlertBanner({
    Key? key,
    required this.icon,
    required this.title,
    required this.message,
    this.tone = JKBMSRAlertTone.warning,
    this.details = const [],
    this.action,
  }) : super(key: key);

  Color _toneColor(BuildContext context) {
    switch (tone) {
      case JKBMSRAlertTone.warning:
        return context.colors.warning;
      case JKBMSRAlertTone.critical:
        return context.colors.critical;
      case JKBMSRAlertTone.accent:
        return context.colors.accent;
      case JKBMSRAlertTone.signal:
        return context.colors.signal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: JKBMSRTokens.space16,
        vertical: JKBMSRTokens.space12,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: JKBMSRTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: JKBMSRTypography.cardHeading.copyWith(color: color),
                ),
                const SizedBox(height: JKBMSRTokens.space4),
                Text(message, style: JKBMSRTypography.bodySecondary),
                for (final detail in details) ...[
                  const SizedBox(height: JKBMSRTokens.space4),
                  Text(
                    detail,
                    style: JKBMSRTypography.label
                        .copyWith(color: context.colors.textMuted),
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: JKBMSRTokens.space8),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 19. STATUS BADGE
// ==========================================
enum JKBMSRStatus {
  online,
  offline,
  charging,
  discharging,
  idle,
  updating,
  maintenance,
  warning,
  critical,
}

class JKBMSRStatusBadge extends StatelessWidget {
  final JKBMSRStatus status;

  const JKBMSRStatusBadge({
    Key? key,
    required this.status,
  }) : super(key: key);

  Color _color(BuildContext context) {
    switch (status) {
      case JKBMSRStatus.online:
      case JKBMSRStatus.charging:
        return context.colors.accent;
      case JKBMSRStatus.discharging:
      case JKBMSRStatus.updating:
        return context.colors.signal;
      case JKBMSRStatus.idle:
      case JKBMSRStatus.warning:
        return context.colors.warning;
      case JKBMSRStatus.critical:
        return context.colors.critical;
      case JKBMSRStatus.maintenance:
      case JKBMSRStatus.offline:
        return context.colors.textMuted;
    }
  }

  String get _label {
    switch (status) {
      case JKBMSRStatus.online:
        return 'Online';
      case JKBMSRStatus.offline:
        return 'Offline';
      case JKBMSRStatus.charging:
        return 'Charging';
      case JKBMSRStatus.discharging:
        return 'Discharging';
      case JKBMSRStatus.idle:
        return 'Idle';
      case JKBMSRStatus.updating:
        return 'Updating';
      case JKBMSRStatus.maintenance:
        return 'Maintenance';
      case JKBMSRStatus.warning:
        return 'Warning';
      case JKBMSRStatus.critical:
        return 'Critical';
    }
  }

  @override
  Widget build(BuildContext context) {
    // The color dot alone isn't accessible to screen readers; the visible
    // text already conveys the same status, so merge them into one
    // announcement instead of exposing the decorative dot separately.
    return Semantics(
      label: '$_label status',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: JKBMSRTokens.space8,
          vertical: JKBMSRTokens.space2,
        ),
        decoration: BoxDecoration(
          color: _color(context).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(JKBMSRTokens.radiusFull),
          border: Border.all(
              color: _color(context).withValues(alpha: 0.4), width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: _color(context),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: JKBMSRTokens.space4),
            Text(
              _label,
              style: JKBMSRTypography.label.copyWith(
                color: _color(context),
                fontSize: 11.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 20. DROPDOWN MENU
// ==========================================
class JKBMSRDropdownMenu<T> extends StatelessWidget {
  final Widget child;
  final List<PopupMenuEntry<T>> items;
  final Function(T) onSelected;

  const JKBMSRDropdownMenu({
    Key? key,
    required this.child,
    required this.items,
    required this.onSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      onSelected: onSelected,
      itemBuilder: (context) => items,
      color: context.colors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
        side: BorderSide(color: context.colors.line),
      ),
      child: child,
    );
  }
}
