//! The audio tap behind `viz` events: band energies and a beat pulse from
//! the audio this device plays, about 30 times a second, for clients that
//! subscribe to the `viz` topic (decision D8).
//!
//! `Tap` wraps the real audio sink. Audio passes through untouched; it is
//! only analysed while someone is subscribed, so the cost is nil otherwise.
//! The analysis is a 4096-point FFT every 1/30 s, summed into 16 bands
//! spaced evenly in pitch.
//! Audio is written ahead of what is heard (the sound server's buffer), so
//! each frame carries the moment its audio will play and `Hub::deliver`
//! holds it until then. The time is found by counting what was written
//! since the sink started: the sound server plays it back in real time.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use librespot_playback::audio_backend::{Sink, SinkResult};
use librespot_playback::convert::Converter;
use librespot_playback::decoder::AudioPacket;
use librespot_playback::{NUM_CHANNELS, SAMPLE_RATE};
use serde_json::json;
use tokio::sync::{broadcast, mpsc};

use crate::proto;

/// Number of bands, log-spaced from the low bass to the highs.
pub const BANDS: usize = 16;
/// Frames per second.
pub const RATE: u32 = 30;
/// Audio frames (one sample per channel) per viz frame.
const HOP: usize = (SAMPLE_RATE / RATE) as usize;
const LOWEST_HZ: f64 = 40.0;
const HIGHEST_HZ: f64 = 14_000.0;
/// How far below the loudest recent band a band reads as zero.
const RANGE_DB: f64 = 36.0;
/// The loudest-recent level falls by this per frame (about 6 dB in 3 s), so
/// quiet passages still move.
const PEAK_DECAY: f64 = 0.992;
/// Below this (about -70 dBFS) everything counts as silence.
const SILENCE: f64 = 3e-4;
/// A beat: bass this much above its recent average, at most every ~270 ms.
const ONSET: f64 = 1.35;
const BEAT_GAP: u32 = 8;
const BEAT_DECAY: f64 = 0.72;
/// Frames waiting for their moment: more than any sound server buffers.
const QUEUE: usize = 512;

/// One frame: each band 0..1, and a beat pulse that jumps to 1 and decays.
#[derive(Debug, Clone, PartialEq)]
pub struct Frame {
    pub bands: [f64; BANDS],
    pub beat: f64,
}

impl Frame {
    pub fn silent() -> Self {
        Self { bands: [0.0; BANDS], beat: 0.0 }
    }

    pub fn line(&self) -> String {
        let round = |v: f64| (v * 100.0).round() / 100.0;
        let bands: Vec<f64> = self.bands.iter().map(|v| round(*v)).collect();
        proto::event("viz", json!({ "bands": bands, "beat": round(self.beat) }))
    }
}

/// Samples in each spectrum: 93 ms, enough to tell 40 Hz from 55 Hz.
const FFT: usize = 4096;
/// A frame describes the audio around the middle of its window, so it is
/// due that much before the window's last sample plays.
pub const CENTRE_FRAMES: u64 = FFT as u64 / 2;

/// An in-place radix-2 FFT of a fixed size, with its tables made once.
struct Fft {
    cos: Vec<f64>,
    sin: Vec<f64>,
    reversed: Vec<usize>,
}

impl Fft {
    fn new(size: usize) -> Self {
        let bits = size.trailing_zeros();
        let half = size / 2;
        let angle = |k: usize| -2.0 * std::f64::consts::PI * k as f64 / size as f64;
        Self {
            cos: (0..half).map(|k| angle(k).cos()).collect(),
            sin: (0..half).map(|k| angle(k).sin()).collect(),
            reversed: (0..size).map(|i| i.reverse_bits() >> (usize::BITS - bits)).collect(),
        }
    }

