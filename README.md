# Glint

Glint is a macOS menu-bar app for snapping windows. Drag a window to a screen edge or click a zone in the menu-bar picker. Use Glint Settings to manage custom layouts, adjust window gaps, and choose whether Glint starts at login.

## Build and run

Use macOS 13 or later with the Xcode Command Line Tools. Sign in to GitHub with an account that has access to this repository, then run the following commands.

```sh
git clone https://github.com/mohan-codebase/glint.git
cd glint
make
open build/Glint.app
```

In Glint Settings, click **Allow Access…** and enable Glint under **System Settings → Privacy & Security → Accessibility**. macOS can ask you to approve a new local build after its signature changes.

## Test

```sh
make test
```

The test suite covers snap geometry, window gaps, and saved layouts. Use the running app to check dragging, the menu-bar picker, and login behavior.
