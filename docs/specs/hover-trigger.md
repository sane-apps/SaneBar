# Feature Spec: Show on Hover

**Feature**: Auto-show hidden menu bar items when mouse hovers over the menu bar.
**Status**: Implemented (Phase 5)

## 1. Overview
Allows users to reveal hidden icons by simply moving their mouse to the menu bar area, without clicking.

## 2. Technical Implementation
- **Detection**: `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)`
- **Safety**: No `CGEvent` simulation. No cursor warping. Pure read-only monitoring.
- **Throttling**: Checks at 10Hz (0.1s interval) to minimize CPU usage.

## 3. Privacy Impact
- **Monitoring**: Uses global event monitor which requires "Accessibility" permission.
- **Data**: Mouse coordinates are processed locally in ephemeral memory. No logging or transmission.
- **Sandboxing**: Requires App Sandbox entitlement exception (already granted for other features).

## 4. Accessibility (A11y)
- **Interaction**: Alternative to clicking for users with motor difficulties.
- **VoiceOver**: No specific impact, visual-only trigger.

## 5. Configuration
- **Settings**:
  - `showOnHover` (Bool): Master toggle.
  - `hoverDelay` (TimeInterval): 0.1s - 1.0s slider.