    fn run(&self, re: &mut [f64], im: &mut [f64]) {
        let size = re.len();
        for i in 0..size {
            let j = self.reversed[i];
            if i < j {
                re.swap(i, j);
                im.swap(i, j);
            }
        }
        let mut span = 2;
        while span <= size {
            let step = size / span;
            for start in (0..size).step_by(span) {
                for k in 0..span / 2 {
                    let (c, s) = (self.cos[k * step], self.sin[k * step]);
                    let (a, b) = (start + k, start + k + span / 2);
                    let tr = re[b] * c - im[b] * s;
                    let ti = re[b] * s + im[b] * c;
                    re[b] = re[a] - tr;
                    im[b] = im[a] - ti;
                    re[a] += tr;
                    im[a] += ti;
                }
            }
            span *= 2;
        }
    }
}

/// Turns samples into frames. Pure: no clock, no I/O.
pub struct Analyser {
    fft: Fft,
    window: Vec<f64>,
    /// Which FFT bins make up each band: [first, end).
    bins: [(usize, usize); BANDS],
    /// The last `FFT` mono samples, oldest first from `at`.
    history: Vec<f64>,
    at: usize,
    count: usize,
    re: Vec<f64>,
    im: Vec<f64>,
    peak: f64,
    bass_average: f64,
    since_beat: u32,
    beat: f64,
}

impl Default for Analyser {
    fn default() -> Self {
        let ratio = (HIGHEST_HZ / LOWEST_HZ).powf(1.0 / BANDS as f64);
        let hz_per_bin = SAMPLE_RATE as f64 / FFT as f64;
        let bins = std::array::from_fn(|i| {
            let low = (LOWEST_HZ * ratio.powi(i as i32) / hz_per_bin).round() as usize;
            let high = (LOWEST_HZ * ratio.powi(i as i32 + 1) / hz_per_bin).round() as usize;
            (low.max(1), high.max(low.max(1) + 1).min(FFT / 2))
        });
        let window = (0..FFT)
            .map(|i| 0.5 - 0.5 * (2.0 * std::f64::consts::PI * i as f64 / FFT as f64).cos())
            .collect();
        Self {
            fft: Fft::new(FFT),
            window,
            bins,
            history: vec![0.0; FFT],
            at: 0,
            count: 0,
            re: vec![0.0; FFT],
            im: vec![0.0; FFT],
            peak: SILENCE,
            bass_average: 0.0,
            since_beat: BEAT_GAP,
            beat: 0.0,
        }
    }
}

impl Analyser {
    /// Feed interleaved stereo samples. `emit(frames_in, frame)` is called
    /// for each finished frame, with how many audio frames of this packet
    /// it covers, so the caller can tell when it will be heard.
    pub fn push(&mut self, samples: &[f64], mut emit: impl FnMut(usize, Frame)) {
        let channels = NUM_CHANNELS as usize;
        for (index, pair) in samples.chunks_exact(channels).enumerate() {
            self.history[self.at] = pair.iter().sum::<f64>() / channels as f64;
            self.at = (self.at + 1) % FFT;
            self.count += 1;
            if self.count == HOP {
                self.count = 0;
                let frame = self.finish();
                emit(index + 1, frame);
            }
        }
    }

