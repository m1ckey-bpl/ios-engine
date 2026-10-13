// Pioneer DSP - Hi-Fi Audio Processing Engine & Persistent Storage
class PioneerAudioDB {
  constructor() {
    this.dbName = 'PioneerDSP_DB';
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
}

class PioneerDSPEngine {
  constructor() {
    this.audioCtx = null;
    this.sourceNode = null;
    this.isPlaying = false;
    this.isPaused = false;
    this.pauseOffset = 0;
    this.startTime = 0;
    
    // DSP State & Levels
    this.preampGain = 0; // -12 to +12 dB
    this.superBassGain = 0; // 0 to 12 dB (Todoroki 63Hz)
    this.deepBassGain = 0; // 0 to 8 dB (Sub-Bass 31Hz)
    this.midGain = 0; // -10 to +10 dB (1.5kHz)
    this.trebleGain = 0; // -10 to +10 dB (10kHz)
    
    this.ambienceMode = 'hall'; // 'hall', 'room', 'studio'
    this.reverbMix = 0; // 0 to 100%
    this.balance = 0; // -1.0 to +1.0
    this.cabinPosition = 'all'; // 'all', 'fl', 'fr', 'fc'

    // 10-Band Graphic EQ Frequencies
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
    this.limiterNode = null; // Clipping Protection
    this.analyser = null;
    this.spectrumBuffer = null;

    // Impulse Responses Cache
    this.impulseCache = {};

    // Playlist & Songs
    this.defaultSongs = [
      { id: 'demo_1', title: 'Concert Hall Acoustic Master', artist: 'Pioneer Philharmonic', duration: 180, isDemo: true, demoType: 'hall' },
      { id: 'demo_2', title: 'Todoroki 808 Sub-Bass Groove', artist: 'Pioneer Bass Lab', duration: 165, isDemo: true, demoType: 'bass' },
      { id: 'demo_3', title: 'Tokyo Highway Synth Drive', artist: 'Cyber Sound Collective', duration: 210, isDemo: true, demoType: 'synth' },
      { id: 'demo_4', title: 'Midnight Lo-Fi Piano Lounge', artist: 'Acoustic Stage Project', duration: 195, isDemo: true, demoType: 'lofi' }
    ];
    this.songs = [...this.defaultSongs];
    this.currentIndex = 0;
    this.currentBuffer = null;
    this.isShuffle = false;
    this.isRepeat = true;

    this.db = new PioneerAudioDB();
    this.initAudioContext();
  }

