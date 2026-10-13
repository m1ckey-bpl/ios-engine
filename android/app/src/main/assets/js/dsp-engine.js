// Pioneer DSP - Sound Tune Audio Processing Engine & Persistent Local Storage
// Completely Free of Demo Audio, Placeholders, and Synthetic Chords

class PioneerAudioDB {
  constructor() {
    this.dbName = 'PioneerDSP_Storage_v3';
    this.version = 1;
    this.db = null;
  }

  async open() {
    if (this.db) return this.db;
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(this.dbName, this.version);
      request.onupgradeneeded = (e) => {
        const db = e.target.result;
        if (!db.objectStoreNames.contains('songs')) {
          db.createObjectStore('songs', { keyPath: 'id' });
        }
        if (!db.objectStoreNames.contains('streams')) {
          db.createObjectStore('streams', { keyPath: 'id' });
        }
      };
      request.onsuccess = (e) => {
        this.db = e.target.result;
        resolve(this.db);
      };
      request.onerror = (e) => {
        console.error('IndexedDB open error:', e);
        reject(e);
      };
    });
  }

  async saveSong(song) {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('songs', 'readwrite');
      const store = tx.objectStore('songs');
      const req = store.put(song);
      req.onsuccess = () => resolve(true);
      req.onerror = (e) => reject(e);
    });
  }

  async getAllSongs() {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('songs', 'readonly');
      const store = tx.objectStore('songs');
      const req = store.getAll();
      req.onsuccess = () => resolve(req.result || []);
      req.onerror = (e) => reject(e);
    });
  }

  async deleteSong(id) {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('songs', 'readwrite');
      const store = tx.objectStore('songs');
      const req = store.delete(id);
      req.onsuccess = () => resolve(true);
      req.onerror = (e) => reject(e);
    });
  }

  async saveStream(stream) {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('streams', 'readwrite');
      const store = tx.objectStore('streams');
      const req = store.put(stream);
      req.onsuccess = () => resolve(true);
      req.onerror = (e) => reject(e);
    });
  }

  async getAllStreams() {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('streams', 'readonly');
      const store = tx.objectStore('streams');
      const req = store.getAll();
      req.onsuccess = () => resolve(req.result || []);
      req.onerror = (e) => reject(e);
    });
  }

  async deleteStream(id) {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('streams', 'readwrite');
      const store = tx.objectStore('streams');
      const req = store.delete(id);
      req.onsuccess = () => resolve(true);
      req.onerror = (e) => reject(e);
    });
  }
}

class PioneerDSPEngine {
  constructor() {
    this.audioCtx = null;
    this.db = new PioneerAudioDB();
    
    // Playback State
    this.sourceType = 'none'; // 'buffer', 'stream', 'none'
    this.sourceNode = null;
    this.audioElement = null;
    this.mediaElementSource = null;
    this.isPlaying = false;
    this.isPaused = false;
    this.pauseOffset = 0;
    this.startTime = 0;
    this.duration = 0;

    // Track Library (100% Free of fake demo music)
    this.songs = [];
    this.currentIndex = -1;
    this.currentBuffer = null;
    this.activeTrack = null;

    // Network Streaming State
    this.networkStreams = [];
    this.activeStream = null;

    // DSP Tuning State & Parameters
    this.preampGain = 0; // -12 to +12 dB
    this.superBassGain = 0; // 0 to 12 dB (Todoroki 63Hz)
    this.deepBassGain = 0; // 0 to 8 dB (Sub-Bass 31Hz)
    this.midGain = 0; // -10 to +10 dB (1.5kHz)
    this.trebleGain = 0; // -10 to +10 dB (10kHz)
    
    this.ambienceMode = 'hall'; // 'hall', 'room', 'studio'
    this.reverbMix = 0; // 0 to 100%
    this.balance = 0; // -1.0 to +1.0
    this.cabinPosition = 'all'; // 'all', 'fl', 'fr'

    // 10-Band Graphic EQ Frequencies (ISO Standard Bands)
    this.eqFreqs = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
    this.eqFilters = [];
    this.eqGains = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

    // Audio Graph Nodes
    this.preampNode = null;
    this.superBassFilter = null;
    this.deepBassFilter = null;
    this.midFilter = null;
    this.trebleFilter = null;
    this.convolverNode = null;
    this.dryGain = null;
    this.wetGain = null;
    this.pannerNode = null;
    this.cabinDelayL = null;
    this.cabinDelayR = null;
    this.limiterNode = null;
    this.analyser = null;

    // Visualizer Spectrum Buffer
    this.spectrumBuffer = new Uint8Array(64);

    // Impulse Cache
    this.impulseBuffers = {};
  }