    fn finish(&mut self) -> Frame {
        for i in 0..FFT {
            self.re[i] = self.history[(self.at + i) % FFT] * self.window[i];
            self.im[i] = 0.0;
        }
        self.fft.run(&mut self.re, &mut self.im);
        // A sine of amplitude A reads as A: the Hann window keeps a quarter.
        let scale = 4.0 / FFT as f64;
        let amplitude: [f64; BANDS] = std::array::from_fn(|b| {
            let (first, end) = self.bins[b];
            let power: f64 = (first..end).map(|k| self.re[k] * self.re[k] + self.im[k] * self.im[k]).sum();
            power.sqrt() * scale
        });

        // One shared reference level, so the shape of the spectrum survives
        // and the volume does not matter.
        let loudest = amplitude.iter().cloned().fold(0.0, f64::max);
        self.peak = (self.peak * PEAK_DECAY).max(loudest).max(SILENCE);
        let bands = std::array::from_fn(|i| {
            if amplitude[i] < SILENCE {
                return 0.0;
            }
            let db = 20.0 * (amplitude[i] / self.peak).log10();
            ((db + RANGE_DB) / RANGE_DB).clamp(0.0, 1.0)
        });

        let bass = amplitude[0].hypot(amplitude[1]).hypot(amplitude[2]);
        self.since_beat = self.since_beat.saturating_add(1);
        if bass > SILENCE && bass > self.bass_average * ONSET && self.since_beat >= BEAT_GAP {
            self.beat = 1.0;
            self.since_beat = 0;
        } else {
            self.beat *= BEAT_DECAY;
        }
        self.bass_average = self.bass_average * 0.9 + bass * 0.1;

        Frame { bands, beat: self.beat }
    }
}

/// A frame line and the moment its audio plays.
type Due = (Instant, Arc<str>);

/// Where frames go: held until their audio plays, then to every subscriber.
pub struct Hub {
    due: mpsc::Sender<Due>,
    waiting: Mutex<Option<mpsc::Receiver<Due>>>,
    out: broadcast::Sender<Arc<str>>,
}

impl Default for Hub {
    fn default() -> Self {
        let (due, waiting) = mpsc::channel(QUEUE);
        // Lossy: a subscriber that falls behind skips frames.
        let (out, _) = broadcast::channel(4);
        Self { due, waiting: Mutex::new(Some(waiting)), out }
    }
}

impl Hub {
    pub fn subscribe(&self) -> broadcast::Receiver<Arc<str>> {
        self.out.subscribe()
    }

    /// Whether anyone listens. The tap does no analysis otherwise.
    pub fn wanted(&self) -> bool {
        self.out.receiver_count() > 0
    }

    /// Send `frame` to subscribers at `at`.
    pub fn schedule(&self, at: Instant, frame: &Frame) {
        // Full means nobody is draining it; dropping a frame is fine.
        let _ = self.due.try_send((at, frame.line().into()));
    }

    /// Release each frame when its audio plays. Runs for the daemon's life.
    pub async fn deliver(&self) {
        let waiting = self.waiting.lock().expect("viz lock").take();
        let Some(mut waiting) = waiting else {
            return std::future::pending().await;
        };
        while let Some((at, line)) = waiting.recv().await {
            tokio::time::sleep_until(at.into()).await;
            let _ = self.out.send(line);
        }
    }
}

fn audio_time(frames: u64) -> Duration {
    Duration::from_secs_f64(frames as f64 / SAMPLE_RATE as f64)
}

/// The real sink, with the analyser listening in.
pub struct Tap {
    inner: Box<dyn Sink>,
    hub: Arc<Hub>,
    analyser: Analyser,
    /// When the first frame written since `start` plays.
    started: Option<Instant>,
    /// Audio frames written since `start`.
    written: u64,
    /// Whether frames were being sent, so a stop can settle the clients.
    sending: bool,
}

impl Tap {
    pub fn new(inner: Box<dyn Sink>, hub: Arc<Hub>) -> Self {
        Self { inner, hub, analyser: Analyser::default(), started: None, written: 0, sending: false }
    }
}

impl Sink for Tap {
    fn start(&mut self) -> SinkResult<()> {
        self.inner.start()?;
        self.started = Some(Instant::now());
        self.written = 0;
        self.analyser = Analyser::default();
        Ok(())
    }

    fn stop(&mut self) -> SinkResult<()> {
        // Returns once the buffered audio has played.
        let result = self.inner.stop();
        self.started = None;
        if self.sending {
            self.sending = false;
            self.hub.schedule(Instant::now(), &Frame::silent());
        }
        result
    }

