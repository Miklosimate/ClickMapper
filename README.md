# ClickMapper

Native macOS Zwift Click V2 keyboard mapper. Requires macOS 14+ and Swift 6 tools. MyWhoosh on the same Mac is the first supported workflow.

## Build and run

```sh
./scripts/build-app.sh
open 'build/ClickMapper Diagnostic.app'
```

Quit the previous diagnostic before opening the rebuilt app. The bundle retains its original name and identifier to preserve Bluetooth permissions.

1. Allow Bluetooth, close other apps connected to the controllers, wake the pods, click Scan, and connect to **Zwift Click**. The scanner shows only names beginning with Zwift Click, in fixed discovery order. Rescanning retains rows so they do not jump. Short device IDs distinguish identically named devices. Use Switch to try the other device if only one pod responds, then Remember working device once both respond; this marks that device for future sessions. Switching disables keyboard output, so enable it again after checking the connection. Only one peripheral connection is supported; both physical pods have produced events through one connection in hardware testing.
2. Press each physical button and watch the diagrams light up. The drawings are schematic and their initial decoded names/positions are provisional. Click a diagram position, choose **Learn physical button**, then press that physical button to confirm its source. Learning swaps assignments to keep sources unique.
3. The default MyWhoosh preset maps **plus → I** and **minus → K**, with one tap per press. MyWhoosh documents I/K for MyShift: https://mywhoosh.com/myshift-mywhooshs-virtual-shifting-explained/. Confirm gear direction in your installed game; either mapping is editable.
4. Click **Enable output** and grant ClickMapper access in **System Settings → Privacy & Security → Accessibility**. Then enable output again. The app never enables output automatically at launch or after disconnect.
5. Open MyWhoosh on this Mac, enable MyShift, and start a ride. Keep MyWhoosh in front. Verify I/K with your physical keyboard first, then test the pod buttons.

## Custom mappings

Click any of the ten diagram buttons. Select a key and Command/Option/Control/Shift modifiers, or record a keyboard shortcut. Escape cancels recording; select Escape from the menu to assign it. Keys use macOS physical key codes, so character output depends on the active keyboard layout. Recorded keys outside the standard menu appear as a custom option.

- **Tap:** one key-down/up pair per controller press (default for shifting).
- **Hold:** key stays down until the controller button is released.
- **Repeat:** immediate tap, then taps every 150 ms after a 450 ms delay while held.

Mappings and learned positions are saved locally. Loading the MyWhoosh preset resets all keyboard bindings, leaving learned positions intact. Other eight buttons start unassigned. Keyboard output now works across all foreground apps by default; ClickMapper itself is excluded. There is no application restriction toggle.

Held keys and repeat timers are cleared on disconnect, output disable, mapping edits, and foreground-app changes. Sleep disables output. Bluetooth input and keyboard typing have been confirmed by the user. Automatic reconnect and real-game behavior still need hardware verification; automated tests use a fake event sink and do not send keys. This version supports keyboard shortcuts, not mouse actions, text macros, or profile switching.

## Hardware evidence and limitations

Firmware 1.0.1 produced all ten decoded button IDs beyond ten minutes, resumed after idle, and registered simultaneous three-second holds without a reported prior unlock. Reconnecting restored both pods after an intermittent one-pod response. Pod topology, reliable peripheral selection, sleep/wake behavior, and other firmware remain unverified. See `docs/protocol-observations.md`.

Protocol constants and candidate active-low button positions derive from the MIT-licensed community reference:
https://github.com/nrbz467bct-dot/zwift-click-keyboard-mapper/blob/main/zwift_click_mapper.py

The app recognizes seven-byte `23 08` state frames and uses the reference handshake and five-second keepalive. It does not authenticate/decrypt other packet formats, connect to a trainer, or update firmware. Unknown payloads are omitted from the bounded in-memory log. Remove device UUIDs before sharing logs.

## Tests

```sh
./scripts/test.sh
```

## Menu bar mode

The build script now quits ClickMapper before replacing its executable and resets only `local.clickmapper.diagnostic` Accessibility approval after signing, as requested. Each rebuild therefore requires you to grant permission again. Run `sh scripts/reset-permission.sh` to perform the same reset without rebuilding. A failed reset is reported as a script failure; inside a restricted execution environment, the reset needs to run outside the sandbox. macOS approval must still be given by the user.

ClickMapper starts as a keyboard icon in the macOS menu bar, without a Dock icon or an open window. Click the icon for an interactive panel with live pod diagrams, device cards, signal strength, scan/connect/switch controls, an output toggle, and a shortcut to the full mapper. Tap a diagram position and choose Edit to configure it. Brief presses remain highlighted for 200 ms so they are visible. Close the mapper window to leave Bluetooth and keyboard output running. Choose **Quit** in the panel to stop the app and release held keys. The process must remain running to receive Bluetooth input; menu bar mode hides the main window, it does not eliminate the background process.

This locally ad-hoc-signed build can require renewed Accessibility permission after a rebuild. If Accessibility is granted but keyboard posting is denied, fully quit via the menu and reopen the unchanged build to refresh the permission check. Output remains off at launch until explicitly enabled.
# ClickMapper

Automatic reconnect is enabled by default and can be turned off in the panel. The last device that produced a recognized state frame is remembered; only that device is retried, avoiding arbitrary selection between identically named pods. Startup and Bluetooth recovery attempt that device, and failed connections retry after a bounded 15-second attempt on an eight-second retry timer. Manual Disconnect/Cancel pauses reconnect until Resume, a manual connection, or relaunch. Output still needs to be explicitly enabled after disconnect. Discovery rows retain their positions while RSSI updates; saved devices without a current advertisement are labeled as saved.