  initAudioContext() {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    this.audioCtx = new AudioContextClass();

    // 1. Preamp Gain
    this.preampNode = this.audioCtx.createGain();
    this.preampNode.gain.value = 1.0;

    // 2. 10-Band EQ Filters
    this.eqFilters = this.eqFreqs.map(freq => {
      const filter = this.audioCtx.createBiquadFilter();
      filter.type = 'peaking';
      filter.frequency.value = freq;
      filter.Q.value = 1.4;
      filter.gain.value = 0;
      return filter;
    });

    // 3. Super Bass (Todoroki Low Shelf at 63Hz)
    this.superBassFilter = this.audioCtx.createBiquadFilter();
    this.superBassFilter.type = 'lowshelf';
    this.superBassFilter.frequency.value = 63;
    this.superBassFilter.gain.value = 0;

    // 4. Deep Bass (Sub-Bass Low Shelf at 31Hz)
    this.deepBassFilter = this.audioCtx.createBiquadFilter();
    this.deepBassFilter.type = 'lowshelf';
    this.deepBassFilter.frequency.value = 31;
    this.deepBassFilter.gain.value = 0;

    // 5. Tone Controls: Midrange (1.5kHz) and Treble (10kHz High Shelf)
    this.midFilter = this.audioCtx.createBiquadFilter();
    this.midFilter.type = 'peaking';
    this.midFilter.frequency.value = 1500;
    this.midFilter.Q.value = 1.0;
    this.midFilter.gain.value = 0;

    this.trebleFilter = this.audioCtx.createBiquadFilter();
    this.trebleFilter.type = 'highshelf';
    this.trebleFilter.frequency.value = 10000;
    this.trebleFilter.gain.value = 0;

    // 6. Ambience / Reverb Convolver Node
    this.convolverNode = this.audioCtx.createConvolver();
    this.buildImpulseResponses();
    this.convolverNode.buffer = this.impulseCache['hall'];

    this.dryGain = this.audioCtx.createGain();
    this.dryGain.gain.value = 1.0;

    this.wetGain = this.audioCtx.createGain();
    this.wetGain.gain.value = 0.0;

    // 7. Stereo Balance / Panner
    if (this.audioCtx.createStereoPanner) {
      this.pannerNode = this.audioCtx.createStereoPanner();
      this.pannerNode.pan.value = 0;
    } else {
      this.pannerNode = this.audioCtx.createGain();
    }

    // 8. Peak Limiter / Clipping Protection (DynamicsCompressor)
    // Prevents digital clipping distortion under heavy bass/gain boost
    this.limiterNode = this.audioCtx.createDynamicsCompressor();
    this.limiterNode.threshold.value = -3.0; // dB
    this.limiterNode.knee.value = 30; // dB
    this.limiterNode.ratio.value = 12; // 12:1 compression for hard limiting
    this.limiterNode.attack.value = 0.003; // 3ms fast peak catch
    this.limiterNode.release.value = 0.25; // 250ms smooth release

    // 9. Analyser Node for Spectrum Visualizer
    this.analyser = this.audioCtx.createAnalyser();
    this.analyser.fftSize = 64;
    this.analyser.smoothingTimeConstant = 0.82;
    this.spectrumBuffer = new Uint8Array(this.analyser.frequencyBinCount);

    // Audio Graph Pipeline:
    // Source -> Preamp -> EQ[0..9] -> DeepBass -> SuperBass -> Mid -> Treble -> (Dry/Wet Split) -> Panner -> Limiter -> Analyser -> Output
    this.preampNode.connect(this.eqFilters[0]);
    for (let i = 0; i < this.eqFilters.length - 1; i++) {
      this.eqFilters[i].connect(this.eqFilters[i + 1]);
    }
    this.eqFilters[this.eqFilters.length - 1].connect(this.deepBassFilter);
    this.deepBassFilter.connect(this.superBassFilter);
    this.superBassFilter.connect(this.midFilter);
    this.midFilter.connect(this.trebleFilter);

    // Dry / Wet Split
    this.trebleFilter.connect(this.dryGain);
    this.dryGain.connect(this.pannerNode);

    this.trebleFilter.connect(this.convolverNode);
    this.convolverNode.connect(this.wetGain);
    this.wetGain.connect(this.pannerNode);

    // Master Output with Limiter Protection
    this.pannerNode.connect(this.limiterNode);
    this.limiterNode.connect(this.analyser);
    this.analyser.connect(this.audioCtx.destination);

    // Initial demo synthesized audio
    this.currentBuffer = this.generateSynthBuffer('hall');
  }

  // Pre-generate 3 Ambience Impulse Responses (Hall, Room, Studio)
  buildImpulseResponses() {
    this.impulseCache['hall'] = this.createSyntheticImpulse(2.8, 2.0); // Concert Hall: long, expansive
    this.impulseCache['room'] = this.createSyntheticImpulse(1.4, 2.8); // Acoustic Room: warm, intimate
    this.impulseCache['studio'] = this.createSyntheticImpulse(0.6, 4.0); // Studio: dry, tight reflections
  }

  createSyntheticImpulse(duration, decay) {
    const rate = this.audioCtx.sampleRate;
    const length = Math.floor(rate * duration);
    const impulse = this.audioCtx.createBuffer(2, length, rate);
    const left = impulse.getChannelData(0);
    const right = impulse.getChannelData(1);

    for (let i = 0; i < length; i++) {
      const n = (length - i) / length;
      const env = Math.pow(n, decay);
      left[i] = (Math.random() * 2 - 1) * env;
      right[i] = (Math.random() * 2 - 1) * env;
    }
    return impulse;
  }

  // Synthesize Demonstration Audio Chords
  generateSynthBuffer(type = 'hall') {
    const rate = this.audioCtx.sampleRate;
    const duration = 6.0;
    const length = rate * duration;
    const buffer = this.audioCtx.createBuffer(2, length, rate);
    const left = buffer.getChannelData(0);
    const right = buffer.getChannelData(1);

    const chords = [130.81, 164.81, 196.00, 246.94, 293.66, 392.00];
    for (let i = 0; i < length; i++) {
      const t = i / rate;
      let sL = 0;
      let sR = 0;
      for (let c = 0; c < chords.length; c++) {
        const f = chords[c];
        const phase = c * 0.4;
        const toneL = Math.sin(2 * Math.PI * f * t) + 0.25 * Math.sin(4 * Math.PI * f * t);
        const toneR = Math.sin(2 * Math.PI * f * t + phase) + 0.25 * Math.sin(4 * Math.PI * f * t + phase);
        sL += toneL * 0.12;
        sR += toneR * 0.12;
      }
      const bassPulse = Math.sin(2 * Math.PI * 65.41 * t) * (0.6 + 0.4 * Math.sin(2 * Math.PI * 1.5 * t));
      sL += bassPulse * 0.22;
      sR += bassPulse * 0.22;

      left[i] = sL;
      right[i] = sR;
    }
    return buffer;
  }

