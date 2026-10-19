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

Spiced-Rum helps you run Windows x64 games and apps on Apple Silicon Macs. It combines a macOS Wine engine, Rosetta 2 for Intel code, and a graphics layer such as DXVK or Apple's Game Porting Toolkit.

Each Windows environment is called a **shotglass**. Keep different games or apps in separate shotglasses, and choose where each one is stored.

Spiced-Rum is a highly experimental personal project that I released in case it may be useful to others. It is still in active development and has not been tested across a wide range of Macs, engines, or games. A successful environment check only confirms that Wine starts; it does not guarantee that a particular app or game will work or display correctly.

**Download:** [Latest macOS arm64 release](https://github.com/LaughingInPurgatory/Spiced-Rum/releases/latest)

## Build and run

You need an Apple Silicon Mac running macOS 14 or later, plus Xcode or the Swift command-line tools. Some engines require a newer macOS version.

```sh
bash scripts/test.sh
bash scripts/build-app.sh
open dist/Spiced-Rum.app
```

The build creates an arm64 app and signs it locally for development. It is not configured for distribution signing or notarization. To work on the source, open Package.swift in Xcode. The project has no package dependencies.

## Open the app

The downloadable app is ad-hoc signed. It is not signed with an Apple Developer ID or notarized, so macOS may block it the first time you open it. If you trust the download, try opening Spiced-Rum, then go to **System Settings → Privacy & Security** and choose **Open Anyway**. See [Apple's instructions](https://support.apple.com/en-gb/guide/mac-help/mh40617/27/mac/27).

## Create a shotglass

1. Open **Runtimes & setup**. If Rosetta is needed, choose **Set up Rosetta** and follow Apple's prompts.
2. Choose an engine. You can download Wine Staging in the app, or use Apple's links to download GPTK and its evaluation image. Apple may require a developer sign-in.
3. Spiced-Rum prepares the engine and checks that it can create a temporary Windows x64 environment. This confirms that Wine starts; it does not confirm that games will work.
4. Wine Staging downloads are checked against the publisher's SHA-256 checksum when available. Spiced-Rum sets up MoltenVK, macOS DXVK, and video support.
5. Create a shotglass, choose an engine, and select where to store it. External drives work when mounted and writable. APFS is recommended because Wine needs file permissions and symbolic links.
6. Run a Windows installer in the shotglass. Then choose **Add application** to save the installed program as a shortcut. This is also how you add Windows Steam or Heroic.

GPTK setup uses the newest Apple Wine host and evaluation image available on your Mac. Spiced-Rum mounts the image read-only and builds a separate runtime, leaving Apple's original app unchanged.

If you download the image after opening Spiced-Rum, return to the app so it can check again. Newer GPTK payloads install alongside older ones. GPTK 4 requires macOS 15 or later and Apple's license applies.

Shotglass cards show a status light near the top. Green means setup has completed; amber means the shotglass still needs initialization.

To remove a shotglass, select the trash icon on its card or beside its name in the collection sidebar, then confirm. Spiced-Rum stops its Windows processes and moves the whole folder—including its Windows environment, installed apps, games, settings, and backups—to macOS Trash. The shared Wine engine stays installed.

If a program reports a missing Windows component, open its shotglass and choose **Install components**. The list refreshes from the installed Winetricks version and can include applications, benchmarks, DLLs, fonts, and Windows settings. Search by name or verb. Common entries include:

- Visual C++ 2015–2022
- D3DCompiler 47
- DirectX 9 helper libraries
- Core fonts
- .NET Framework 4.8

Spiced-Rum sets up Winetricks and its extraction tools through Homebrew when needed. Windows installers may still ask for setup or license approval. Components are installed only in the selected shotglass. Some entries run installers or change Windows settings; choose the verb the program asks for.

Heroic's Windows installer has a special path. Spiced-Rum extracts the app files into C:\Program Files\Heroic and adds a shortcut without running the installer's unreliable “Heroic is running” check.

This skips Windows Start menu and uninstaller registration. To remove this extracted copy, delete C:\Program Files\Heroic inside the shotglass.

If Homebrew is missing, choose **Set up Homebrew**. Spiced-Rum downloads the official package, verifies its checksum, and opens macOS Installer.

Follow the prompts, including any administrator approval. Your credentials go to macOS Installer, not Spiced-Rum. When you return to the app, it resumes setting up Winetricks and its extraction tools. See Homebrew's [installation requirements](https://docs.brew.sh/Installation).

## Steam's black login window

Some Wine 11 builds show Steam's login window as a black rectangle. To try the workaround, open the Steam shortcut's program menu and enable it.

The workaround saves Steam's web helper, then runs it with Chromium GPU rendering disabled and the interface in a single process. It also sets BootStrapperInhibitAll=enable in Steam's steam.cfg to pause client updates while enabled. Your games continue to use the shotglass's selected graphics engine.

Choose the workaround again to turn it off and restore Steam's previous files and setting.

If Steam replaced its helper in the meantime, Spiced-Rum keeps the replacement beside the restored original. This optional fix has not been tested with every Steam version or Wine engine.

The bundled Windows helper is based on notpop's MIT-licensed steamwebhelper-wrapper.c from [steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine).

The original source and license are included under Sources/SpicedRum/Resources/ThirdParty and copied into the app.

To rebuild the x64 helper, install mingw-w64 with Homebrew and run:

    bash scripts/build-steam-helper.sh

## Advanced engine setup

You can import a complete macOS Wine engine or a prepared launcher script. In the file picker, choose the engine's wine or wine64 program. Press ⌘⇧G to navigate inside an application bundle.

Launcher scripts must pass through their arguments and preserve WINEPREFIX.

Only mark an imported engine as D3DMetal- or DXMT-capable if it already includes the matching Wine integration. Imported engines need their dependencies prepared first; a source archive alone is not a usable engine.

Sikarugir downloads include the publisher's checksum-pinned Template 1.0.24 support package. Spiced-Rum connects its native libraries, including libinotify and GStreamer, with portable links and per-engine Wine launch scripts.

Existing engine files are preserved. The support template and checksum record stay with the engine.

Sikarugir Wine 11 currently requires the publisher's launcher, so it cannot be installed directly. The release browser explains this. Compatible builds use Wine's default graphics; optional wrapper renderers and launcher services are not enabled automatically.

Every shotglass lives in its own UUID-named `.spicedrum` directory:

```text
<uuid>.spicedrum/
  shotglass.json     # Runtime snapshot, renderer, shortcuts and setup status
  prefix/         # Wine's Windows environment, including drive_c
  session.log     # Wine command output
```

The library catalog is stored at ~/Library/Application Support/Spiced-Rum/library.json. You can change the default location for new shotglasses without moving the ones you already have.

To move a shotglass, move its folder in Finder, then import it from its new location. Shortcuts inside the folder continue to work.

Any external apps or engines must still be available at their saved paths.

If a drive is missing or the catalog cannot be read, Spiced-Rum reports the problem without replacing the catalog. Failed setup leaves the folder and log available for inspection and retry.

## Engine choices

Engine versions and availability change over time. The release browser sorts releases by upload date, refreshes recent versions, and offers **Load older releases**. Engines install side by side.

Spiced-Rum verifies a publisher checksum when one is available. Some older releases do not have one; for those, the app asks before downloading and uses the publisher's HTTPS link.

For an older release without a publisher checksum, Spiced-Rum records a local checksum and checks that Wine can create a Windows x64 environment. The local checksum records the file but does not authenticate it with the publisher. Imported engines receive a version check only.

Publisher details last checked on **18 October 2026**. These notes describe engine support in Spiced-Rum, not guaranteed game compatibility.

- **Sikarugir / Kegworks:** successor to Wineskin/Kegworks. Some older releases are unsupported. Compatible standalone releases prepare support libraries automatically; Wine 11 still requires the publisher's launcher. [Project](https://github.com/Sikarugir-App/Sikarugir) · [engine releases](https://github.com/Sikarugir-App/Engines/releases)
- **Apple GPTK:** prepares a separate runtime with matching D3DMetal files from Apple's evaluation image. GPTK 4 requires macOS 15 or later and Apple's license applies. [Apple Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/)
- **Wine Staging:** Gcenx's macOS WineHQ build, with Staging patches, dependencies, and MoltenVK. [Wine builds](https://github.com/Gcenx/macOS_Wine_builds)
- **Wine Stable and Devel:** alternative macOS WineHQ releases for compatibility comparisons. [Wine builds](https://github.com/Gcenx/macOS_Wine_builds)
- **Whisky community Wine Libraries:** versioned community releases. Spiced-Rum checks downloads and x64 startup; GPTK-capable versions can receive Apple's matching graphics payload. The Wine 11.16 preview notes report Steam login stalls. [Releases](https://github.com/frankea/Whisky/releases)
- **Custom macOS Wine:** import a complete macOS-compatible engine or prepared launcher. Linux ELF binaries are rejected.

Valve Proton and GE-Proton are built for Linux. Rosetta does not make their Linux binaries run on macOS. Some of their open-source patches could be adapted for macOS Wine, but that requires engine development.

## Graphics

- **Runtime default:** Let the selected engine manage its graphics settings. This does not select a specific renderer.
- **DXVK through MoltenVK:** DXVK translates Direct3D 10/11 to Vulkan, and MoltenVK translates Vulkan to Metal.
  - Managed WineHQ engines receive a macOS-compatible DXVK package automatically.
  - Imported engines need their own macOS-compatible DXVK package and MoltenVK. Linux DXVK packages do not work here.
  - In **Runtimes & setup**, choose **DXVK versions** to install an older or newer package from [Gcenx DXVK-macOS](https://github.com/Gcenx/DXVK-macOS/releases). Spiced-Rum keeps versions side by side and updates shotglasses using DXVK with that engine. It keeps Wine's original DLLs so you can switch graphics later. The package can include optional x32 DLLs.
  - Shotglass graphics can be changed after setup. D3DMetal appears only when the selected engine already includes Apple's matching GPTK payload. Its version changes with the engine.
- **D3DMetal:** Apple's Direct3D-to-Metal implementation. It is available only in engines that already include it. GPTK-capable Whisky releases receive matching files from Apple's evaluation image; general Wine builds do not.
- **DXMT:** A separate Direct3D 10/11-to-Metal implementation. This preview supports runtimes that already include DXMT's built-in Wine DLLs.
  Native-DLL DXMT packages need a prepared launcher and should use Runtime default. See [DXMT](https://github.com/3Shain/dxmt) and its [installation guide](https://github.com/3Shain/dxmt/wiki/DXMT-Installation-Guide-for-Geeks).

## Change a shotglass's engine and manage backups

To switch engines, open a shotglass and choose **Change engine**. Pick any installed older or newer version. To download another version, choose **Download older or newer engines**; this keeps your current engines.

Before the update, Spiced-Rum checks the selected engine, stops the shotglass's Wine processes, and backs up the Wine environment. It then updates the environment and selects the new engine's prepared graphics defaults, replacing or removing Spiced-Rum's DXVK files if needed. Your installed apps and games stay in place.

To remove an engine, choose **Remove…** in **Runtimes & setup**. Spiced-Rum only allows removal when no shotglass or recovery backup still needs it.

Downloaded engines are deleted from the managed Engines folder. Custom engines are unregistered, but their files are left in place.

A backup contains **only the Wine environment** and the previous engine and graphics settings. It includes:

- drive_c/windows
- system.reg, user.reg, and userdef.reg
- dosdevices, .update-timestamp, and winetricks.log

Backups do not include installed apps or games, Program Files, Program Files (x86), ProgramData, user profiles, saves, or other app and game folders.

Files inside the Windows system directory are included. Backups are stored in the shotglass's engine-backups folder.

If an engine update fails, Spiced-Rum restores the previous environment automatically. You can also choose **Restore** in Change engine to return to a saved environment.

Restore keeps installed apps, games, and current shortcuts. Because it restores the registry too, apps installed after the backup may need repair. Before a manual restore, Spiced-Rum saves the current environment so you can undo the restore.

If an engine change is interrupted, the shotglass stays unavailable until you restore its saved environment.

After you have checked that the new engine works, choose **Delete backup** to remove the snapshot. It does not remove installed apps, the current Wine environment, or any engine. A backup needed to recover an interrupted change cannot be deleted.

## Video playback and H.264

Managed Wine engines prepare video support before first use. Wine Staging, Stable, and Devel receive the checksum-pinned [GStreamer 1.28.8 universal runtime](https://gstreamer.freedesktop.org/data/pkg/osx/1.28.8/), which includes libav's H.264 decoder.

Spiced-Rum extracts GStreamer into the engine's media folder without running installer scripts or writing to /Library. It keeps the original notices and resources. Setup checks H.264 encoding and decoding under Rosetta before publishing the runtime. Sikarugir uses its bundled framework when available.

Wine launches use explicit paths for GStreamer's libraries, plugins, and scanner. Wine's own libraries are kept later in the search path so they do not replace macOS libraries GStreamer needs.

Each shotglass gets its own x64 plugin registry to avoid stale plugin caches. To set up an existing engine, choose **Runtimes & setup → Set up video playback**. Close Windows apps and launchers during setup, then reopen them. Imported engines keep their publisher-specific media setup.

An opt-in check verifies the official package, assembles the framework, decodes a generated H.264 stream under Rosetta, and creates Wine's Windows H.264 decoder from an x64 program in a disposable shotglass:

```sh
SPICED_RUM_TEST_GSTREAMER_PACKAGE=/path/to/gstreamer-1.0-1.28.8-universal.pkg SPICED_RUM_TEST_WINE=/path/to/wine bash scripts/test.sh --filter ShotglassTests/testOptionalH264DecodeAndWineStaging
```

For a previously installed runtime, replace `SPICED_RUM_TEST_GSTREAMER_PACKAGE` with `SPICED_RUM_TEST_GSTREAMER_FRAMEWORK=/path/to/GStreamer.framework`. The test copies the framework into its disposable fixture.

## Verification

Core tests cover folder selection, shortcuts, path safety, launch arguments, renderer settings, Linux binary rejection, DXVK installation, logs, and prefix setup failures.

### Optional integration tests

An opt-in integration check creates a real x64 Wine prefix and runs Windows `cmd.exe` through Rosetta:

```sh
SPICED_RUM_TEST_WINE=/absolute/path/to/wine bash scripts/test.sh
```

Add `SPICED_RUM_TEST_COMPONENTS=1` to this command to also install D3DCompiler 47 into the disposable shotglass through Winetricks and verify its native x64 DLL checksum. This path has been verified with Wine Staging 11.18 and Winetricks 20260125.

Test the full official download, checksum verification, automatic graphics setup, engine relocation and Windows x64 startup path with:

```sh
SPICED_RUM_TEST_DOWNLOADS=1 bash scripts/test.sh
```

Test a selected Whisky community runtime release through download, checksum verification, graphics setup, engine relocation and Windows x64 startup with:

```sh
SPICED_RUM_TEST_WHISKY=v4.6.4-beta.1 bash scripts/test.sh --filter ShotglassTests/testOptionalWhiskyCommunityRuntimeDownloadAndSetup
```

The Whisky integration test also needs Apple's GPTK evaluation image available in `~/Downloads` or an imported managed GPTK runtime in Spiced-Rum's Engines folder.

To test switching between two engines, set both variables to different Wine executable paths:

    SPICED_RUM_TEST_WINE=/path/to/wine-one SPICED_RUM_TEST_OTHER_WINE=/path/to/wine-two bash scripts/test.sh

The test checks switching, running a Windows command, restoring an environment, preserving app files, and deleting a backup. It passed with Wine Staging 11.18 and 11.17 on 18 October 2026. Unit tests also cover failed updates, automatic recovery, protected backups, graphics DLL replacement, and release history.

### Sikarugir integration test

This test downloads and sets up a Sikarugir engine, then checks that it can create a Windows x64 environment:

    SPICED_RUM_TEST_SIKARUGIR=WS11Wine10.0_3.tar.xz bash scripts/test.sh --filter ShotglassTests/testOptionalSikarugirDownloadAndSetup

The test passed on 18 October 2026 with the previously failing WS11Wine10.0_3 engine. It verified the support template, engine relocation, and Windows x64 setup.

## Current limits

The tests do not check DirectX rendering or guarantee that commercial games will work. Game-specific compatibility guides and Steam or Heroic account linking are not included.

Automatic setup works best with complete WineHQ macOS packages. Source-only and Apple-licensed engines may need extra setup. Spiced-Rum prepares Sikarugir's support libraries, but does not automatically enable its optional wrapper renderers or launcher services.

A launch status describes the Wine command Spiced-Rum started. A launcher can start child processes that keep running after that command exits. Closing Spiced-Rum does not stop games or Wine servers. Shotglasses keep apps and files separate, but they are not security sandboxes.