  // Initialize Web Audio Processing Pipeline
  async initAudioContext() {
    if (this.audioCtx && this.audioCtx.state !== 'closed') {
      if (this.audioCtx.state === 'suspended') {
        await this.audioCtx.resume();
      }
      return;
    }

    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    this.audioCtx = new AudioContextClass({ latencyHint: 'playback' });

    // 1. Preamp Gain Node (-12dB to +12dB)
    this.preampNode = this.audioCtx.createGain();
    this.preampNode.gain.value = this.dbToLinear(this.preampGain);

    // 2. 10-Band Graphic Equalizer Peaking Filters
    this.eqFilters = [];
    let prevFilter = this.preampNode;
    this.eqFreqs.forEach((freq, idx) => {
      const filter = this.audioCtx.createBiquadFilter();
      filter.type = 'peaking';
      filter.frequency.value = freq;
      filter.Q.value = 1.414; // Standard 1-octave bandwidth
      filter.gain.value = this.eqGains[idx];
      prevFilter.connect(filter);
      this.eqFilters.push(filter);
      prevFilter = filter;
    });

    // 3. Todoroki Super Bass Peaking Filter (63Hz punch, Q=1.8)
    this.superBassFilter = this.audioCtx.createBiquadFilter();
    this.superBassFilter.type = 'peaking';
    this.superBassFilter.frequency.value = 63;
    this.superBassFilter.Q.value = 1.8;
    this.superBassFilter.gain.value = this.superBassGain;
    prevFilter.connect(this.superBassFilter);

    // 4. Deep Sub-Bass Low-Shelf Filter (31Hz foundation)
    this.deepBassFilter = this.audioCtx.createBiquadFilter();
    this.deepBassFilter.type = 'lowshelf';
    this.deepBassFilter.frequency.value = 31;
    this.deepBassFilter.gain.value = this.deepBassGain;
    this.superBassFilter.connect(this.deepBassFilter);

    // 5. Midrange Tone Peaking Filter (1.5kHz vocal presence, Q=1.2)
    this.midFilter = this.audioCtx.createBiquadFilter();
    this.midFilter.type = 'peaking';
    this.midFilter.frequency.value = 1500;
    this.midFilter.Q.value = 1.2;
    this.midFilter.gain.value = this.midGain;
    this.deepBassFilter.connect(this.midFilter);

    // 6. Treble Tone High-Shelf Filter (10kHz air & clarity)
    this.trebleFilter = this.audioCtx.createBiquadFilter();
    this.trebleFilter.type = 'highshelf';
    this.trebleFilter.frequency.value = 10000;
    this.trebleFilter.gain.value = this.trebleGain;
    this.midFilter.connect(this.trebleFilter);

    // 7. Convolution Reverb Ambience Simulation & Wet/Dry Mixer
    this.convolverNode = this.audioCtx.createConvolver();
    this.convolverNode.buffer = await this.getImpulseResponse(this.ambienceMode);

    this.dryGain = this.audioCtx.createGain();
    this.wetGain = this.audioCtx.createGain();
    const wetRatio = this.reverbMix / 100.0;
    this.dryGain.gain.value = 1.0;
    this.wetGain.gain.value = wetRatio * 0.8;

    this.trebleFilter.connect(this.dryGain);
    this.trebleFilter.connect(this.convolverNode);
    this.convolverNode.connect(this.wetGain);

    // Reverb Summing Node
    const reverbSum = this.audioCtx.createGain();
    this.dryGain.connect(reverbSum);
    this.wetGain.connect(reverbSum);

    // 8. Car Cabin Time Alignment (Channel Delay Processing)
    const merger = this.audioCtx.createChannelMerger(2);
    const splitter = this.audioCtx.createChannelSplitter(2);
    this.cabinDelayL = this.audioCtx.createDelay(0.05);
    this.cabinDelayR = this.audioCtx.createDelay(0.05);
    this.updateCabinDelays();

    reverbSum.connect(splitter);
    splitter.connect(this.cabinDelayL, 0);
    splitter.connect(this.cabinDelayR, 1);
    this.cabinDelayL.connect(merger, 0, 0);
    this.cabinDelayR.connect(merger, 0, 1);

    // 9. Stereo Balance Panner Node (-1.0 Left to +1.0 Right)
    this.pannerNode = this.audioCtx.createStereoPanner();
    this.pannerNode.pan.value = this.balance;
    merger.connect(this.pannerNode);

    // 10. Peak Limiter / Dynamics Compressor (Clipping Protection)
    this.limiterNode = this.audioCtx.createDynamicsCompressor();
    this.limiterNode.threshold.value = -0.5; // Trigger at -0.5 dB
    this.limiterNode.knee.value = 2.0;
    this.limiterNode.ratio.value = 20.0; // Hard limiting ratio
    this.limiterNode.attack.value = 0.003; // 3ms fast attack
    this.limiterNode.release.value = 0.1; // 100ms release
    this.pannerNode.connect(this.limiterNode);

    // 11. 60fps Real-time Spectrum Analyser
    this.analyser = this.audioCtx.createAnalyser();
    this.analyser.fftSize = 128;
    this.analyser.smoothingTimeConstant = 0.82;
    this.limiterNode.connect(this.analyser);

    // 12. Final Audio Output Destination
    this.analyser.connect(this.audioCtx.destination);
  }