  // Load Saved Songs from Persistent IndexedDB
  async loadSavedSongs() {
    try {
      const saved = await this.db.getAllSongs();
      if (saved && saved.length > 0) {
        const customTracks = saved.map(s => ({
          id: s.id,
          title: s.title,
          artist: s.artist || 'Local Track',
          duration: s.duration || 180,
          fileSize: s.fileSize || 'Audio',
          blob: s.blob,
          isDemo: false
        }));
        this.songs = [...this.defaultSongs, ...customTracks];
      }
    } catch (e) {
      console.warn('Failed to load songs from IndexedDB:', e);
    }
    return this.songs;
  }

  // DSP Real-Time Parameter Controls with Smooth Interpolation
  setPreamp(gainDB) {
    this.preampGain = gainDB;
    const linear = Math.pow(10, gainDB / 20);
    this.preampNode.gain.setTargetAtTime(linear, this.audioCtx.currentTime, 0.05);
  }

  setSuperBass(gainDB) {
    this.superBassGain = gainDB;
    this.superBassFilter.gain.setTargetAtTime(gainDB, this.audioCtx.currentTime, 0.05);
  }

  setDeepBass(gainDB) {
    this.deepBassGain = gainDB;
    this.deepBassFilter.gain.setTargetAtTime(gainDB, this.audioCtx.currentTime, 0.05);
  }

  setMid(gainDB) {
    this.midGain = gainDB;
    this.midFilter.gain.setTargetAtTime(gainDB, this.audioCtx.currentTime, 0.05);
  }

  setTreble(gainDB) {
    this.trebleGain = gainDB;
    this.trebleFilter.gain.setTargetAtTime(gainDB, this.audioCtx.currentTime, 0.05);
  }

  setEQBand(index, gainDB) {
    if (index >= 0 && index < this.eqFilters.length) {
      this.eqGains[index] = gainDB;
      this.eqFilters[index].gain.setTargetAtTime(gainDB, this.audioCtx.currentTime, 0.05);
    }
  }

  resetEQ() {
    for (let i = 0; i < this.eqFilters.length; i++) {
      this.setEQBand(i, 0);
    }
  }

  setAmbienceMode(mode) {
    if (this.impulseCache[mode]) {
      this.ambienceMode = mode;
      this.convolverNode.buffer = this.impulseCache[mode];
    }
  }

  setReverbMix(pct) {
    this.reverbMix = pct;
    const wet = pct / 100;
    const now = this.audioCtx.currentTime;
    this.wetGain.gain.setTargetAtTime(wet, now, 0.05);
    this.dryGain.gain.setTargetAtTime(1.0 - (wet * 0.35), now, 0.05);
  }

  setBalance(pan) {
    this.balance = pan;
    if (this.pannerNode.pan) {
      this.pannerNode.pan.setTargetAtTime(pan, this.audioCtx.currentTime, 0.05);
    }
  }

  setCabinPosition(pos) {
    this.cabinPosition = pos;
    let pan = 0;
    if (pos === 'fl') pan = -0.45;
    if (pos === 'fr') pan = 0.45;
    if (pos === 'fc') pan = 0;
    if (pos === 'all') pan = 0;
    this.setBalance(pan);
  }

