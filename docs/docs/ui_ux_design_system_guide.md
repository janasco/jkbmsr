# JKBMSR Design System: Uniformity & Intent

This document defines the unified UI/UX design rules for the **JKBMSR** ecosystem (including `jkbmsr-web` and `jkbmsr-pro`). 
Consistency is the foundation of a professional product. This design system ensures all platforms feel like they were created by a single designer using one cohesive system.

---

## 1. Unified Brand Palette

The color scheme is designed for a **dark-mode first, high-performance industrial aesthetic**. Avoid neon-heavy cyber themes or brown-beige solar aesthetics.

### Color Tokens

| Token | HEX | Web (Tailwind) | Mobile (Dart) | Primary Intent |
| :--- | :--- | :--- | :--- | :--- |
| `carbon-950` | `#080B0E` | `bg-canvas` | `JKBMSRTokens.carbon950` | Primary app canvas background. |
| `carbon-900` | `#10151A` | `bg-panel` | `JKBMSRTokens.carbon900` | Card, container, and dialog background. |
| `graphite-800` | `#1C242B` | `border-line` | `JKBMSRTokens.graphite800`| Borders, grid-lines, divider margins. |
| `steel-500` | `#7E8B96` | `text-muted` | `JKBMSRTokens.steel500` | Secondary metadata and labels. |
| `steel-200` | `#D8E0E6` | `text-secondary` | `JKBMSRTokens.steel200` | Main body copy, headings, readouts. |
| `energy-500` | `#17C964` | `text-signal` | `JKBMSRTokens.energy500` | Charge states, online status, healthy cells. |
| `signal-500` | `#2F9BFF` | `text-info` | `JKBMSRTokens.signal500` | Interactive triggers, command links, focus rings. |
| `warning-500` | `#F5A524` | `text-warning` | `JKBMSRTokens.warning500` | Cell imbalance warnings, high temperatures. |
| `critical-500`| `#EF4444` | `text-danger` | `JKBMSRTokens.critical500`| Under-voltage, protections triggered, system offline. |

---

## 2. Core UI Components Mapping

To preserve uniformity, use these standardized component definitions across all applications:

### 1. Navigation Bar
*   **Web**: Inline top navigation on landing screens; persistent top/left navigation in the main shell.
*   **Mobile**: Bottom navigation layout with high-contrast active icons matching `signal-500` highlights.

### 2. Sidebar
*   **Web**: Left-side vertical menu collapsing into a menu button on tablet widths.
*   **Mobile**: Collapsible side drawer matching desktop sidebar item alignments.

### 3. Breadcrumb
*   **Web/Mobile**: Simple, non-intrusive hierarchy tags (e.g., `Devices > JK-BMS-01 > Settings`) located above page headers.

### 4. Tabs
*   **Web/Mobile**: High-contrast inline tab triggers inside card sections to toggle views (e.g., Overview vs. Cell Voltages).

### 5. Segmented Control
*   **Web/Mobile**: Inline selector buttons with pill-shaped background slides when switching config categories.

### 6. Combobox
*   **Web/Mobile**: Searchable options selector showing dropdown list overlays on typing filters.

### 7. Command Palette
*   **Web/Mobile**: Universal `CMD+K` input modal enabling rapid navigation to specific gateway devices or telemetry search pages.

### 8. Data Table
*   **Web/Mobile**: Clean table arrays with monospace alignment for floats and technical values.

### 9. Accordion
*   **Web/Mobile**: Expandable sections for viewing cell limits, system logs, or detailed hardware specifications.

### 10. Popover
*   **Web/Mobile**: Small hover card overlays displaying metadata details when hovering indicators.

### 11. Tooltip
*   **Web/Mobile**: Simple, descriptive overlays explaining battery status definitions or warning descriptions.

### 12. Drawer / Sheet
*   **Web/Mobile**: Bottom-sheet slides on mobile or right-sheet slides on web for settings configurations.

### 13. Dialog
*   **Web/Mobile**: Confirm modals used when executing critical functions like OTA flashes or device deletion.

### 14. Toast
*   **Web/Mobile**: Small notification chips that slide into view to confirm settings saves or alert updates.

### 15. Skeleton
*   **Web/Mobile**: Shimmer container placeholders displaying during asynchronous API load cycles.

### 16. Pagination
*   **Web/Mobile**: Centered number controls used to manage long feeds of alerts or history logs.

### 17. Empty State
*   **Web/Mobile**: Clear, friendly empty-state illustrations with explicit action CTAs (e.g., "Pair a Device").

### 18. Date Picker
*   **Web/Mobile**: Calendar grid modals used to select date windows for telemetry history chart reviews.

### 19. Status Badge
*   **Web/Mobile**: Clean pill-shaped indicators showing `Online`, `Offline`, or `Warning` status.

### 20. Dropdown Menu
*   **Web/Mobile**: Compact options menus anchored to control buttons.

---

## 3. Font Families & Scales

*   **Main Typeface**: `Geist Sans` or `Inter` for layout labels, interface headers, and marketing copy.
*   **Technical Typeface**: `JetBrains Mono` or `IBM Plex Mono` for telemetry numbers, packet readouts, cell voltages, and device IDs.