  dbToLinear(db) {
    return Math.pow(10, db / 20);
  }

  // Algorithmic Acoustic Impulse Responses
  async getImpulseResponse(mode) {
    if (this.impulseBuffers[mode]) return this.impulseBuffers[mode];
    if (!this.audioCtx) return null;

    const sampleRate = this.audioCtx.sampleRate;
    let duration = 2.8; // Concert Hall
    let decayRate = 2.2;
    let density = 0.85;

    if (mode === 'room') {
      duration = 1.4;
      decayRate = 3.5;
      density = 0.65;
    } else if (mode === 'studio') {
      duration = 0.6;
      decayRate = 6.0;
      density = 0.45;
    }

    const length = Math.floor(sampleRate * duration);
    const impulse = this.audioCtx.createBuffer(2, length, sampleRate);
    const left = impulse.getChannelData(0);
    const right = impulse.getChannelData(1);

    for (let i = 0; i < length; i++) {
      const t = i / sampleRate;
      const env = Math.exp(-t * decayRate);
      const earlyReflections = (i < sampleRate * 0.08) ? (Math.random() > (1 - density) ? 1.4 : 0.2) : 1.0;
      left[i] = (Math.random() * 2 - 1) * env * earlyReflections;
      right[i] = (Math.random() * 2 - 1) * env * earlyReflections;
    }

    this.impulseBuffers[mode] = impulse;
    return impulse;
  }

  // Real-time DSP Setters
  setPreamp(db) {
    this.preampGain = parseFloat(db);
    if (this.preampNode && this.audioCtx) {
      this.preampNode.gain.setTargetAtTime(this.dbToLinear(this.preampGain), this.audioCtx.currentTime, 0.02);
    }
  }

  setEQBand(index, gainDB) {
    this.eqGains[index] = parseFloat(gainDB);
    if (this.eqFilters[index] && this.audioCtx) {
      this.eqFilters[index].gain.setTargetAtTime(this.eqGains[index], this.audioCtx.currentTime, 0.02);
    }
  }

  setSuperBass(gainDB) {
    this.superBassGain = parseFloat(gainDB);
    if (this.superBassFilter && this.audioCtx) {
      this.superBassFilter.gain.setTargetAtTime(this.superBassGain, this.audioCtx.currentTime, 0.02);
    }
  }

  setDeepBass(gainDB) {
    this.deepBassGain = parseFloat(gainDB);
    if (this.deepBassFilter && this.audioCtx) {
      this.deepBassFilter.gain.setTargetAtTime(this.deepBassGain, this.audioCtx.currentTime, 0.02);
    }
  }

