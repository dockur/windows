(function () {
  var EMPTY = new Uint8Array(0);
  function attach() {
    var cb = document.getElementById('noVNC_setting_audio');
    if (!cb) return setTimeout(attach, 300);
    var ctx = null, ws = null, nextTime = 0, leftover = EMPTY;
    function stop() {
      try { if (ws) ws.close(); } catch (e) {}
      try { if (ctx) ctx.close(); } catch (e) {}
      ws = null; ctx = null; leftover = EMPTY;
    }
    function start() {
      stop();
      ctx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 48000 });
      nextTime = ctx.currentTime + 0.15;
      ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/audio');
      ws.binaryType = 'arraybuffer';
      ws.onmessage = function (e) {
        if (!ctx) return;
        var bytes;
        if (leftover.length) {
          bytes = new Uint8Array(leftover.length + e.data.byteLength);
          bytes.set(leftover); bytes.set(new Uint8Array(e.data), leftover.length);
        } else {
          bytes = new Uint8Array(e.data);
        }
        var usable = bytes.length & ~3;
        leftover = usable < bytes.length ? bytes.slice(usable) : EMPTY;
        if (!usable) return;
        var frames = usable >> 2;
        var i16 = new Int16Array(bytes.buffer, bytes.byteOffset, usable >> 1);
        var buf = ctx.createBuffer(2, frames, 48000);
        var l = buf.getChannelData(0), r = buf.getChannelData(1);
        for (var i = 0, j = 0; i < frames; i++) { l[i] = i16[j++] / 32768; r[i] = i16[j++] / 32768; }
        var src = ctx.createBufferSource(); src.buffer = buf; src.connect(ctx.destination);
        var t = nextTime > ctx.currentTime ? nextTime : ctx.currentTime + 0.02;
        src.start(t); nextTime = t + buf.duration;
      };
    }
    cb.addEventListener('change', function () { cb.checked ? start() : stop(); });
  }
  attach();
})();
