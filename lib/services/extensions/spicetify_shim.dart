// Spicetify compatibility layer injected into every extension WebView.
// Source of truth for this string is the plain JS version kept alongside the tests.
const String spicetifyShimSource = r'''
(function () {
  var I = window.__INIT || {};
  var pending = {}, L = {}, actions = {}, shortcuts = [], aid = 0;
  var S = Object.assign({ playing: false, progress: 0, duration: 0, volume: 50, shuffle: false, repeat: 'off', item: null }, I.state, { ts: Date.now() });
  var store = I.ls || {};

  function bridge() {
    return new Promise(function (res) {
      (function wait() {
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) res(window.flutter_inappwebview);
        else setTimeout(wait, 25);
      })();
    });
  }
  function call(m) {
    var a = Array.prototype.slice.call(arguments, 1);
    return bridge().then(function (b) { return b.callHandler.apply(b, ['sp', m].concat(a)); }).then(function (r) {
      if (r && r.__err) throw new Error(r.__err);
      return r && r.hasOwnProperty('v') ? r.v : r;
    });
  }
  function emit(t, d) {
    (L[t] || []).slice().forEach(function (f) {
      try { f({ data: d }); } catch (e) { call('log', 'error', String(e)); }
    });
  }
  function meta(it) {
    if (!it) return null;
    var al = it.album || {};
    return {
      uri: it.uri, name: it.name, artists: it.artists, album: al,
      duration: { milliseconds: it.duration_ms },
      metadata: {
        title: it.name, artist_name: (it.artists || []).map(function (a) { return a.name; }).join(', '),
        album_title: al.name || '', image_url: ((al.images || [])[0] || {}).url || '', duration: String(it.duration_ms)
      }
    };
  }
  function prog() { return S.playing ? Math.min(S.duration, S.progress + Date.now() - S.ts) : S.progress; }
  function reg(kind, label, cb) { var id = ++aid; actions[id] = cb; call('action', id, kind, label); return id; }

  window.__spEmit = function (ev, state) {
    S = Object.assign(state, { ts: Date.now() });
    if (ev === 'songchange' || ev === 'onplaypause') emit(ev, Spicetify.Player.data);
  };
  window.__spAction = function (id) {
    var a = actions[id];
    if (a) { try { a(); } catch (e) { call('log', 'error', String(e)); } }
  };
  window.__spKey = function (k) {
    shortcuts.forEach(function (s) {
      var c = s.k;
      if (String(c.key).toLowerCase() === String(k.key).toLowerCase() && !!c.ctrl === !!k.ctrl && !!c.shift === !!k.shift && !!c.alt === !!k.alt) s.cb();
    });
  };
  setInterval(function () { if (S.playing) emit('onprogress', prog()); }, 1000);

  var Player = {
    addEventListener: function (t, f) { (L[t] = L[t] || []).push(f); },
    removeEventListener: function (t, f) { L[t] = (L[t] || []).filter(function (x) { return x !== f; }); },
    getProgress: prog,
    getProgressPercent: function () { return S.duration ? prog() / S.duration : 0; },
    getDuration: function () { return S.duration; },
    isPlaying: function () { return S.playing; },
    getVolume: function () { return S.volume / 100; },
    getShuffle: function () { return S.shuffle; },
    getRepeat: function () { return ({ off: 0, context: 1, track: 2 })[S.repeat] || 0; },
    getMute: function () { return false; },
    play: function () { return call('player', 'play'); },
    pause: function () { return call('player', 'pause'); },
    togglePlay: function () { return call('player', S.playing ? 'pause' : 'play'); },
    next: function () { return call('player', 'next'); },
    back: function () { return call('player', 'prev'); },
    seek: function (p) { return call('player', 'seek', p < 1 ? Math.round(p * S.duration) : p); },
    setVolume: function (v) { return call('player', 'volume', Math.round(v * 100)); },
    toggleShuffle: function () { return call('player', 'shuffle'); },
    toggleRepeat: function () { return call('player', 'repeat'); }
  };
  Object.defineProperty(Player, 'data', {
    get: function () {
      return S.item ? { item: S.item, track: meta(S.item), is_paused: !S.playing, position: prog(), duration: S.duration } : null;
    }
  });

  function fromString(s) { var p = String(s).split(':'); return { uri: s, type: p[1], id: p[2], toURI: function () { return s; } }; }
  fromString.fromString = fromString;
  ['Track', 'Album', 'Artist', 'Playlist'].forEach(function (n) {
    fromString['is' + n] = function (s) { return String(s).split(':')[1] === n.toLowerCase(); };
  });
  function unsupported(what) { return function () { return Promise.reject(new Error(what + ' is not available in Spotube')); }; }

  function Button(label, icon, onClick) { this.label = label; var self = this; reg('topbar', label, function () { onClick(self); }); }
  function MenuItem(name, isEnabled, onClick) { this.name = name; var self = this; reg('menu', name, function () { onClick(self); }); }
  MenuItem.prototype.setState = function () {}; MenuItem.prototype.setName = function () {};
  MenuItem.prototype.register = function () {}; MenuItem.prototype.deregister = function () {};
  function CtxItem(name, onClick) { reg('menu', name, function () { onClick([S.item && S.item.uri].filter(Boolean)); }); }
  CtxItem.prototype.register = function () {}; CtxItem.prototype.deregister = function () {};

  var Spicetify = {
    version: 'spotube-0.1',
    Player: Player,
    URI: fromString,
    showNotification: function (t, isErr) { return call('notify', String(t), !!isErr); },
    addToQueue: unsupported('addToQueue'),
    CosmosAsync: { get: unsupported('Spotify API'), post: unsupported('Spotify API'), put: unsupported('Spotify API'), del: unsupported('Spotify API'), delete: unsupported('Spotify API'), resolve: unsupported('Spotify API') },
    LocalStorage: {
      get: function (k) { return Object.prototype.hasOwnProperty.call(store, k) ? store[k] : null; },
      set: function (k, v) { store[k] = String(v); call('ls', 'set', k, String(v)); },
      remove: function (k) { delete store[k]; call('ls', 'remove', k); },
      clear: function () { store = {}; call('ls', 'clear'); }
    },
    Keyboard: {
      registerShortcut: function (k, cb) { if (typeof k === 'string') k = { key: k }; if (Array.isArray(k)) k = { key: k[k.length - 1] }; shortcuts.push({ k: k, cb: cb }); },
      registerIsolatedShortcut: function (k, cb) { this.registerShortcut(k, cb); },
      KEYS: { SPACE: ' ', ARROW_LEFT: 'ArrowLeft', ARROW_RIGHT: 'ArrowRight', ARROW_UP: 'ArrowUp', ARROW_DOWN: 'ArrowDown' }
    },
    Topbar: { Button: Button },
    Menu: { Item: MenuItem },
    ContextMenu: { Item: CtxItem },
    Platform: { version: 'spotube', History: { location: { pathname: '/' }, listen: function () { return function () {}; }, push: function () {} } },
    Config: { version: 'spotube' },
    Locale: { get: function (k) { return k; } },
    SVGIcons: {},
    test: function () { return true; }
  };
  window.Spicetify = Spicetify;
  window.addEventListener('error', function (e) { call('log', 'error', e.message); });
  window.addEventListener('unhandledrejection', function (e) { call('log', 'error', String(e.reason)); });
})();
''';