  setMid(gainDB) {
    this.midGain = parseFloat(gainDB);
    if (this.midFilter && this.audioCtx) {
      this.midFilter.gain.setTargetAtTime(this.midGain, this.audioCtx.currentTime, 0.02);
    }
  }

  setTreble(gainDB) {
    this.trebleGain = parseFloat(gainDB);
    if (this.trebleFilter && this.audioCtx) {
      this.trebleFilter.gain.setTargetAtTime(this.trebleGain, this.audioCtx.currentTime, 0.02);
    }
  }

  async setAmbienceMode(mode) {
    this.ambienceMode = mode;
    if (this.convolverNode && this.audioCtx) {
      this.convolverNode.buffer = await this.getImpulseResponse(mode);
    }
  }

  setReverbMix(percent) {
    this.reverbMix = parseFloat(percent);
    if (this.wetGain && this.audioCtx) {
      const wetRatio = (this.reverbMix / 100.0) * 0.8;
      this.wetGain.gain.setTargetAtTime(wetRatio, this.audioCtx.currentTime, 0.03);
    }
  }

  setBalance(val) {
    this.balance = Math.max(-1, Math.min(1, parseFloat(val)));
    if (this.pannerNode && this.audioCtx) {
      this.pannerNode.pan.setTargetAtTime(this.balance, this.audioCtx.currentTime, 0.02);
    }
  }

  setCabinPosition(pos) {
    this.cabinPosition = pos;
    this.updateCabinDelays();
  }

  updateCabinDelays() {
    if (!this.cabinDelayL || !this.cabinDelayR || !this.audioCtx) return;
    const now = this.audioCtx.currentTime;
    if (this.cabinPosition === 'fl') {
      // Driver focus: delay left speaker slightly (0.9ms) to align acoustic arrival
      this.cabinDelayL.delayTime.setTargetAtTime(0.0009, now, 0.03);
      this.cabinDelayR.delayTime.setTargetAtTime(0.0, now, 0.03);
    } else if (this.cabinPosition === 'fr') {
      this.cabinDelayL.delayTime.setTargetAtTime(0.0, now, 0.03);
      this.cabinDelayR.delayTime.setTargetAtTime(0.0009, now, 0.03);
    } else {
      // Center / All Seats
      this.cabinDelayL.delayTime.setTargetAtTime(0.0, now, 0.03);
      this.cabinDelayR.delayTime.setTargetAtTime(0.0, now, 0.03);
    }
  }

  // Presets Configuration
  applyPreset(presetName) {
    const presets = {
      flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      bass: [5, 7, 5, 2, 0, 0, 0, 1, 2, 3],
      deep_bass: [7, 8, 4, 1, 0, 0, 0, 0, 1, 2],
      hall: [2, 1, 0, 0, 1, 2, 3, 4, 3, 2],
      studio: [0, 1, 2, 0, 1, 1, 2, 1, 0, 0],
      vocal: [-2, -1, 0, 2, 4, 5, 4, 2, 1, 0],
      acoustic: [3, 2, 1, 2, 3, 3, 4, 4, 3, 2],
      rock: [5, 4, 2, 0, -1, 1, 3, 5, 5, 4],
      classical: [4, 3, 2, 1, 0, 1, 2, 3, 4, 4],
      cinema: [6, 5, 2, 0, 1, 2, 4, 5, 6, 5]
    };

    const targetGains = presets[presetName] || presets.flat;
    targetGains.forEach((g, idx) => this.setEQBand(idx, g));

    if (presetName === 'bass' || presetName === 'deep_bass') {
      this.setSuperBass(presetName === 'bass' ? 8 : 4);
      this.setDeepBass(presetName === 'deep_bass' ? 6 : 2);
    } else {
      this.setSuperBass(0);
      this.setDeepBass(0);
    }

    if (presetName === 'hall') {
      this.setAmbienceMode('hall');
      this.setReverbMix(65);
    } else if (presetName === 'studio') {
      this.setAmbienceMode('studio');
      this.setReverbMix(25);
    } else if (presetName === 'cinema') {
      this.setAmbienceMode('hall');
      this.setReverbMix(50);
    } else {
      this.setReverbMix(0);
    }
  }

