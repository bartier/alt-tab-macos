/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {
  /** AltTab Shortcut - Which AltTab shortcut's window list to show (its filters and ordering apply). Enable 'Raycast integration' for it in AltTab Preferences > Controls. */
  "shortcutIndex": "1" | "2" | "3" | "4",
  /** AltTab.app Path - Path to the AltTab app bundle */
  "altTabPath": string
}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `search-windows` command */
  export type SearchWindows = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `search-windows` command */
  export type SearchWindows = {}
}

