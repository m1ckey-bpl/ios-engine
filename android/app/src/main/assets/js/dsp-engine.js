// Pioneer DSP Audio Core Engine with IndexedDB Storage & Precision Timer
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
    
    // DSP State
    this.isConcertHall = false;
    this.superBassGain = 0; // 0 to 12 dB
    this.reverbMix = 0; // 0 to 100%
    this.currentPosition = 'all'; // all, fl, fr, fc
    
    // 10-Band EQ: 31, 63, 125, 250, 500, 1k, 2k, 4k, 8k, 16k
    this.eqFreqs = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
    this.eqFilters = [];
    this.eqGains = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    
    // Audio Nodes
    this.superBassFilter = null;
    this.convolverNode = null;
    this.wetGain = null;
    this.dryGain = null;
    this.pannerNode = null;
    this.analyser = null;
    this.spectrumBuffer = null;
    
    // Playlists & Songs
    this.defaultSongs = [
      { id: 'demo_1', title: 'Concert Hall Acoustic Master', artist: 'Pioneer Philharmonic', duration: 180, isDemo: true, demoType: 'hall' },
      { id: 'demo_2', title: 'Todoroki 808 Sub-Bass Groove', artist: 'Pioneer Sound Engineering', duration: 165, isDemo: true, demoType: 'bass' },
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
    
    // 1. Setup 10-Band EQ Filters
    this.eqFilters = this.eqFreqs.map(freq => {
      const filter = this.audioCtx.createBiquadFilter();
      filter.type = 'peaking';
      filter.frequency.value = freq;
      filter.Q.value = 1.4;
      filter.gain.value = 0;
      return filter;
    });

    // 2. Setup Super Bass Filter (Low Shelf at 63Hz)
    this.superBassFilter = this.audioCtx.createBiquadFilter();
    this.superBassFilter.type = 'lowshelf';
    this.superBassFilter.frequency.value = 63;
    this.superBassFilter.gain.value = 0;

    // 3. Setup Concert Hall Convolver Reverb
    this.convolverNode = this.audioCtx.createConvolver();
    this.convolverNode.buffer = this.buildHallImpulseResponse(2.5, 2.0);

    this.dryGain = this.audioCtx.createGain();
    this.dryGain.gain.value = 1.0;

    this.wetGain = this.audioCtx.createGain();
    this.wetGain.gain.value = 0.0;

    // 4. Stereo Panner
    if (this.audioCtx.createStereoPanner) {
      this.pannerNode = this.audioCtx.createStereoPanner();
      this.pannerNode.pan.value = 0;
    } else {
      this.pannerNode = this.audioCtx.createGain();
    }

    // 5. Analyser
    this.analyser = this.audioCtx.createAnalyser();
    this.analyser.fftSize = 64;
    this.analyser.smoothingTimeConstant = 0.82;
    this.spectrumBuffer = new Uint8Array(this.analyser.frequencyBinCount);

    // Audio Graph Routing:
    // Source -> EQ[0] -> ... -> EQ[9] -> SuperBass -> Dry/Wet -> Panner -> Analyser -> Destination
    for (let i = 0; i < this.eqFilters.length - 1; i++) {
      this.eqFilters[i].connect(this.eqFilters[i + 1]);
    }
    this.eqFilters[this.eqFilters.length - 1].connect(this.superBassFilter);

    this.superBassFilter.connect(this.dryGain);
    this.dryGain.connect(this.pannerNode);

    this.superBassFilter.connect(this.convolverNode);
    this.convolverNode.connect(this.wetGain);
    this.wetGain.connect(this.pannerNode);

    this.pannerNode.connect(this.analyser);
    this.analyser.connect(this.audioCtx.destination);

    // Default buffer
    this.currentBuffer = this.generateSynthBuffer('hall');
  }

  // Load Saved Songs from IndexedDB
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
      console.warn('Could not restore saved songs from IndexedDB:', e);
    }
    return this.songs;
  }

  // Generate 3D Spatial Concert Hall Impulse Response
  buildHallImpulseResponse(duration = 2.5, decay = 2.0) {
    const rate = this.audioCtx.sampleRate;
    const length = rate * duration;
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

  // Synthesize Demonstration Audio
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

  // Real-Time Controls
  toggleConcertHall() {
    this.isConcertHall = !this.isConcertHall;
    if (this.isConcertHall) {
      this.reverbMix = 65;
      this.setReverbMix(65);
      this.setEQBand(1, 4.0);
      this.setEQBand(8, 3.5);
      this.setEQBand(9, 4.0);
    } else {
      this.reverbMix = 0;
      this.setReverbMix(0);
      this.resetEQ();
    }
    return this.isConcertHall;
  }

  setReverbMix(pct) {
    this.reverbMix = pct;
    const wet = pct / 100;
    const now = this.audioCtx.currentTime;
    this.wetGain.gain.setTargetAtTime(wet, now, 0.05);
    this.dryGain.gain.setTargetAtTime(1.0 - (wet * 0.35), now, 0.05);
  }

  setSuperBass(gainDB) {
    this.superBassGain = gainDB;
    this.superBassFilter.gain.setTargetAtTime(gainDB, this.audioCtx.currentTime, 0.05);
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

  setPosition(pos) {
    this.currentPosition = pos;
    let pan = 0;
    if (pos === 'fl') pan = -0.45;
    if (pos === 'fr') pan = 0.45;
    if (this.pannerNode.pan) {
      this.pannerNode.pan.setTargetAtTime(pan, this.audioCtx.currentTime, 0.05);
    }
  }

  // Playback Engine
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
    this.sourceNode.connect(this.eqFilters[0]);

    this.startTime = this.audioCtx.currentTime - offset;
    this.sourceNode.start(0, offset);

    const dur = this.getCurrentDuration();
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
        console.error('Error decoding stored blob:', e);
      }
    }

    // Demo fallback
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

        // Save to IndexedDB
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

  // Delete User Track from Library & Storage
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
