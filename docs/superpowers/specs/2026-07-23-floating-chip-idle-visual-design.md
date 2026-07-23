# Floating Chip Idle Visual Design

## Goal

Make Vordi's draggable chip match the supplied Wispr Flow reference while it is idle and not hovered, so the chip remains legible over both light and dark application backgrounds.

## Reference

The supplied Retina screenshot measures the Wispr Flow chip at 80 x 16 physical pixels, equivalent to 40 x 8 SwiftUI points.

Sampled reference colors:

- Fill: near-black `#0C0C0A`
- Outline: mid-gray `#868685`

## Design

The idle, non-hovered chip will use:

- Width: 40 points
- Height: 8 points
- Shape: continuous capsule
- Fill: `#0C0C0A`
- Outline: `#868685`
- Outline width: 1 point

The opaque near-black body provides contrast on light backgrounds. The mid-gray outline separates the same body from dark backgrounds.

## Scope

Only the idle, non-hovered visual changes.

The following remain unchanged:

- The 64 x 24 point hovered chip with the Vordi logo
- Hover controls and animation
- Dragging and saved chip position
- Permission-warning appearance
- Recording, processing, done, hands-free, and warning states
- Window size, placement, visibility level, and cross-Space behavior

## Implementation

Keep the change local to `FloatingChipView.idleChip` in `Sources/Views/FloatingChipWindow.swift`.

Use separate resting colors rather than changing the shared floating-chip colors, because those shared colors are used by active and warning states that are outside this task.

## Verification

- Build the macOS app successfully.
- Confirm the resting chip is 40 x 8 points.
- Confirm the resting chip is visible over both a predominantly light window and a predominantly dark window.
- Hover the chip and confirm it still expands to 64 x 24 points with the Vordi logo and side controls.
- Exercise recording and processing once to confirm those visuals are unchanged.