    fn write(&mut self, packet: AudioPacket, converter: &mut Converter) -> SinkResult<()> {
        if let (AudioPacket::Samples(samples), Some(mut start)) = (&packet, self.started) {
            // Writing later than the audio before it would finish means the
            // buffer ran dry and playback resumed late: move the clock on.
            let now = Instant::now();
            if start + audio_time(self.written) < now {
                start = now - audio_time(self.written);
                self.started = Some(start);
            }
            if self.hub.wanted() {
                self.sending = true;
                let written = self.written;
                let hub = &self.hub;
                self.analyser.push(samples, |frames, frame| {
                    let heard = (written + frames as u64).saturating_sub(CENTRE_FRAMES);
                    hub.schedule(start + audio_time(heard), &frame);
                });
            } else if self.sending {
                self.sending = false;
            }
            self.written += (samples.len() / NUM_CHANNELS as usize) as u64;
        }
        self.inner.write(packet, converter)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(hz: f64, amplitude: f64, seconds: f64) -> Vec<f64> {
        let frames = (SAMPLE_RATE as f64 * seconds) as usize;
        let mut out = Vec::with_capacity(frames * 2);
        for i in 0..frames {
            let v = amplitude * (2.0 * std::f64::consts::PI * hz * i as f64 / SAMPLE_RATE as f64).sin();
            out.push(v);
            out.push(v);
        }
        out
    }

    fn frames(analyser: &mut Analyser, samples: &[f64]) -> Vec<Frame> {
        let mut out = Vec::new();
        analyser.push(samples, |_, frame| out.push(frame));
        out
    }

    fn loudest(frame: &Frame) -> usize {
        (0..BANDS).max_by(|a, b| frame.bands[*a].total_cmp(&frame.bands[*b])).unwrap()
    }

    #[test]
    fn about_thirty_frames_a_second() {
        let out = frames(&mut Analyser::default(), &tone(440.0, 0.5, 1.0));
        assert_eq!(out.len(), RATE as usize);
    }

    #[test]
    fn silence_is_all_zero() {
        let out = frames(&mut Analyser::default(), &vec![0.0; SAMPLE_RATE as usize * 2]);
        assert!(out.iter().all(|f| f.bands.iter().all(|v| *v == 0.0) && f.beat == 0.0));
    }

    #[test]
    fn a_tone_lights_its_own_band() {
        for (hz, low_half) in [(60.0, true), (6000.0, false)] {
            let out = frames(&mut Analyser::default(), &tone(hz, 0.5, 1.0));
            let last = out.last().unwrap();
            let band = loudest(last);
            assert_eq!(band < BANDS / 2, low_half, "{hz} Hz lit band {band}: {:?}", last.bands);
            assert!(last.bands[band] > 0.9);
            // Far bands stay near the bottom.
            let far = if low_half { BANDS - 1 } else { 0 };
            assert!(last.bands[far] < 0.3, "{hz} Hz: {:?}", last.bands);
        }
    }

    #[test]
    fn two_far_apart_tones_light_two_bands_with_a_dip_between() {
        let low = tone(60.0, 0.4, 1.0);
        let high = tone(3000.0, 0.4, 1.0);
        let mixed: Vec<f64> = low.iter().zip(&high).map(|(a, b)| a + b).collect();
        let out = frames(&mut Analyser::default(), &mixed);
        let bands = out.last().unwrap().bands;
        let band = |hz: f64| ((hz / LOWEST_HZ).ln() / (HIGHEST_HZ / LOWEST_HZ).ln() * BANDS as f64) as usize;
        assert!(bands[band(60.0)] > 0.9, "{bands:?}");
        assert!(bands[band(3000.0)] > 0.9, "{bands:?}");
        assert!(bands[band(450.0)] < 0.4, "nothing plays at 450 Hz: {bands:?}");
    }

    #[test]
    fn the_volume_does_not_matter() {
        let loud = frames(&mut Analyser::default(), &tone(250.0, 0.8, 1.0));
        let quiet = frames(&mut Analyser::default(), &tone(250.0, 0.05, 1.0));
        let (a, b) = (loud.last().unwrap(), quiet.last().unwrap());
        for i in 0..BANDS {
            assert!((a.bands[i] - b.bands[i]).abs() < 0.02, "band {i}: {} vs {}", a.bands[i], b.bands[i]);
        }
    }

    #[test]
    fn a_kick_twice_a_second_is_two_beats() {
        // 80 ms of 55 Hz every 500 ms, a quiet high tone throughout.
        let mut samples = Vec::new();
        for _ in 0..4 {
            let kick = tone(55.0, 0.7, 0.08);
            let pad = tone(3000.0, 0.02, 0.42);
            samples.extend(kick.iter().zip(tone(3000.0, 0.02, 0.08).iter()).map(|(a, b)| a + b));
            samples.extend(pad);
        }
        let out = frames(&mut Analyser::default(), &samples);
        let beats = out.iter().filter(|f| f.beat == 1.0).count();
        assert_eq!(beats, 4, "beats: {:?}", out.iter().map(|f| f.beat).collect::<Vec<_>>());
    }

    /// What the analysis costs, as a share of one core while music plays:
    /// `cargo test --release viz::tests::cost -- --ignored --nocapture`.
    #[test]
    #[ignore]
    fn cost() {
        let audio = tone(440.0, 0.4, 10.0);
        let mut analyser = Analyser::default();
        let started = Instant::now();
        let mut count = 0;
        analyser.push(&audio, |_, frame| count += frame.line().len().min(1));
        let share = started.elapsed().as_secs_f64() / 10.0 * 100.0;
        println!("viz analysis: {share:.2} % of a core ({count} frames)");
    }

    struct Null;
    impl Sink for Null {
        fn write(&mut self, _: AudioPacket, _: &mut Converter) -> SinkResult<()> {
            Ok(())
        }
    }

    #[test]
    fn frames_are_due_when_their_audio_plays() {
        let hub = Arc::new(Hub::default());
        let _listener = hub.subscribe();
        let mut waiting = hub.waiting.lock().unwrap().take().unwrap();
        let mut tap = Tap::new(Box::new(Null), hub.clone());
        let mut converter = Converter::new(None);
        tap.start().unwrap();
        // Two seconds written at once, as a sound server buffer allows.
        for _ in 0..4 {
            tap.write(AudioPacket::Samples(tone(440.0, 0.3, 0.5)), &mut converter).unwrap();
        }
        // Playback starts with the first write, which is where the clock sits.
        let started = tap.started.unwrap();
        let mut due = Vec::new();
        while let Ok((at, _)) = waiting.try_recv() {
            due.push(at.duration_since(started).as_secs_f64());
        }
        assert_eq!(due.len(), 2 * RATE as usize);
        // Each frame is due when the middle of its window plays.
        let centre = CENTRE_FRAMES as f64 / SAMPLE_RATE as f64;
        assert!((due[10] - (11.0 / RATE as f64 - centre)).abs() < 0.002, "{}", due[10]);
        assert!((due.last().unwrap() - (2.0 - centre)).abs() < 0.002, "{}", due.last().unwrap());

        // A stop settles the clients with one silent frame.
        tap.stop().unwrap();
        let (_, line) = waiting.try_recv().unwrap();
        assert!(line.contains("\"beat\":0.0"), "{line}");
    }

    #[test]
    fn nothing_is_analysed_without_a_listener() {
        let hub = Arc::new(Hub::default());
        let mut waiting = hub.waiting.lock().unwrap().take().unwrap();
        let mut tap = Tap::new(Box::new(Null), hub.clone());
        let mut converter = Converter::new(None);
        tap.start().unwrap();
        tap.write(AudioPacket::Samples(tone(440.0, 0.3, 0.5)), &mut converter).unwrap();
        assert!(waiting.try_recv().is_err());
        assert_eq!(tap.written, SAMPLE_RATE as u64 / 2);
    }
}
