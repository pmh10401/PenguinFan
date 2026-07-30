# PenguinFan Menu Version Label Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display the running app version above the menu bar popover footer.

**Architecture:** `ProductBrand` reads and formats bundle metadata. `MenuBarView` renders the resulting string without knowing release numbers.

**Tech Stack:** SwiftUI, Foundation Bundle, XCTest

## Tasks

- [ ] Add tested bundle-version formatting to `ProductBrand`.
- [ ] Add the centered secondary version label above footer controls.
- [ ] Bump package defaults and README to version 1.0.12.
- [ ] Build the installer and publish the focused update to GitHub.