  resetEQ() {
    this.applyPreset('flat');
    this.setPreamp(0);
  }

  saveCustomPreset(name) {
    try {
      const presets = this.getCustomPresets();
      presets[name] = {
        eq: [...this.eqGains],
        preamp: this.preampGain,
        superBass: this.superBassGain,
        deepBass: this.deepBassGain,
        mid: this.midGain,
        treble: this.trebleGain,
        reverbMix: this.reverbMix,
        ambienceMode: this.ambienceMode
      };
      localStorage.setItem('pioneer_custom_presets', JSON.stringify(presets));
      return true;
    } catch(e) {
      return false;
    }
  }

  getCustomPresets() {
    try {
      const data = localStorage.getItem('pioneer_custom_presets');
      return data ? JSON.parse(data) : {};
    } catch(e) {
      return {};
    }
  }

  applyCustomPreset(name) {
    const presets = this.getCustomPresets();
    const p = presets[name];
    if (!p) return false;
    if (p.eq) p.eq.forEach((g, idx) => this.setEQBand(idx, g));
    if (p.preamp !== undefined) this.setPreamp(p.preamp);
    if (p.superBass !== undefined) this.setSuperBass(p.superBass);
    if (p.deepBass !== undefined) this.setDeepBass(p.deepBass);
    if (p.mid !== undefined) this.setMid(p.mid);
    if (p.treble !== undefined) this.setTreble(p.treble);
    if (p.reverbMix !== undefined) this.setReverbMix(p.reverbMix);
    if (p.ambienceMode) this.setAmbienceMode(p.ambienceMode);
    return true;
  }

  // --- Real Media Playback Pipeline ---

  // Stop any currently playing audio
  stopPlayback() {
    if (this.sourceNode) {
      try {
        this.sourceNode.stop();
        this.sourceNode.disconnect();
      } catch(e) {}
      this.sourceNode = null;
    }

    if (this.audioElement) {
      try {
        this.audioElement.pause();
        this.audioElement.src = '';
      } catch(e) {}
    }

    this.isPlaying = false;
    this.isPaused = false;
    this.pauseOffset = 0;
  }

  // Play a local audio file
  async playLocalSong(index) {
    if (index < 0 || index >= this.songs.length) return false;
    await this.initAudioContext();
    this.stopPlayback();

    this.currentIndex = index;
    const song = this.songs[index];
    this.activeTrack = song;
    this.activeStream = null;
    this.sourceType = 'local';

    try {
      let arrayBuffer = null;

      // Option A: Loaded from IndexedDB Blob
      if (song.blob) {
        arrayBuffer = await song.blob.arrayBuffer();
      }
      // Option B: MediaStore Content URI via Native Stream / Proxy
      else if (song.contentUri) {
        const proxyUrl = 'https://pioneer.local/media?uri=' + encodeURIComponent(song.contentUri);
        try {
          const resp = await fetch(proxyUrl);
          if (resp.ok) {
            arrayBuffer = await resp.arrayBuffer();
          }
        } catch(netErr) {}

        // Fallback: If proxy fetch fails, try Native Bridge base64 reader
        if (!arrayBuffer && window.PioneerBridge && typeof window.PioneerBridge.readAudioBase64 === 'function') {
          const b64 = window.PioneerBridge.readAudioBase64(song.contentUri);
          if (b64 && b64.length > 0) {
            const binStr = atob(b64);
            const len = binStr.length;
            const bytes = new Uint8Array(len);
            for (let i = 0; i < len; i++) bytes[i] = binStr.charCodeAt(i);
            arrayBuffer = bytes.buffer;
          }
        }
      }

      if (!arrayBuffer) {
        throw new Error('Unable to read audio data for ' + song.title);
      }

      this.currentBuffer = await this.audioCtx.decodeAudioData(arrayBuffer);
      this.duration = this.currentBuffer.duration;

      this.sourceNode = this.audioCtx.createBufferSource();
      this.sourceNode.buffer = this.currentBuffer;
      this.sourceNode.connect(this.preampNode);

      this.sourceNode.onended = () => {
        if (this.isPlaying && !this.isPaused) {
          this.playNext();
        }
      };

      this.startTime = this.audioCtx.currentTime;
      this.pauseOffset = 0;
      this.sourceNode.start(0);
      this.isPlaying = true;
      this.isPaused = false;
      return true;
    } catch(err) {
      console.error('Failed to play local song:', err);
      this.stopPlayback();
      throw err;
    }
  }

