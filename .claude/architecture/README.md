# Sporetify architecture plan

Status: **M0 and M1 done; the full app has library browsing, playback and library search** (see the roadmap). These
documents are the working design; `CLAUDE.md` at the repo root holds the rules that the design must obey.

| Doc | Contents |
| --- | --- |
| [01-overview.md](01-overview.md) | Processes, who owns what, lifecycles, data flow |
| [02-daemon.md](02-daemon.md) | `sporetifyd`: modules, state, cache, auth, failure handling |
| [03-protocol.md](03-protocol.md) | Socket protocol between daemon and frontends (draft v0) |
| [04-frontends.md](04-frontends.md) | Shell plugin and full app: QML structure, state, keymap, theme |
| [05-visuals.md](05-visuals.md) | Spore-inspired visual language and how it is rendered cheaply |
| [06-roadmap.md](06-roadmap.md) | Milestones, each with a runnable result |
| [07-plan.md](07-plan.md) | What to work on next, in order |

## Decisions so far

| # | Decision | Why |
| --- | --- | --- |
| D1 | One Rust daemon owns audio, network, auth and cache; QML only renders | Keeps slow work off every UI thread; one place enforces deadlines |
| D2 | Full app is its own Quickshell process, not a shell `panel` | A heavy view cannot stall the bar, notifications or lock screen |
| D3 | Frontends drive transport over the socket; the daemon also serves MPRIS for media keys and other desktop tools | The socket ops were needed anyway and give optimistic state in one place; MPRIS is the compatibility surface |
| D4 | Daemon is systemd socket-activated and exits when idle | No lifecycle code in QML, nothing running when not in use |
| D5 | Protocol is newline-delimited JSON over a Unix socket | Trivial to speak from QML (`Quickshell.Io.Socket`) and to debug with `socat` |
| D6 | One keymap table drives handlers, hints and help | Hints can never drift from behaviour |
| D7 | Organisms are generated from the track id by a pure function | Deterministic, testable, no assets, no network |
| D9 | Frontends hold the socket only while needed (surface open, request in flight, 10 s linger) | A permanently connected bar would keep the daemon from ever idling out |
| D10 | A request sent on a connection that drops fails `offline` at once; unsent ones wait for reconnect until their deadline | Fast failure beats silently replaying a command the user may no longer want |
| D11 | Library, metadata and playback go through the librespot session's internal API; the public Web API is optional and only used with a user-supplied client id | Probe showed the Web API is 429 for the built-in id, while the session API works with no id |
| D12 | Two searches: `/` for all of Spotify (the search service its own apps use), `Ctrl F` for the user's library (cached, instant), each filterable by kind of result | Owner's call on 2026-10-06 to keep them apart. The library one works offline and never fails; the Spotify one needs no client id but depends on a query hash Spotify may retire |
| D13 | Caches are plain JSON files written atomically | Small data, one writer; simpler than a database and enough so far |
| D14 | In-app actions must feel instant; app launch time is not a goal | Owner's call on 2026-10-06: playing, browsing and searching matter, a second to open the window does not |
| D15 | Plugin id stays `namelessnovice.sporetify`; licence is MIT | Owner's call on 2026-10-06 |
| D8 | Audio-reactive data comes from the daemon's own audio path | No dependency on cava or a PipeWire monitor; zero cost when nobody subscribes |

## Open questions

Resolve these before or during the milestone noted; record the answer above.

1. **Login model (M1).** Answered by a live probe on 2026-10-05 (librespot
   0.8.0, Premium account, no client id of our own):
   - Sign-in through librespot's built-in OAuth works and the session connects.
   - The public Web API (`api.spotify.com/v1/...`) answers `429` to every
     call with either token that sign-in yields (the OAuth token and the
     login5 token). The built-in id's quota is shared and spent. Unusable.
   - Spotify's internal API through the session works with no client id:
     the user's playlists (rootlist), liked songs (collection context) and
     track metadata all returned data.
   - The `searchview` endpoints do not work (`400` to every parameter set
     tried, `404` over mercury), but Spotify's GraphQL search does: found on
     2026-10-06, see D12.

   Consequence: playback and library are built on the session, not the Web
   API. A user-supplied client id is optional and only ever adds things
   (search fallback, anything the internal API cannot do). See D11.
   Build note: librespot-core 0.8.0 needs `vergen` pinned to 9.0.4 and
   `vergen-gitcl` to 1.0.5 or its build script fails to compile.
2. **Shared QML (M2).** Answered: the app's entry file is `App.qml` at the
   repo root, started with `qs -p <repo>/App.qml`, which makes the repo root
   the config folder so `app/` and `common/` both resolve. Singletons
   (`pragma Singleton` + `Singleton {}`) work from either folder.
3. **App cold start (M2).** Closed: measured at about 970 ms to a mapped
   window. Not pursued, see D14.
4. **Cache store (M3).** Answered: JSON files, see D13.
5. **Web API coverage (M3).** Moot without a client id of our own, see D11.
6. **Plugin id.** Answered: it stays, see D15.
7. **Galaxy view scale (M4).** How many stars can be drawn as one shader pass
   before it costs more than the list it sits beside.
