#!/usr/bin/env python3

"""A stand-in for sporetifyd that serves a made-up library.

For taking screenshots and looking at the app without showing anyone's real
playlists. It speaks just enough of the socket protocol for the app to open:
a sidebar, track lists, generated covers and a "playing" track. Nothing is
played and Spotify is never contacted. Every name in it is invented.

    scripts/demo-daemon.py /tmp/demo.sock &
    SPORETIFY_SOCKET=/tmp/demo.sock qs -p App.qml

Covers are drawn with Pillow into a folder beside the socket.
"""

import hashlib
import json
import os
import random
import socketserver
import sys
import time

from PIL import Image, ImageDraw, ImageFilter

ARTISTS = [
    "Velvet Harbour", "The Paper Lanterns", "Ansel Rook", "Marigold Static", "Low Tide Choir",
    "Juno Vale", "Glass Orchard", "Kite and Compass", "North Atlas", "Halcyon Drift",
    "Saffron Motel", "Odd Meridian", "Wren Calloway", "Tidal Arcade", "Pale Cartographer",
]
ALBUMS = [
    "Salt and Signal", "Rooms We Left", "A Map of Small Hours", "Undertow Season", "Lantern Weather",
    "Slow Machines", "Fieldnotes", "The Long Shallow", "Paper Moons", "Afterglow Index",
    "Second Shoreline", "Quiet Engines",
]
TITLES = [
    "Tide Pool", "Small Hours", "Lanterns", "Copper Sky", "Drift", "Northbound", "Glasshouse", "Halfway Home",
    "Static Bloom", "Undertow", "Paper Boats", "Slow Orbit", "Marigold", "The Shallows", "Night Ferry",
    "Kelp Forest", "Afterglow", "Blue Hour", "Open Water", "Fireflies", "Low Sun", "Salt", "Cartography",
    "Wavelength", "Moth Light", "Second Wind", "Harbour Lights", "Soft Machine", "Evergreen", "Sundial",
    "Hollow Coast", "Quiet Engine", "Field Recording", "Lighthouse", "Spore", "Meridian", "Driftwood",
    "Silver Lining", "Rain Garden", "Long Way Round",
]
PLAYLISTS = [
    ("Liked Songs", None, 0, False),
    ("Morning Tide", 24, 0, True),
    ("Deep Focus", 31, 0, True),
    ("Night Drive", 18, 0, True),
    ("Sunday Slow", 22, 0, True),
    ("Kitchen Radio", 40, 0, True),
    ("Moods", "folder", 0, False),
    ("Rainy Window", 16, 1, True),
    ("Golden Hour", 27, 1, True),
    ("Loud and Fast", 35, 1, True),
    ("Road Trip 2026", 52, 0, True),
    ("Instrumental", 29, 0, True),
    ("Songs for Coding", 44, 0, True),
    ("Tide Pool Radio", 50, 0, False),
    ("Found This Week", 12, 0, True),
]
FOR_YOU = ["Discover Weekly", "Release Radar", "On Repeat", "Daily Mix 1", "Daily Mix 2"]

art_dir = ""


def slug(text):
    return hashlib.sha1(text.encode()).hexdigest()[:22]


