# 07 · Plan from here

Written 2026-10-12, with everything up to `a98b8c8` on `main`. The roadmap
([06-roadmap.md](06-roadmap.md)) records what was built milestone by
milestone; this is the order to continue in. Each phase is one branch and
one pull request, small enough to finish and merge.

The order follows what the owner said matters: things done inside the app
must feel right and work, then the wishlist, then getting it into other
people's hands. The larger Spore scenes come last because nothing else
waits on them.

## Phase 1 · Make what exists trustworthy (done on `phase-1-trustworthy`)

Outcome: the owner did the hand checks on 2026-10-12 and reported everything
working. The liked-state fix, the cover cache limit, tests for `persist`,
library search, the offline fallback, liked matching, cache eviction and
player state, and the mini-player's like button are in. One change from the
list below: the mini-player got like but not queue, because the only track
it knows is the one already playing.

Original list:

Nothing new for the user to learn; the point is that everything already
there is known to work.

- **Check by hand what was only driven over IPC.** A track queued with `e`
  plays next; right click and middle click on the bar; `/`, `Ctrl F`, `Tab`
  and `Esc` as real key presses; the heart in the now-playing bar; the
  shuffle and repeat buttons; a light theme; a second monitor if one is
  available. Fix whatever turns up. Needs the owner at the keyboard.
- **Liked state of the playing track.** It is wrong when Spotify plays a
  different version of a song than the one that was liked. Match on more
  than the uri (title plus first artist, or the album), or ask the
  collection service directly.
- **Cover cache limit.** Covers are never removed. Cap the folder by size
  and drop the least recently used.
- **Tests for the daemon's own logic.** `persist` round trip, library search
  matching, folder parsing (exists), player state transitions from events,
  the offline fallback of `library.playlists` and `library.tracks`.
- **Tidy the roadmap.** Several "still to do" lists in it name things that
  have since been built (folders, artwork, search). Bring them in line.
- **Mini-player catches up with the app:** like (`f`) and queue (`e`) for the
  playing track, since the shared player code already has them.

Done when: the hand check list is ticked off, `scripts/test.sh` covers the
new tests, and the roadmap has no stale claims.

## Phase 2 · The wishlist's quick wins (done on `phase-2-wishlist`)

Outcome: all three are built. The investigation found that nothing lists the
made-for-you playlists, but Spotify-wide search finds each by name with
Spotify as owner, so "For you" looks them up that way. Artist radio comes
from `/inspiredby-mix/v2/seed_to_playlist/<artist uri>`, which answers with
the radio playlist's uri; "This Is" from search, like the others.

Original list:

- **Heart on Liked Songs in the sidebar.** Sidebar only.
- **"This Is" and radio on artist pages.**
  - "This Is <artist>": Spotify-wide playlist search already finds these by
    name; filter to the one owned by Spotify and add it as a row at the top
    of the artist page.
  - Artist radio: librespot has `get_radio_for_track` and
    `get_apollo_station`, never tried. Probe them with `debug.spclient`
    first. If they work, add a "Radio" row that plays the station.
- **"For you" / Discover: investigate, half a day at most.** Look for a home
  or recommendations query on the GraphQL service that search uses, with
  `debug.http`. Check whether Discover Weekly and the daily mixes are simply
  playlists that can be opened by uri or found in the rootlist.
  - Reachable: build a "For you" entry in the sidebar that lists them.
  - Not reachable: write down what was tried and close the item.

Done when: the heart and the artist-page rows are in, and "For you" is
either built or closed with a written reason.

## Phase 3 · Ready for other people (built, not released)

`omarchy plugin add` clones a repository and runs nothing, while Sporetify
also needs a daemon binary, systemd units and a launcher. So:

- **Install path.** Built. `scripts/setup.sh` downloads the daemon for the
  plugin's version from the GitHub release, checks its checksum, and falls
  back to building it (or builds at once with `--build`); it then installs
  the daemon, the units and the launcher, after checking for `jq`,
  `systemctl`, `secret-tool`, `qs`, `hyprctl` and libpulse.
  `.github/workflows/release.yml` builds and attaches that daemon when a tag
  `v<version>` is pushed.
- **First run without the daemon, and updates.** Built. The app and the
  mini-player say the daemon is missing or of another version and show the
  setup command (`common/Faults.js`); setup ends by saying a shell restart
  is needed.
- **Uninstall for end users.** Built: `scripts/uninstall.sh`, with `--purge`
  for caches, saved state, preferences and the keyring entry.
- **Versioning.** `CHANGELOG.md` started; the lint checks that the manifest,
  the daemon and the changelog name the same version.
- **README for strangers.** Rewritten: the unofficial-API caveat first,
  requirements, install, update, remove. No screenshots yet.

Tested: setup and uninstall in a throwaway home folder with stand-ins for
`systemctl` and the keyring: download with a good checksum, a bad checksum
(falls back to building), no release (builds), uninstall with and without
`--purge`.

Not tested, because each needs the owner's go-ahead or another machine:

- The release workflow has never run (a workflow can only be started by
  hand once it is on `main`, and a real release needs a tag).
- Downloading from GitHub itself: the repository is private, so an
  anonymous download fails and setup builds from source.
- A clean Omarchy install from `plugin add` to music.

Left for the owner to decide: make the repository public; keep the name;
tag `v0.1.0`. Omarchy has no plugin directory to submit to: `omarchy plugin
add` takes any git URL, and its catalogue only lists what is installed.

Also still open from M5 in the roadmap: opening `spotify:` links, an icon
of our own, screenshots.

Done when: on a clean Omarchy install, `plugin add`, one setup command and a
sign-in give a working Sporetify.

## Phase 4 · Spore, properly

- **Audio tap in the daemon** (`viz`): band energies and a beat pulse from
  the playback path, sent only to subscribers.
- **Creatures react to the music** in the bar, mini-player and app.
- **Tide-pool now-playing view:** the playing track's creature drifting in a
  scene, its neighbours at the edges.
- **Helix loader** in place of "Loading…".
- **Screensaver** (wishlist, least urgent): the tide pool, full screen, with
  nothing staying in one place, so it can be left on without burn-in. See
  whether Omarchy's screensaver hook can launch it.
- **A "reduced" visuals setting** between on and off, and a measurement of
  what the animation costs on integrated graphics.

Done when: the tide pool runs within the budget in [05-visuals.md](05-visuals.md)
and the app is still complete with visuals off.

## Later, in no order

- Devices view and moving playback between devices. Needs device
  information librespot does not hand out; look for it in the dealer
  messages or the connect-state service.
- Telling the user when another device took over. Same source.
- Reading, reordering and clearing the queue. Not exposed by librespot.
- Opening `spotify:` links in Sporetify.
- Media keys waking a daemon that has idled out.
- Batched metadata lookups, to make first-time indexing faster.
- Zoom transitions, group visuals for albums and playlists, the galaxy view.

## Standing risks

- **Spotify can break any of this.** Sign-in uses Spotify's own desktop
  client id; library, likes, queueing and search use undocumented services.
  The search query hash in particular can be retired without notice.
- **librespot is pinned** (0.8.0, with `vergen` held back). An upgrade may
  change the internal API this leans on.
- **The owner's machine is the test bed.** Tests that play, like or queue
  touch a real account in daily use; see the rules in `CLAUDE.md`.
