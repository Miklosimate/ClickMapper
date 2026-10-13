# Protocol observations

## Source evidence (2026-10-13)

Community reference: https://github.com/nrbz467bct-dot/zwift-click-keyboard-mapper/blob/main/zwift_click_mapper.py

- Notification UUID: `00000002-19ca-4651-86e5-fa29dcdd09d1`
- Write UUID: `00000003-19ca-4651-86e5-fa29dcdd09d1`
- Initial writes: `526964654f6e0203`, `000800`, `000810`
- Keepalive: `000810` every five seconds
- Candidate state: seven bytes beginning `23 08`, four active-low mask bytes thereafter
- Reference names are provisional; validate physical layout locally.
- Credited upstream URL returned 404 during research.

## Hardware evidence

User corrected the initial answer on 2026-10-13: the controllers had not connected to anything previously; no prior unlock is reported. The later ten-minute trace below provides initial evidence of persistent no-unlock operation on these devices with firmware 1.0.1.

Per-pod details still to collect (session evidence is recorded below):

- Pod side:
- Firmware (if exposed):
- Recent Zwift/BikeControl unlock and approximate time:
- Service/characteristic layout:
- Five physical buttons and observed candidate IDs:
- Down/up transitions correct:
- Ten-minute session and idle/resume results:
- Disconnect/reconnect results:
- Sleep/wake results:

A successful connection or a short sequence of presses does not establish persistent support.

## First user-supplied diagnostic trace — 2026-10-13

- Connected at 20:08:34; handshake began at 20:08:35 (user's local time).
- Firmware: 1.0.1. Battery: 100%.
- Services: Device Information, FC82, Battery, F000FFC0-0451-4000-B000-000000000000.
- Community notify characteristic properties: 16 (notify); write characteristic properties: 4 (write without response).
- Unknown notifications of 23, 3, 27, and 85 bytes were received; payloads omitted. Their meaning is not established.
- Between +24 and +40 seconds, candidate IDs y, b, z, a, right, left, down, up, minus, plus each produced down and up transitions. Minus was pressed twice.
- Ten distinct decoded IDs observed through one central connection. Physical pod topology and correspondence to printed button labels still require user confirmation; do not infer two independent pod connections.
- No previous connection/unlock reported by user (corrected account).
- This verifies initial decoding only. Operation beyond one minute, ten-minute persistence, reconnects, and holds remain untested.

User confirmed that both physical pods were pressed and both worked during the initial test. Ten candidate IDs were observed through the single selected peripheral connection. The underlying inter-pod transport/topology is not established. Long-duration operation remains unverified.

Follow-up user trace: down/up transitions continued from +117 through +132 seconds (20:10:32–20:10:47 local time), including face and directional buttons. User reports all buttons work. This session passed the reported approximately one-minute cutoff; ten-minute persistence is still pending.

## Reconnection and ten-minute trace — 2026-10-13

- User reported only one pod responding after selecting the other peripheral, then confirmed both worked after a subsequent connection. Selected pod sides and the cause of the temporary one-pod behavior remain unknown.
- An attempt to connect to WH-CH720N at 20:35:10 timed out; this was a different advertised device, not evidence of a Click connection failure.
- Connected to Zwift Click at 20:35:34; handshake at 20:35:36. Firmware 1.0.1, battery 100%, and the same service layout as the first trace.
- All ten candidate IDs produced down/up transitions at +228 through +238 seconds.
- After no decoded button events between +238 and +622 seconds, plus and minus both went down at +622 and both released at +625, demonstrating an approximately three-second simultaneous hold.
- The other eight IDs produced down/up transitions at +631 through +634 seconds. All ten IDs therefore remained responsive beyond ten minutes, and the user confirmed all was good.
- Unknown notifications (including repeated three-byte notifications during the idle interval) did not prevent subsequent decoded input; their meaning remains unknown.
- The persistence and idle/resume checks passed for this session. Reconnection recovered both pods by user report, but consistent behavior across peripheral selection, physical label mapping, and sleep/wake remain unverified. This evidence does not establish compatibility with other firmware or devices.