  // 10 Real Factory Presets (All actually modify audio DSP nodes)
  applyPreset(presetKey) {
    switch(presetKey) {
      case 'flat':
        this.resetEQ();
        this.setSuperBass(0);
        this.setDeepBass(0);
        this.setMid(0);
        this.setTreble(0);
        this.setPreamp(0);
        this.setReverbMix(0);
        break;
      case 'bass': // Super Bass (Todoroki)
        this.resetEQ();
        this.setSuperBass(11);
        this.setDeepBass(5);
        this.setEQBand(0, 4);
        this.setEQBand(1, 8);
        this.setEQBand(8, 2);
        this.setReverbMix(10);
        break;
      case 'deep_bass':
        this.resetEQ();
        this.setDeepBass(8);
        this.setSuperBass(6);
        this.setEQBand(0, 7);
        this.setEQBand(1, 4);
        this.setReverbMix(5);
        break;
      case 'hall': // Concert Hall
        this.resetEQ();
        this.setAmbienceMode('hall');
        this.setReverbMix(65);
        this.setEQBand(0, 3);
        this.setEQBand(1, 4.5);
        this.setEQBand(8, 3.5);
        this.setEQBand(9, 4.0);
        break;
      case 'studio': // Studio Ambience
        this.resetEQ();
        this.setAmbienceMode('studio');
        this.setReverbMix(25);
        this.setEQBand(4, 1.5);
        this.setEQBand(5, 2.0);
        break;
      case 'vocal': // Vocal Clarity
        this.resetEQ();
        this.setSuperBass(0);
        this.setMid(4);
        this.setTreble(2);
        this.setEQBand(0, -3);
        this.setEQBand(1, -2);
        this.setEQBand(4, 3.5);
        this.setEQBand(5, 5.0);
        this.setEQBand(6, 4.0);
        this.setReverbMix(20);
        break;
      case 'acoustic': // Natural Acoustic
        this.resetEQ();
        this.setAmbienceMode('room');
        this.setReverbMix(35);
        this.setEQBand(2, 3);
        this.setEQBand(3, 2);
        this.setEQBand(7, 3);
        this.setEQBand(8, 4);
        break;
      case 'rock': // Punchy Rock
        this.resetEQ();
        this.setSuperBass(6);
        this.setEQBand(0, 4);
        this.setEQBand(1, 6);
        this.setEQBand(5, -2);
        this.setEQBand(7, 4);
        this.setEQBand(8, 5);
        this.setReverbMix(15);
        break;
      case 'classical': // Orchestral Hall
        this.resetEQ();
        this.setAmbienceMode('hall');
        this.setReverbMix(55);
        this.setEQBand(1, 3);
        this.setEQBand(2, 2);
        this.setEQBand(7, 3);
        this.setEQBand(9, 5);
        break;
      case 'cinema': // Spatial Surround
        this.resetEQ();
        this.setDeepBass(7);
        this.setSuperBass(7);
        this.setAmbienceMode('hall');
        this.setReverbMix(45);
        this.setEQBand(0, 5);
        this.setEQBand(8, 4);
        this.setEQBand(9, 6);
        break;
    }
  }

  // User Custom Presets Management (localStorage)
  saveCustomPreset(name) {
    if (!name || !name.trim()) return false;
    const presets = this.getCustomPresets();
    presets[name.trim()] = {
      eqGains: [...this.eqGains],
      preampGain: this.preampGain,
      superBassGain: this.superBassGain,
      deepBassGain: this.deepBassGain,
      midGain: this.midGain,
      trebleGain: this.trebleGain,
      ambienceMode: this.ambienceMode,
      reverbMix: this.reverbMix,
      balance: this.balance
    };
    localStorage.setItem('pioneer_custom_presets', JSON.stringify(presets));
    return true;
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

    if (p.eqGains) {
      p.eqGains.forEach((g, idx) => this.setEQBand(idx, g));
    }
    if (p.preampGain !== undefined) this.setPreamp(p.preampGain);
    if (p.superBassGain !== undefined) this.setSuperBass(p.superBassGain);
    if (p.deepBassGain !== undefined) this.setDeepBass(p.deepBassGain);
    if (p.midGain !== undefined) this.setMid(p.midGain);
    if (p.trebleGain !== undefined) this.setTreble(p.trebleGain);
    if (p.ambienceMode) this.setAmbienceMode(p.ambienceMode);
    if (p.reverbMix !== undefined) this.setReverbMix(p.reverbMix);
    if (p.balance !== undefined) this.setBalance(p.balance);
    return true;
  }

  deleteCustomPreset(name) {
    const presets = this.getCustomPresets();
    delete presets[name];
    localStorage.setItem('pioneer_custom_presets', JSON.stringify(presets));
  }

  // Playback Control
  async play() {
    if (this.audioCtx.state === 'suspended') {
      await this.audioCtx.resume();
    }

    const curSong = this.songs[this.currentIndex];
    if (curSong && !this.currentBuffer) {
      await this.prepareSongBuffer(this.currentIndex);
    }

    const dur = this.getCurrentDuration();
    if (this.isPaused) {
      this.startSourceAt(this.pauseOffset % dur);
    } else {
      this.startSourceAt(0);
    }
    this.isPlaying = true;
    this.isPaused = false;
  }

  pause() {
    if (this.sourceNode) {
      try { this.sourceNode.stop(); } catch(e) {}
      this.sourceNode.disconnect();
      this.sourceNode = null;
    }
    this.pauseOffset = this.getCurrentTime();
    this.isPlaying = false;
    this.isPaused = true;
  }