  // Play a network audio stream (HTTP/HTTPS URL) routed directly into the DSP engine
  async playNetworkStream(url, title = 'Network Stream', artist = 'Live Audio Source') {
    if (!url || !url.trim()) return false;
    await this.initAudioContext();
    this.stopPlayback();

    this.sourceType = 'network';
    this.activeStream = { url: url.trim(), title: title.trim(), artist: artist.trim() };
    this.activeTrack = {
      title: title.trim(),
      artist: artist.trim(),
      album: 'Network Audio Stream',
      duration: 0,
      isNetwork: true
    };

    try {
      if (!this.audioElement) {
        this.audioElement = new Audio();
        this.audioElement.crossOrigin = 'anonymous';
        this.mediaElementSource = this.audioCtx.createMediaElementSource(this.audioElement);
        this.mediaElementSource.connect(this.preampNode);
      }

      this.audioElement.src = url.trim();
      this.audioElement.onerror = (e) => {
        console.error('Network stream playback error:', e);
        this.isPlaying = false;
      };

      await this.audioElement.play();
      this.isPlaying = true;
      this.isPaused = false;
      return true;
    } catch(err) {
      console.error('Failed to play network stream:', err);
      this.stopPlayback();
      throw err;
    }
  }

  // Playback Control
  togglePlay() {
    if (this.sourceType === 'network' && this.audioElement) {
      if (this.audioElement.paused) {
        this.audioElement.play();
        this.isPlaying = true;
        this.isPaused = false;
      } else {
        this.audioElement.pause();
        this.isPlaying = false;
        this.isPaused = true;
      }
      return this.isPlaying;
    }

    if (this.isPlaying) {
      this.pause();
      return false;
    } else {
      this.resume();
      return true;
    }
  }

  pause() {
    if (this.sourceType === 'network' && this.audioElement) {
      this.audioElement.pause();
      this.isPlaying = false;
      this.isPaused = true;
      return;
    }

    if (this.sourceNode && this.isPlaying && !this.isPaused) {
      this.pauseOffset = (this.audioCtx.currentTime - this.startTime) % (this.duration || 1);
      try {
        this.sourceNode.stop();
        this.sourceNode.disconnect();
      } catch(e) {}
      this.sourceNode = null;
      this.isPlaying = false;
      this.isPaused = true;
    }
  }

  resume() {
    if (this.sourceType === 'network' && this.audioElement) {
      this.audioElement.play();
      this.isPlaying = true;
      this.isPaused = false;
      return;
    }

    if (this.isPaused && this.currentBuffer && this.audioCtx) {
      this.sourceNode = this.audioCtx.createBufferSource();
      this.sourceNode.buffer = this.currentBuffer;
      this.sourceNode.connect(this.preampNode);

      this.sourceNode.onended = () => {
        if (this.isPlaying && !this.isPaused) {
          this.playNext();
        }
      };

      this.startTime = this.audioCtx.currentTime - this.pauseOffset;
      this.sourceNode.start(0, this.pauseOffset);
      this.isPlaying = true;
      this.isPaused = false;
    } else if (this.currentIndex >= 0) {
      this.playLocalSong(this.currentIndex);
    }
  }

  seek(ratio) {
    if (this.sourceType === 'network') return; // Live streams are unseekable
    if (!this.currentBuffer) return;

    const targetTime = Math.max(0, Math.min(this.duration, this.duration * ratio));
    this.pauseOffset = targetTime;

    if (this.isPlaying && this.sourceNode) {
      try {
        this.sourceNode.stop();
        this.sourceNode.disconnect();
      } catch(e) {}
      this.sourceNode = this.audioCtx.createBufferSource();
      this.sourceNode.buffer = this.currentBuffer;
      this.sourceNode.connect(this.preampNode);
      this.sourceNode.onended = () => {
        if (this.isPlaying && !this.isPaused) this.playNext();
      };
      this.startTime = this.audioCtx.currentTime - targetTime;
      this.sourceNode.start(0, targetTime);
    }
  }

