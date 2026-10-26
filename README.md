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

Spiced-Rum keeps Windows games and apps in separate Wine setups on Apple Silicon Macs. I started it as a personal project and released it in case it helps someone else.

It is still highly experimental. Some games will not install, some will look or sound wrong, and some will not run at all. When Spiced-Rum says an engine is ready, it means only that it started a basic Windows environment; it does not mean a particular game works.

[Download the latest release](https://github.com/LaughingInPurgatory/Spiced-Rum/releases/latest)

## What you need

- An Apple Silicon Mac running macOS 14 or later. Individual engines may need a newer macOS version; Apple GPTK 4 needs macOS 15 or later.
- An internet connection to download engines and Windows installers.
- Enough disk space for each game. You can put shotglasses on an external drive.

Spiced-Rum does not include Windows, Steam, Heroic or games. Installers and account sign-ins are yours to provide.

## A couple of terms

An **engine** is the macOS Wine software that runs Windows programs. You can keep several versions installed and try a different one when a game has trouble.

A **shotglass** is one game's or app's own Windows setup. Its files, settings and shortcuts are kept apart from your other shotglasses.

## Getting started

### Install an engine

Click the gear in the left side of the main window to open **Settings**. Choose **Download engine…**, pick a source and version, and let Spiced-Rum set it up. The first setup can take a while. Spiced-Rum checks that Wine can start a basic Windows environment when it finishes.

You can install more than one version. Keeping an older version around is useful when a game stops working after an engine update.

### Create a shotglass

Close Settings, or move its window wherever you like. In the main window, click **+** above the shotglass list. Name the shotglass, choose an engine and choose where to keep its files.

### Install a Windows app or game

Select the shotglass and choose **Run installer or executable…**. Open the game's `.exe` or `.msi` installer. When it has finished, choose **Add application…** and select the installed program's `.exe`; Spiced-Rum will add a shortcut to the shotglass.

You can install Windows Steam or Heroic the same way. If Steam's sign-in window is black, or Heroic opens blank or reports that it is already running, see [Fixing common problems](#fixing-common-problems).

## Using the main window

Your shotglasses are listed on the left. The buttons above the list add, import or refresh shotglasses. A green status light means a shotglass is ready; amber means setup is still needed. Use the trash button beside a shotglass to move it to macOS Trash.

Select a shotglass to see its engine, graphics settings and saved shortcuts. From there you can launch an app, run another installer, install Windows components, change engines, view files and logs, or force-stop that shotglass's Wine processes. Force Stop can lose unsaved game progress, but it does not stop other shotglasses.

Use the gear button to open Settings in its own macOS window. You can drag it by its title bar and close it with the standard macOS close button. Settings is where you manage engines, graphics downloads, dependency tools, video support and the default location for new shotglasses.

## Engines and graphics

Spiced-Rum gets macOS builds from a few projects. It can install Apple's Game Porting Toolkit when you have the matching Apple Wine host and evaluation image, check Gcenx's Homebrew package when it matches that image, and download Barrel Wine, Wine Staging/Stable/Devel, Whisky community Wine and selected Sikarugir releases. Advanced users can register a complete macOS Wine engine. Linux builds of Wine, Proton and DXVK are not macOS engines.

Graphics choices depend on the engine. A shotglass can use Wine's built-in Direct3D 12 support, MoltenVK for Vulkan when the engine includes it, or other supported options such as D3DMetal, DXMT, DXVK, mtld3d and Zink. The Graphics panel only offers combinations the selected engine can use.

DXVK versions are downloaded and removed in Settings, then selected separately for each shotglass. Installing or changing a DXVK version does not change your other shotglasses. DXVK-Sarek is experimental on macOS.

## Changing an engine

Close the shotglass's Windows apps and save your game before changing its engine. Spiced-Rum backs up the **Wine environment** so you can restore it if the change causes trouble. The backup does not contain installed games, apps or personal files. Once you have checked that the new engine works, delete the backup to free its space.

Duplicating a shotglass copies its Windows environment, installed apps and games, settings and shortcuts. It does not copy engine-change backups, and it can take about as much space as the original.

## Fixing common problems

- **Steam's sign-in window is black:** open the Steam shortcut's menu and choose **Fix Steam's black login window…**. This changes how Steam draws its sign-in page. You can undo it from the same menu. Steam client updates are paused while the fix is enabled.
- **Heroic opens blank:** choose **Repair Heroic blank window…** from its shortcut menu. This clears Heroic's temporary graphics cache and changes how its window is drawn. It is available for the installed and portable Windows versions. It does not change the graphics settings of games launched through Heroic.
- **Heroic's installer says Heroic is already running:** use the option to extract the installer files directly, then add Heroic's executable to the shotglass.
- **A game asks for a Windows component:** open the shotglass and choose **Install components…**. Search for the component's name. It is installed in that shotglass only; some component installers need you to make a choice.
- **Video does not play:** open Settings and choose **Set up video playback**, then close and reopen the Windows app.
- **A game still will not start:** try another engine or graphics option, then check that shotglass's **Logs**. Passing the basic setup check does not guarantee that a specific game is compatible.

Some helper tools need Homebrew, a macOS package manager. Spiced-Rum can guide you through installing it; macOS may ask you to approve the installer.

Shotglasses keep their files separate, but they are not security sandboxes. Only run Windows programs you trust.

## Installing Spiced-Rum

Download the latest `.zip` from [Releases](https://github.com/LaughingInPurgatory/Spiced-Rum/releases/latest), expand it and move **Spiced-Rum.app** to Applications.

The app is signed with my self-signed certificate, not an Apple Developer ID, and it is not notarized. macOS may ask you to approve it the first time you open it. Other Macs will not automatically trust this certificate. [Apple's instructions](https://support.apple.com/en-gb/guide/mac-help/mh40617/27/mac/27) explain how to open an app that macOS cannot verify.

## Reporting a problem

Please include the engine, macOS version, game or app, graphics choice and relevant shotglass log. Remove account names, access tokens and other private details before posting a log publicly.

Spiced-Rum is developed by **Laughing In Purgatory**. It is not affiliated with Apple, CodeWeavers, Valve, Heroic Games Launcher or the engine publishers.

## Building from source

Spiced-Rum is a SwiftUI macOS app. On an Apple Silicon Mac with Xcode or the Swift command-line tools installed:

```sh
bash scripts/test.sh
bash scripts/build-app.sh
open dist/Spiced-Rum.app
```

The build is ad-hoc signed by default. To sign with an identity in your login keychain, set `SPICED_RUM_SIGNING_IDENTITY` to its name. The app supports macOS 14 and later; game compatibility depends on the game, engine and Mac.
