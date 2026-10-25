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

Spiced-Rum helps you try Windows games and apps on an Apple Silicon Mac. It keeps each game or app in its own **shotglass**, so you can change its settings without changing the others.

This is a highly experimental personal project. I released it in case it is useful to other people, but many Windows games and apps will not work properly. A successful setup only means Spiced-Rum could start a basic Windows environment; it does not mean a game will install, look right or run well.

[Download Spiced-Rum](https://github.com/LaughingInPurgatory/Spiced-Rum/releases/latest)

## Before you start

- An Apple Silicon Mac, such as an M1, M2, M3 or M4 Mac.
- macOS 14 or later. Some engines need a newer version of macOS; Apple's GPTK 4 needs macOS 15 or later.
- An internet connection to download engines and Windows installers.
- Enough free storage for your games. Large games can take up a lot of space.

Spiced-Rum does not include Windows, Steam, Heroic or any games. You provide the Windows installers and sign in to your own accounts.

## A few words in plain English

- **Engine:** the compatibility software that helps a Windows app run on your Mac. You can install more than one engine and try different versions.
- **Shotglass:** a separate Windows setup for one game or app. It keeps that app's files and settings together.
- **Graphics option:** the way a game draws its picture. If one option gives you a blank screen or crashes, another may work better.

Spiced-Rum uses Wine-based engines. Wine is not a copy of Windows; it translates the parts of Windows that an app needs. Different games need different parts, so results vary.

## Get started

### 1. Install an engine

Open **Runtimes & setup** in the sidebar and choose **Download engine…**. Select a source and a version. Spiced-Rum downloads the engine, sets up the parts it needs and checks that it can start a basic Windows environment.

You can keep several engines installed. That makes it easy to try an older or newer version if a game has problems.

### 2. Create a shotglass

Open **Shotglasses** in the sidebar and click the **+** button. Give the shotglass a name, choose an installed engine, then choose where to save it. You can use an external drive if it is connected and writable.

### 3. Install a Windows app or game

Select the shotglass, choose **Run installer or executable…**, and open the Windows `.exe` or `.msi` installer. After it installs, choose **Add application…** and select the program's `.exe` file. Spiced-Rum adds a shortcut you can use with **Launch**.

You can install the Windows versions of Steam or Heroic this way too. Heroic also has an option to extract its installer files directly if its installer incorrectly says Heroic is already running.

## How the app is laid out

### Shotglasses in the sidebar

The **Shotglasses** list is where you choose which game or app to manage. The buttons above the list add a shotglass, import one or refresh the list. Hover over a button to see what it does. A green light means the shotglass is ready; an amber light means it still needs setup. The trash button is beside each shotglass.

Select a shotglass to see its engine, graphics option and saved app shortcuts in the main area. From there you can:

- **Launch** a saved shortcut or run another Windows installer.
- **Add application…** to save a shortcut to an installed `.exe`.
- **Install components…** if a game asks for a Windows font or system component.
- **Change engine…** to try another installed engine.
- **Graphics** to choose another graphics option supported by that engine.
- **Show files** or **Logs** to find the shotglass folder or see what happened when something failed.
- **Force Stop** to stop Windows apps in that shotglass. Unsaved progress may be lost; other shotglasses are not affected.

Use the shotglass's sidebar menu to rename or duplicate it. The trash button moves the shotglass and its installed games to macOS Trash. Removing a shotglass does not remove its shared engine.

Duplicating a shotglass copies its Windows environment, installed games and apps, settings and shortcuts. It does not copy old engine-change backups, and the copy can need as much free space as the original.

### Runtimes & setup

Use **Runtimes & setup** to install and remove engines, check Rosetta, choose the default location for new shotglasses, and set up video or Windows dependency tools.

The DXVK section installs and removes macOS-compatible releases in a shared library, separate from your engines. Choose a DXVK version in a compatible shotglass's graphics options; that choice changes only that shotglass. Spiced-Rum will ask you to switch any shotglass or remove any saved backup that still uses a version before deleting it.

## Choosing an engine or graphics option

Spiced-Rum lists available releases inside the app. These are the main sources:

- **Apple Game Porting Toolkit (GPTK):** Apple's tools include a Wine host and D3DMetal graphics support. Spiced-Rum needs Apple's Wine host and the matching evaluation image to set it up. Apple may ask you to sign in, and Apple's terms apply. If Homebrew is installed, Spiced-Rum checks Gcenx's Homebrew package, but only offers it when it matches Apple's current GPTK release and your downloaded evaluation image. Homebrew may ask you to approve trusting this package first. Otherwise, use the matching Apple download. [Apple GPTK](https://developer.apple.com/games/game-porting-toolkit/) · [Gcenx Homebrew package](https://github.com/Gcenx/homebrew-wine)
- **Barrel Wine:** a Wine build based on CrossOver. Spiced-Rum prepares its support files and DXMT graphics option. [Barrel project](https://github.com/MrTuNNe/Barrel)
- **Wine Staging, Stable and Devel:** macOS Wine builds with different fixes and changes. [Gcenx's macOS builds](https://github.com/Gcenx/macOS_Wine_builds)
- **Whisky community Wine:** community-maintained Wine versions. Some need a matching Apple GPTK download. [Releases](https://github.com/frankea/Whisky/releases)
- **Sikarugir / Kegworks:** macOS Wine engines. Some releases need Sikarugir's own launcher and are not supported by Spiced-Rum. [Engine releases](https://github.com/Sikarugir-App/Engines/releases)
- **Custom engine:** advanced users can import a complete macOS Wine engine. Linux Wine, Proton and DXVK downloads cannot be used as macOS engines.

Graphics options you may see:

- **D3DMetal** is Apple's graphics support from GPTK.
- **DXMT** translates some DirectX games to Metal. It is currently offered with Barrel Wine.
- **DXVK** translates some DirectX games through Vulkan and MoltenVK. Spiced-Rum offers Gcenx's macOS builds and [DXVK-Sarek](https://github.com/pythonlover02/dxvk-sarek). Select its version separately for each shotglass. Sarek is experimental on macOS and may not work with every engine or game.

Not every engine supports every graphics option. If a game shows a blank screen, crashes or performs poorly, try another option or engine.

## Changing an engine safely

Before changing a shotglass's engine, close its Windows apps and save your game. Spiced-Rum saves a backup of the **Windows environment** so you can restore it if the switch causes a problem.

The backup does not include installed games, apps or personal files. After you have checked the new engine, choose **Delete backup** to free the space. Choose **Restore** if you need to go back.

## Fixing common problems

- **Steam's sign-in window is black:** open the Steam shortcut menu and choose **Fix Steam's black login window…**. This changes how Steam draws its sign-in page. You can use the same menu to undo the fix. Steam client updates are paused while it is enabled.
- **Heroic opens to a blank window:** choose **Repair Heroic blank window…** from the Heroic shortcut menu. Spiced-Rum clears Heroic's temporary graphics cache and changes how its window is drawn. This setting is for Heroic's window; it does not change the graphics setting used by games launched from Heroic.
- **A game asks for a missing Windows component:** open the shotglass and choose **Install components…**. Search for the component name shown by the game. Components are added only to that shotglass; some installers may ask you to make a choice.
- **A video does not play:** open **Runtimes & setup** and choose **Set up video playback**, then close and reopen the Windows app.
- **A game still will not start:** try another installed engine or supported graphics option, then check the shotglass's **Logs**. The setup check cannot guarantee that a specific game will work.

Some helper tools need Homebrew, a macOS package manager. Spiced-Rum can guide you through installing it; macOS may ask you to approve the installer.

Shotglasses keep their files separate, but they are not security sandboxes. Only run Windows programs you trust.

## Installing the downloaded app

Download the latest `.zip` from [Releases](https://github.com/LaughingInPurgatory/Spiced-Rum/releases/latest), expand it and move **Spiced-Rum.app** to Applications.

The app is signed with the maintainer's self-signed certificate. It is not signed with an Apple Developer ID or notarized, so macOS may ask you to approve it the first time you open it. The certificate does not make another Mac trust the app automatically. See [Apple's instructions](https://support.apple.com/en-gb/guide/mac-help/mh40617/27/mac/27).

## Help and project notes

If you report a problem, include the engine name, macOS version, game or app, graphics option and relevant shotglass log. Remove account names, access tokens and other private information before sharing a log publicly.

Spiced-Rum is developed by **Laughing In Purgatory**. It is not affiliated with Apple, CodeWeavers, Valve, Heroic Games Launcher or the engine publishers.

## Building Spiced-Rum

For developers: Spiced-Rum is a SwiftUI macOS app with no package dependencies. Open `Package.swift` in Xcode, or use the Swift command-line tools on an Apple Silicon Mac:

```sh
bash scripts/test.sh
bash scripts/build-app.sh
open dist/Spiced-Rum.app
```

The build is ad-hoc signed by default. To use a code-signing identity from your login keychain, set `SPICED_RUM_SIGNING_IDENTITY` to its name. The app supports macOS 14 and later. Real game compatibility still depends on the game, engine and Mac.
