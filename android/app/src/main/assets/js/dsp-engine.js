// Pioneer DSP Audio Core Engine (Web Audio API)
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
    
    // EQ Bands: 31, 63, 125, 250, 500, 1k, 2k, 4k, 8k, 16k
    this.eqFreqs = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
    this.eqFilters = [];
    this.eqGains = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    
    // Nodes
    this.superBassFilter = null;
    this.convolverNode = null;
    this.wetGain = null;
    this.dryGain = null;
    this.pannerNode = null;
    this.analyser = null;
    
    // Playlists & Songs
    this.songs = [
      { id: '1', title: 'Concert Hall Acoustic Master', artist: 'Pioneer Philharmonic Studio', duration: 180, isDemo: true, demoType: 'hall' },
      { id: '2', title: 'Todoroki 808 Sub-Bass Groove', artist: 'Pioneer Bass Engineering', duration: 165, isDemo: true, demoType: 'bass' },
      { id: '3', title: 'Tokyo Highway Synth Drive', artist: 'Cyber Audio Collective', duration: 210, isDemo: true, demoType: 'synth' },
      { id: '4', title: 'Midnight Lo-Fi Piano Lounge', artist: 'Acoustic Stage Project', duration: 195, isDemo: true, demoType: 'lofi' }
    ];
    this.currentIndex = 0;
    this.currentBuffer = null;
    this.isShuffle = false;
    this.isRepeat = true;
    
    this.initAudioContext();
  }

  initAudioContext() {
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    this.audioCtx = new AudioContext();
    
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
    this.convolverNode.buffer = this.buildHallImpulseResponse(2.6, 2.2);

    this.dryGain = this.audioCtx.createGain();
    this.dryGain.gain.value = 1.0;

    this.wetGain = this.audioCtx.createGain();
    this.wetGain.gain.value = 0.0;

    // 4. Stereo Panner (Time Alignment)
    if (this.audioCtx.createStereoPanner) {
      this.pannerNode = this.audioCtx.createStereoPanner();
      this.pannerNode.pan.value = 0;
    } else {
      this.pannerNode = this.audioCtx.createGain(); // Fallback
    }

    // 5. Spectrum Analyser
    this.analyser = this.audioCtx.createAnalyser();
    this.analyser.fftSize = 64;
    this.analyser.smoothingTimeConstant = 0.8;

    // Connect chain:
    // EQ[0] -> EQ[1] ... -> SuperBass -> Split (DryGain, Convolver->WetGain) -> Panner -> Analyser -> Destination
    for (let i = 0; i < this.eqFilters.length - 1; i++) {
      this.eqFilters[i].connect(this.eqFilters[i + 1]);
    }
    this.eqFilters[this.eqFilters.length - 1].connect(this.superBassFilter);

    // Dry path
    this.superBassFilter.connect(this.dryGain);
    this.dryGain.connect(this.pannerNode);

    // Wet path (Concert Hall)
    this.superBassFilter.connect(this.convolverNode);
    this.convolverNode.connect(this.wetGain);
    this.wetGain.connect(this.pannerNode);

    // Output path
    this.pannerNode.connect(this.analyser);
    this.analyser.connect(this.audioCtx.destination);

    // Generate Initial Demo Buffer
    this.currentBuffer = this.generateSynthBuffer('hall');
  }

  // Generate 3D Spatial Concert Hall Impulse Response
  buildHallImpulseResponse(duration = 2.6, decay = 2.2) {
    const rate = this.audioCtx.sampleRate;
    const length = rate * duration;
    const impulse = this.audioCtx.createBuffer(2, length, rate);
    const left = impulse.getChannelData(0);
    const right = impulse.getChannelData(1);
    
    for (let i = 0; i < length; i++) {
      const n = (length - i) / length;
      // Exponential decay simulating architectural reflection
      const env = Math.pow(n, decay);
      left[i] = (Math.random() * 2 - 1) * env;
      right[i] = (Math.random() * 2 - 1) * env;
    }
    return impulse;
  }

  // Synthesize Hi-Fi Demonstration Music
  generateSynthBuffer(type = 'hall') {
    const rate = this.audioCtx.sampleRate;
    const duration = 4.0;
    const length = rate * duration;
    const buffer = this.audioCtx.createBuffer(2, length, rate);
    const left = buffer.getChannelData(0);
    const right = buffer.getChannelData(1);

    const chords = [130.81, 196.00, 246.94, 293.66, 329.63, 392.00]; // Rich C maj9
    for (let i = 0; i < length; i++) {
      const t = i / rate;
      let sL = 0;
      let sR = 0;
      
      for (let c = 0; c < chords.length; c++) {
        const f = chords[c];
        const phase = c * 0.35;
        const toneL = Math.sin(2 * Math.PI * f * t) + 0.3 * Math.sin(4 * Math.PI * f * t);
        const toneR = Math.sin(2 * Math.PI * f * t + phase) + 0.3 * Math.sin(4 * Math.PI * f * t + phase);
        sL += toneL * 0.12;
        sR += toneR * 0.12;
      }
      
      const bassPulse = Math.sin(2 * Math.PI * 65.41 * t) * (0.5 + 0.5 * Math.sin(2 * Math.PI * 1.2 * t));
      sL += bassPulse * 0.25;
      sR += bassPulse * 0.25;
      
      left[i] = sL;
      right[i] = sR;
    }
    return buffer;
  }

  // Toggle Concert Hall Acoustics in Real Time
  toggleConcertHall() {
    this.isConcertHall = !this.isConcertHall;
    if (this.isConcertHall) {
      this.reverbMix = 65;
      this.setReverbMix(65);
      // Lift sub-bass & air frequencies for wide concert staging
      this.setEQBand(1, 4.5);
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
    this.wetGain.gain.setTargetAtTime(wet, this.audioCtx.currentTime, 0.05);
    this.dryGain.gain.setTargetAtTime(1.0 - (wet * 0.3), this.audioCtx.currentTime, 0.05);
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

  // Zero-Glitch Play / Pause Execution
  togglePlay() {
    if (this.isPlaying) {
      this.pause();
    } else {
      this.play();
    }
    return this.isPlaying;
  }

  play() {
    if (this.audioCtx.state === 'suspended') {
      this.audioCtx.resume();
    }

    if (this.isPaused) {
      // Resume from paused offset
      this.startSourceAt(this.pauseOffset);
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
    this.pauseOffset = (this.audioCtx.currentTime - this.startTime) % (this.currentBuffer ? this.currentBuffer.duration : 180);
    this.isPlaying = false;
    this.isPaused = true;
  }

  startSourceAt(offset) {
    if (this.sourceNode) {
      try { this.sourceNode.stop(); } catch(e) {}
      this.sourceNode.disconnect();
    }

    this.sourceNode = this.audioCtx.createBufferSource();
    this.sourceNode.buffer = this.currentBuffer;
    this.sourceNode.loop = true;
    this.sourceNode.connect(this.eqFilters[0]);

    this.startTime = this.audioCtx.currentTime - offset;
    this.sourceNode.start(0, offset);
  }

  seek(progressPct) {
    const dur = this.currentBuffer ? this.currentBuffer.duration : 180;
    const targetTime = dur * progressPct;
    this.pauseOffset = targetTime;
    if (this.isPlaying) {
      this.startSourceAt(targetTime);
    }
  }

  // Playlist Management
  selectSong(index) {
    if (index >= 0 && index < this.songs.length) {
      this.currentIndex = index;
      const song = this.songs[index];
      
      if (song.audioBuffer) {
        this.currentBuffer = song.audioBuffer;
      } else {
        this.currentBuffer = this.generateSynthBuffer(song.demoType || 'hall');
      }

      this.pauseOffset = 0;
      if (this.isPlaying) {
        this.startSourceAt(0);
      }
    }
  }

  playNext() {
    if (this.isShuffle) {
      this.currentIndex = Math.floor(Math.random() * this.songs.length);
    } else {
      this.currentIndex = (this.currentIndex + 1) % this.songs.length;
    }
    this.selectSong(this.currentIndex);
  }

  playPrev() {
    this.currentIndex = (this.currentIndex - 1 + this.songs.length) % this.songs.length;
    this.selectSong(this.currentIndex);
  }

  // Decode Multi-Song Imported Files
  async importFiles(fileList) {
    for (let file of fileList) {
      try {
        const arrayBuf = await file.arrayBuffer();
        const decoded = await this.audioCtx.decodeAudioData(arrayBuf);
        const newSong = {
          id: Date.now() + Math.random().toString(),
          title: file.name.replace(/\.[^/.]+$/, ''),
          artist: 'Imported Track',
          duration: decoded.duration,
          fileSize: (file.size / (1024 * 1024)).toFixed(1) + ' MB',
          audioBuffer: decoded,
          isDemo: false
        };
        this.songs.push(newSong);
      } catch (err) {
        console.error('Error decoding audio:', file.name, err);
      }
    }
  }
}

window.dspEngine = new PioneerDSPEngine();