  togglePlay() {
    if (this.isPlaying) {
      this.pause();
    } else {
      this.play();
    }
    return this.isPlaying;
  }

  getCurrentDuration() {
    const curSong = this.songs[this.currentIndex];
    if (curSong && curSong.duration) return curSong.duration;
    if (this.currentBuffer && this.currentBuffer.duration) return this.currentBuffer.duration;
    return 180;
  }

  getCurrentTime() {
    if (!this.isPlaying) {
      return this.pauseOffset;
    }
    const dur = this.getCurrentDuration();
    if (dur <= 0) return 0;
    const elapsed = this.audioCtx.currentTime - this.startTime;
    return this.isRepeat ? (elapsed % dur) : Math.min(elapsed, dur);
  }

  startSourceAt(offset) {
    if (this.sourceNode) {
      try { this.sourceNode.stop(); } catch(e) {}
      this.sourceNode.disconnect();
    }

    if (!this.currentBuffer) return;

    this.sourceNode = this.audioCtx.createBufferSource();
    this.sourceNode.buffer = this.currentBuffer;
    this.sourceNode.loop = this.isRepeat;
    this.sourceNode.connect(this.preampNode);

    this.startTime = this.audioCtx.currentTime - offset;
    this.sourceNode.start(0, offset);

    this.sourceNode.onended = () => {
      if (this.isPlaying && !this.isRepeat) {
        this.playNext();
      }
    };
  }

  seek(progressFraction) {
    const dur = this.getCurrentDuration();
    const target = Math.max(0, Math.min(dur * progressFraction, dur - 0.2));
    this.pauseOffset = target;
    if (this.isPlaying) {
      this.startSourceAt(target);
    }
  }

  async prepareSongBuffer(index) {
    const song = this.songs[index];
    if (!song) return;

    if (song.audioBuffer) {
      this.currentBuffer = song.audioBuffer;
      return;
    }

    if (song.blob) {
      try {
        const arrBuf = await song.blob.arrayBuffer();
        const decoded = await this.audioCtx.decodeAudioData(arrBuf);
        song.audioBuffer = decoded;
        this.currentBuffer = decoded;
        return;
      } catch (e) {
        console.error('Error decoding audio data from blob:', e);
      }
    }

    this.currentBuffer = this.generateSynthBuffer(song.demoType || 'hall');
  }

  async selectSong(index) {
    if (index >= 0 && index < this.songs.length) {
      this.currentIndex = index;
      await this.prepareSongBuffer(index);
      this.pauseOffset = 0;
      if (this.isPlaying) {
        this.startSourceAt(0);
      }
    }
  }

  async playNext() {
    if (this.isShuffle) {
      this.currentIndex = Math.floor(Math.random() * this.songs.length);
    } else {
      this.currentIndex = (this.currentIndex + 1) % this.songs.length;
    }
    await this.selectSong(this.currentIndex);
  }

  async playPrev() {
    this.currentIndex = (this.currentIndex - 1 + this.songs.length) % this.songs.length;
    await this.selectSong(this.currentIndex);
  }

  // Import Multiple Audio Files with Persistent IndexedDB Storage
  async importFiles(fileList) {
    const newItems = [];
    for (let file of fileList) {
      try {
        const arrayBuf = await file.arrayBuffer();
        const decoded = await this.audioCtx.decodeAudioData(arrayBuf.slice(0));

        const songRecord = {
          id: 'user_' + Date.now() + '_' + Math.random().toString(36).substr(2, 6),
          title: file.name.replace(/\.[^/.]+$/, ''),
          artist: 'Local Library',
          duration: decoded.duration,
          fileSize: (file.size / (1024 * 1024)).toFixed(1) + ' MB',
          blob: file,
          isDemo: false
        };

        await this.db.saveSong(songRecord);
        songRecord.audioBuffer = decoded;
        this.songs.push(songRecord);
        newItems.push(songRecord);
      } catch (err) {
        console.error('Error processing audio file:', file.name, err);
      }
    }
    return newItems;
  }

  async removeSong(id) {
    const idx = this.songs.findIndex(s => s.id === id);
    if (idx !== -1) {
      const isCurrent = this.currentIndex === idx;
      if (isCurrent && this.isPlaying) {
        this.pause();
      }
      this.songs.splice(idx, 1);
      await this.db.deleteSong(id);
      if (this.currentIndex >= this.songs.length) {
        this.currentIndex = Math.max(0, this.songs.length - 1);
      }
      if (isCurrent && this.songs.length > 0) {
        await this.prepareSongBuffer(this.currentIndex);
      }
    }
  }
}

window.dspEngine = new PioneerDSPEngine();
