<table>
  <tr>
    <td align="left">
      <img src="assets/spiced-rum-icon.png" alt="Spiced-Rum logo" width="96">
    </td>
    <td align="right">
      <a href="https://ko-fi.com/laughinginpurgatory"><img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Support me on Ko-fi"></a><br>
      <strong>Please support me on Kofi, every bit helps!</strong>
    </td>
  </tr>
</table>

# Spiced-Rum

Spiced-Rum is a macOS app for organizing Windows games and apps into separate Wine environments. It is made for Apple Silicon Macs and brings engine downloads, setup, graphics choices and shortcuts together in one place.

The app is highly experimental and began as a personal project. I released it in case it is useful to other people, but game and engine compatibility varies. A successful setup only proves that Wine can start a Windows environment; it does not promise that a particular game will install, render or run well.

[Download the latest Apple Silicon release](https://github.com/LaughingInPurgatory/Spiced-Rum/releases/latest)

## Before you begin

- An Apple Silicon Mac running macOS 14 or later. Some engines need a newer macOS version.
- Rosetta 2, which translates the Intel parts of Wine for Apple Silicon. Spiced-Rum can guide you through installing it.
- Enough free storage for the engine and each game's shotglass. Large games can take up a lot of space.
- An internet connection for engine downloads and Windows installers.

Spiced-Rum does not include Windows, game files, Steam, or Heroic. You provide any Windows installers and sign into your own accounts.

## Get started

### 1. Install a Wine engine

Open **Runtimes & setup** in the left sidebar and choose **Download engine…**. Pick a publisher from the menu, then select a release. The app downloads the engine, prepares the pieces it needs and checks that it can create a Windows x64 environment before adding it to your library.

For a first try, Wine Staging is a useful general-purpose choice. **Barrel Wine** is a CrossOver-based Apple Silicon build; Spiced-Rum also prepares its support libraries and the latest available DXMT runtime. Engines are separate downloads and can be kept side by side.

Some publishers do not provide a checksum for every release. Spiced-Rum will tell you before downloading an unverified release. Only continue if you trust that publisher and version.

### 2. Make a shotglass

Choose **Your shotglasses** in the sidebar, then **New shotglass**. Give it a name, select an installed engine, choose a graphics option and pick a folder for the shotglass. You can use an external drive if it is mounted and writable; APFS is recommended.

A shotglass is a separate Windows environment for a game or app. Its folder contains its Windows settings, installed programs, shortcuts and logs. Keeping games in separate shotglasses makes it easier to try another engine or graphics option without changing your other games.

### 3. Install a game or app

Select a shotglass in the sidebar. Choose **Run installer or executable…** and open a Windows `.exe` or `.msi` installer. When installation finishes, choose **Add application…** and select the installed program's `.exe`. A shortcut appears in the shotglass; use **Launch** to open it later.

For Steam or Heroic, install the Windows version in a shotglass just like another app, then add its executable as a shortcut. Spiced-Rum has a direct extraction option for Heroic's Windows setup file because its installer can incorrectly report that Heroic is already running.

## Finding your way around

### Your shotglasses

When Spiced-Rum opens, a short animation shows rum pouring into a shotglass. Choose **Skip intro** to go straight to the app. The animation is skipped automatically when macOS Reduce Motion is enabled.

The **Shotglasses** section in the sidebar lists your game and app environments. Select a shotglass to see its engine, graphics setting, shortcuts and controls in the main area. The plus, refresh and import buttons above the list manage your library; hover over each button to see its label.

- A **green light** means the shotglass finished its initial setup. An **amber light** means it still needs setup or a retry.
- The small trash button beside a shotglass moves it to macOS Trash. Rename and duplicate actions are available from the shotglass row's context menu.
- **Launch** opens a saved Windows shortcut. **Run installer or executable…** opens another Windows program once.
- **Add application…** saves an installed `.exe` as a shortcut.
- **Duplicate…** copies its Windows environment, installed games and apps, settings, and shortcuts, but leaves backups behind. Allow roughly the same free space as the original.
- **Install components…** adds Windows fonts, DLLs and settings commonly requested by games.
- **Graphics** changes the renderer for that shotglass when its engine supports another option.
- **Change engine…** switches the shotglass to another installed engine and keeps a Wine-environment backup so you can recover.
- **Show files** opens the shotglass folder. **Logs** opens its Wine output to help diagnose setup or launch problems.
- **Force Stop** stops all Wine processes in that shotglass. Unsaved progress may be lost; other shotglasses are unaffected.
- The trash button moves the complete shotglass folder to macOS Trash, including installed games and backups. The shared engine remains installed.

### Runtimes & setup

This screen is for shared engines and Mac-wide tools. It shows whether Rosetta is available, where new shotglasses will be stored, and the setup status for video playback and Windows dependency tools. Use **Download engine…** to install more engines. Use the engine's **Remove…** action when no shotglass or backup needs it.

The graphics sections manage engine-level packages:

- **DXVK** translates Direct3D 10/11 through Vulkan and MoltenVK. Spiced-Rum lists macOS-compatible builds and keeps versions side by side.
- **DXMT** translates Direct3D 10/11 to Metal. It is currently offered with Barrel Wine. Use **Manage versions…** to install or select another official DXMT build.
- **D3DMetal** is Apple's graphics runtime from Game Porting Toolkit (GPTK). It only appears with an engine that already supports it. Spiced-Rum can prepare a GPTK runtime from an Apple evaluation image you downloaded; Apple's terms apply.

These renderer choices are not interchangeable for every game. If one shows a blank screen, crashes or performs poorly, try another supported renderer or engine. Your game files remain in the shotglass while you test.

## Manage an engine or graphics version

To change a shotglass's Wine engine, open it and choose **Change engine…**. Choose an installed version or download another one. Before switching, close the shotglass's Windows apps and save your game. Spiced-Rum stops remaining Wine processes and saves the Windows environment before applying the new engine.

The backup contains the Wine environment—Windows system files, registry and drive mappings—not installed games, apps or personal files. After you have checked the new engine, use **Delete backup** to reclaim its space. If a change fails, use **Restore** to return to the saved environment.

To change a graphics package, open **Runtimes & setup** and choose **Manage versions…** in the DXVK or DXMT section for that engine. Installations stay side by side. Selecting a different DXMT version updates the shotglasses using DXMT and restores Wine's original `winemetal.dll` when a shotglass switches away from DXMT.

## Components and video

If a game asks for a missing Windows component, open its shotglass and choose **Install components…**. Search the list for the name the game reported. Common examples include Visual C++ runtime files, D3DCompiler 47, DirectX 9 helper libraries and fonts. Components are installed only in the selected shotglass. Some installers ask you to accept a license or make a choice.

Managed Wine engines prepare video playback support automatically when available. If an older engine has broken or missing video playback, choose **Set up video playback** in **Runtimes & setup**, then close and reopen its Windows apps.

Some dependency tools need Homebrew, the macOS package manager. Spiced-Rum can start Homebrew's official installer; macOS Installer handles any administrator approval. Return to Spiced-Rum afterward to continue.

## A couple of useful fixes

**Steam's login window is black:** open the Steam shortcut's menu and choose **Fix Steam's black login window…**. This runs Steam's browser interface with GPU rendering disabled and in one process. Steam client updates are paused while the fix is enabled; games keep using the shotglass's graphics setting. Use the same menu to restore Steam's original helper and setting.

**Heroic opens to a blank or broken window:** use **Repair Heroic blank window…** in the Heroic shortcut menu. Spiced-Rum stops the shotglass's Windows processes, clears Heroic's regenerable graphics cache and starts its interface with a software renderer. This affects Heroic's interface, not games launched from it. Save work in other apps in the same shotglass first.

**A game fails to start:** try another engine or supported graphics option, install only the Windows components the game requests, and check **Logs**. A game can fail even when the engine setup check passed. Shotglasses keep files separate, but they are not security sandboxes; only run Windows programs you trust.

## Installing the downloaded app

Download the latest `.zip` from [Releases](https://github.com/LaughingInPurgatory/Spiced-Rum/releases/latest), expand it and move **Spiced-Rum.app** to Applications. Releases use the maintainer's self-signed code-signing certificate; they are not signed with an Apple Developer ID or notarized. The signature helps macOS identify the same signing key and detect changes, but another Mac does not automatically trust that certificate. When you first open a downloaded copy, macOS may ask you to approve it in **System Settings → Privacy & Security**. See [Apple's instructions](https://support.apple.com/en-gb/guide/mac-help/mh40617/27/mac/27).

## Engines included

Available releases change over time. Spiced-Rum lists publisher versions inside the app and installs them side by side.

- **Barrel Wine** is based on CrossOver Wine sources for Apple Silicon. Spiced-Rum prepares its support libraries and DXMT graphics runtime. [Barrel project](https://github.com/MrTuNNe/Barrel)
- **Apple Game Porting Toolkit** includes Apple's Wine host and D3DMetal runtime. GPTK 4 requires macOS 15 or later. [Apple GPTK](https://developer.apple.com/games/game-porting-toolkit/)
- **Wine Staging, Stable and Devel** are macOS WineHQ builds. [Gcenx's macOS builds](https://github.com/Gcenx/macOS_Wine_builds)
- **Whisky community Wine Libraries** are community Wine releases; GPTK-capable builds need a matching Apple payload. [Releases](https://github.com/frankea/Whisky/releases)
- **Sikarugir / Kegworks** builds can prepare support libraries automatically when the release works without Sikarugir's own launcher. [Sikarugir engines](https://github.com/Sikarugir-App/Engines/releases)
- You can also import a complete macOS-compatible Wine engine using **Advanced import…**. Linux builds of Wine, Proton or DXVK do not run on macOS just because Rosetta is installed.

## Help and project notes

If something goes wrong, the shotglass's **Logs** button opens the Wine log. Please include the engine name, macOS version, game or app, selected graphics option and the relevant log when reporting a problem. Remove account names, access tokens and other private information before sharing a log publicly.

Spiced-Rum is a personal, highly experimental project developed by **Laughing In Purgatory**. It is not affiliated with Apple, CodeWeavers, Valve, Heroic Games Launcher or the engine publishers. Windows compatibility varies by game, engine version and Mac.

## For people building Spiced-Rum

Spiced-Rum is a native SwiftUI macOS app with no package dependencies. Open `Package.swift` in Xcode, or build and test on an Apple Silicon Mac with Xcode or the Swift command-line tools:

```sh
bash scripts/test.sh
bash scripts/build-app.sh
open dist/Spiced-Rum.app
```

The build is ad-hoc signed by default. If you have a code-signing identity in your login keychain, set `SPICED_RUM_SIGNING_IDENTITY` to its name to use it instead. The app supports macOS 14 and later. The test suite covers library behavior and setup logic. Real Wine, game rendering and publisher-download checks are optional integration tests and require the relevant runtimes or downloads.
