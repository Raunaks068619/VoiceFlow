# Magic Words Dark Mode and Sidebar Hit Targets

## Goal

Make the Magic Words hero readable in both app themes and make every visible
sidebar row behave as one complete navigation control.

## Magic Words hero

- Treat the blue mesh hero as an always-dark surface.
- Do not use adaptive page text tokens inside the hero.
- Render the trigger chip with a light fill and dark text.
- Render the expansion chip with a dark translucent fill, a restrained light
  border, and light text.
- Use high-contrast light text for supporting copy, arrows, dividers, quotes,
  and installed-app labels.
- Preserve the existing layout, typography, imagery, and copy.

## Sidebar interaction

- Every primary sidebar button fills the available navigation width.
- The complete row is a rectangular hit target, including icon, label,
  padding, selected background, and trailing empty space.
- Apply the same behavior to the Settings sidebar.
- Preserve existing selection, hover, pointer, and navigation behavior.

## Validation

- Inspect the Magic Words hero in dark and light modes.
- Confirm the two example chips maintain clear foreground/background contrast.
- Click the icon, label, selected background, and far-right empty area of
  primary sidebar rows.
- Repeat the hit-target checks in the Settings sidebar.
- Build and install the Release app, then run the bundle verifier.