  async playNext() {
    if (this.songs.length === 0) return;
    const nextIdx = (this.currentIndex + 1) % this.songs.length;
    await this.playLocalSong(nextIdx);
  }

  async playPrev() {
    if (this.songs.length === 0) return;
    const prevIdx = (this.currentIndex - 1 + this.songs.length) % this.songs.length;
    await this.playLocalSong(prevIdx);
  }

  getCurrentTime() {
    if (this.sourceType === 'network' && this.audioElement) {
      return this.audioElement.currentTime || 0;
    }
    if (!this.isPlaying || !this.audioCtx) return this.pauseOffset;
    if (this.isPaused) return this.pauseOffset;
    return (this.audioCtx.currentTime - this.startTime) % (this.duration || 1);
  }

  getCurrentDuration() {
    if (this.sourceType === 'network') return 0;
    return this.duration || (this.songs[this.currentIndex]?.duration || 0);
  }

  // File Management & IndexedDB Persistence
  async loadSavedSongs() {
    try {
      const saved = await this.db.getAllSongs();
      this.songs = saved || [];
      const streams = await this.db.getAllStreams();
      this.networkStreams = streams || [];
      return this.songs;
    } catch(e) {
      this.songs = [];
      this.networkStreams = [];
      return [];
    }
  }

  async importFiles(files) {
    if (!files || files.length === 0) return;
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const id = 'local_' + Date.now() + '_' + Math.floor(Math.random() * 1000);
      const nameParts = file.name.replace(/\.[^/.]+$/, '').split(' - ');
      const artist = nameParts.length > 1 ? nameParts[0].trim() : 'Local Artist';
      const title = nameParts.length > 1 ? nameParts.slice(1).join(' - ').trim() : nameParts[0].trim();
      const fileSize = (file.size / (1024 * 1024)).toFixed(1) + ' MB';

      const songObj = {
        id: id,
        title: title,
        artist: artist,
        album: 'Imported Music',
        duration: 0,
        fileSize: fileSize,
        blob: file,
        addedAt: Date.now()
      };

      this.songs.push(songObj);
      await this.db.saveSong(songObj);
    }
  }

  async importMediaStoreTracks(tracks) {
    if (!tracks || !Array.isArray(tracks)) return;
    for (const t of tracks) {
      // Deduplicate by contentUri or id
      const exists = this.songs.some(s => s.contentUri === t.contentUri || s.id === t.id);
      if (!exists) {
        const songObj = {
          id: t.id,
          title: t.title,
          artist: t.artist,
          album: t.album,
          duration: t.duration || 0,
          fileSize: (t.size / (1024 * 1024)).toFixed(1) + ' MB',
          contentUri: t.contentUri,
          albumId: t.albumId,
          addedAt: Date.now()
        };
        this.songs.push(songObj);
        await this.db.saveSong(songObj);
      }
    }
  }

  async removeSong(id) {
    const idx = this.songs.findIndex(s => s.id === id);
    if (idx !== -1) {
      if (idx === this.currentIndex) {
        this.stopPlayback();
        this.currentIndex = -1;
      } else if (idx < this.currentIndex) {
        this.currentIndex--;
      }
      this.songs.splice(idx, 1);
      await this.db.deleteSong(id);
    }
  }

  async saveNetworkStreamRecord(url, title, artist) {
    const id = 'stream_' + Date.now();
    const item = {
      id: id,
      url: url.trim(),
      title: (title || 'Network Stream').trim(),
      artist: (artist || 'Live Broadcast').trim(),
      addedAt: Date.now()
    };
    this.networkStreams.push(item);
    await this.db.saveStream(item);
    return item;
  }

  async removeNetworkStream(id) {
    const idx = this.networkStreams.findIndex(s => s.id === id);
    if (idx !== -1) {
      this.networkStreams.splice(idx, 1);
      await this.db.deleteStream(id);
    }
  }
}

window.dspEngine = new PioneerDSPEngine();