def cover(name):
    """A generated picture for `name`: a soft gradient with a few shapes."""
    path = os.path.join(art_dir, slug(name) + ".jpg")
    if os.path.exists(path):
        return path
    rng = random.Random(name)
    size = 320
    hue = rng.random()

    def colour(shift, light):
        import colorsys
        r, g, b = colorsys.hls_to_rgb((hue + shift) % 1.0, light, 0.55)
        return int(r * 255), int(g * 255), int(b * 255)

    top, bottom = colour(0.0, 0.32), colour(0.12, 0.62)
    image = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        t = y / size
        draw.line([(0, y), (size, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    for _ in range(rng.randint(2, 4)):
        radius = rng.randint(30, 130)
        x, y = rng.randint(0, size), rng.randint(0, size)
        draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=colour(rng.uniform(0.3, 0.6), rng.uniform(0.35, 0.75)))
    image = image.filter(ImageFilter.GaussianBlur(rng.choice([0, 2, 6])))
    image.save(path, quality=88)
    return path


def track(seed):
    rng = random.Random(seed)
    title, artist, album = rng.choice(TITLES), rng.choice(ARTISTS), rng.choice(ALBUMS)
    artists = [artist] + ([rng.choice(ARTISTS)] if rng.random() < 0.15 else [])
    return {
        "uri": "spotify:track:" + slug("t" + seed), "title": title, "artists": artists,
        "artist_uris": ["spotify:artist:" + slug("a" + name) for name in artists],
        "album": album, "album_uri": "spotify:album:" + slug("b" + album),
        "duration_ms": rng.randint(138, 322) * 1000, "available": True,
        "liked": rng.random() < 0.3, "art_url": "demo:" + album, "art_path": cover(album),
    }


def playlist_uri(name):
    return "spotify:user:demo:collection" if name == "Liked Songs" else "spotify:playlist:" + slug("p" + name)


LENGTHS = {name: (length if isinstance(length, int) else 214) for name, length, _, _ in PLAYLISTS if length != "folder"}
LENGTHS.update({name: 30 for name in FOR_YOU})
BY_URI = {playlist_uri(name): name for name in LENGTHS}


def tracks_of(name):
    rows = [track(name + str(i)) for i in range(LENGTHS[name])]
    if name == "Liked Songs":
        for row in rows:
            row["liked"] = True
    return rows


PLAYING = {}
state = {"playing": True, "volume": 0.72, "shuffle": False, "repeat": False, "seq": 1,
         "position_ms": 48000, "at_ms": int(time.time() * 1000)}


def player():
    return {
        "device": "Sporetify", "playing": state["playing"], "volume": state["volume"],
        "shuffle": state["shuffle"], "repeat": state["repeat"], "seq": state["seq"],
        "position": {"position_ms": state["position_ms"], "at_ms": state["at_ms"], "rate": 1.0 if state["playing"] else 0.0},
        "track": {"id": PLAYING["uri"], "title": PLAYING["title"], "artists": PLAYING["artists"], "album": PLAYING["album"],
                  "duration_ms": PLAYING["duration_ms"], "art_url": PLAYING["art_url"], "art_path": PLAYING["art_path"]},
    }


def answer(op, args):
    if op == "player.get":
        return {"status": "ready", "player": player()}
    if op == "library.playlists":
        items = []
        for name, length, depth, editable in PLAYLISTS:
            if length == "folder":
                items.append({"kind": "folder", "id": slug(name), "name": name, "depth": depth})
            else:
                items.append({"uri": playlist_uri(name), "name": name, "length": length, "depth": depth, "editable": editable})
        return {"items": items, "stale": False}
    if op == "library.tracks":
        name = BY_URI.get(args.get("uri"), "Morning Tide")
        rows = tracks_of(name)
        offset, limit = int(args.get("offset", 0)), int(args.get("limit", 100))
        return {"uri": args.get("uri"), "name": name, "total": len(rows), "offset": offset,
                "items": rows[offset:offset + limit], "art_url": "demo:" + name}
    if op == "library.made_for_you":
        return {"items": [{"uri": playlist_uri(name), "name": name, "owner": "Spotify", "art_url": "demo:" + name} for name in FOR_YOU]}
    if op == "art.get":
        return {"path": cover(str(args.get("url", "")).removeprefix("demo:"))}
    if op in ("library.is_saved", "library.save", "library.unsave"):
        return {"uri": args.get("uri"), "liked": op != "library.unsave"}
    if op == "library.search":
        return {"query": args.get("query", ""), "items": [], "total": 0, "indexing": False}
    if op == "search":
        return {"query": args.get("query", ""), "tracks": [], "artists": [], "albums": [], "playlists": []}
    if op == "player.up_next":
        rows = tracks_of("Morning Tide")[4:]
        return {"context_uri": playlist_uri("Morning Tide"), "context_name": "Morning Tide", "position": 3,
                "total": LENGTHS["Morning Tide"], "shuffle": False, "items": rows}
    if op in ("subscribe", "unsubscribe"):
        return {"topics": args.get("topics", [])}
    return {}


class Connection(socketserver.StreamRequestHandler):
    def send(self, frame):
        self.wfile.write((json.dumps(frame) + "\n").encode())
        self.wfile.flush()

    def handle(self):
        self.send({"ev": "hello", "protocol": 0, "daemon": "0.1.0", "status": "ready", "player": player()})
        for line in self.rfile:
            try:
                request = json.loads(line)
            except ValueError:
                continue
            if "id" not in request:
                continue
            op = request.get("op", "")
            if op in ("player.toggle", "player.play", "player.pause"):
                state["playing"] = op == "player.play" or (op == "player.toggle" and not state["playing"])
                state["seq"] += 1
                self.send({"ev": "player", "player": player()})
            self.send({"id": request["id"], "ok": True, "stale": False, "final": True, "data": answer(op, request.get("args") or {})})


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def main():
    global art_dir
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    art_dir = path + ".art"
    os.makedirs(art_dir, exist_ok=True)
    # Drawn now, not at import: the covers need the folder above.
    PLAYING.update(track("Morning Tide3"), liked=True)
    if os.path.exists(path):
        os.remove(path)
    with Server(path, Connection) as server:
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            os.remove(path)


if __name__ == "__main__":
    main()
