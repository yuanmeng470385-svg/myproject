// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
// Web 平台音频录制 — JS eval + 与 voice_test.html 完全一致的编码
import 'dart:async';
import 'dart:js' as js;
import 'audio_recorder_base.dart';

class AudioRecorder extends AudioRecorderBase {
  var _isRecording = false;
  int _chunkCount = 0;

  @override
  Future<bool> hasPermission() async {
    try {
      final c = Completer<bool>();
      js.context['__permCb'] = js.allowInterop((bool ok) {
        c.complete(ok);
      });
      js.context.callMethod('eval', ['''
(async function() {
  try {
    var s = await navigator.mediaDevices.getUserMedia({audio: true});
    s.getTracks().forEach(function(t) { t.stop(); });
    window.__permCb(true);
  } catch(e) {
    window.__permCb(false);
  }
})()
''']);
      return c.future;
    } catch (e) {
      return true;
    }
  }

  @override
  Future<bool> requestPermission() => hasPermission();

  @override
  Future<void> startRecording(void Function(String base64) onData) async {
    _isRecording = true;
    _chunkCount = 0;

    // 注册回调
    js.context['__acb'] = js.allowInterop((String b64) {
      if (!_isRecording || b64.isEmpty) return;
      _chunkCount++;
      if (_chunkCount == 1) print('[AudioRecorder] Dart b64 first 80: $b64');
      if (_chunkCount <= 3) print('[AudioRecorder] Chunk #$_chunkCount len=${b64.length}');
      onData(b64);
    });

    // 注入 JS 录音脚本 — 与 voice_test.html 完全一致
    js.context.callMethod('eval', ['''
(async function() {
  try {
    var stream = await navigator.mediaDevices.getUserMedia({audio: {echoCancellation: true, noiseSuppression: true, autoGainControl: true}});
    console.log('[AudioRecorder] stream acquired, tracks:', stream.getAudioTracks().length);
    stream.getTracks().forEach(function(t) {
      t.enabled = true;
      console.log('[AudioRecorder] track:', t.label, 'muted:', t.muted, 'readyState:', t.readyState);
    });

    var ctx = new (window.AudioContext||window.webkitAudioContext)({sampleRate: 16000});
    console.log('[AudioRecorder] ctx.sampleRate:', ctx.sampleRate);
    await ctx.resume();
    console.log('[AudioRecorder] ctx.state:', ctx.state);

    var src = ctx.createMediaStreamSource(stream);
    var proc = ctx.createScriptProcessor(4096, 1, 1);
    var chunkCount = 0;

    proc.onaudioprocess = function(e) {
      try {
        var data = e.inputBuffer.getChannelData(0);

        // 与 voice_test.html 完全一致的编码
        var buf = new ArrayBuffer(data.length * 2);
        var view = new DataView(buf);
        for (var i = 0; i < data.length; i++) {
          var s = Math.round(data[i] * 32767);
          s = Math.max(-32768, Math.min(32767, s));
          view.setInt16(i * 2, s, true);
        }
        var bytes = new Uint8Array(buf);
        var binary = '';
        for (var i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
        var b64 = btoa(binary);

        chunkCount++;
        if (chunkCount === 1) {
          // 打印 audio 数据的前几个 Int16 值，验证不是全零
          var firstSamples = [];
          for (var i = 0; i < 20 && i < data.length; i++) {
            firstSamples.push(Math.round(data[i] * 32767));
          }
          console.log('[AudioRecorder] first 20 Int16 samples:', firstSamples.join(','));
          console.log('[AudioRecorder] b64 first 80:', b64.substring(0, 80));
        }
        if (chunkCount <= 3) console.log('[AudioRecorder] Chunk #'+chunkCount+' len='+b64.length);

        window.__acb(b64);
      } catch(e) { console.error('[AudioRecorder] error:', e); }
    };

    src.connect(proc);
    proc.connect(ctx.destination);

    window.__audioCtx = ctx;
    window.__audioSrc = src;
    window.__audioProc = proc;
    window.__audioStream = stream;
    console.log('[AudioRecorder] JS recording started');
  } catch(e) { console.error('[AudioRecorder] setup error:', ''+e); }
})()
''']);
  }

  @override
  Future<void> stopRecording() async {
    _isRecording = false;
    js.context.callMethod('eval', ['''
try {
  var p = window.__audioProc; if(p) { p.disconnect(); p.onaudioprocess = null; }
  var s = window.__audioSrc; if(s) s.disconnect();
  var c = window.__audioCtx; if(c) c.close();
  var t = window.__audioStream; if(t) t.getTracks().forEach(function(x){x.stop()});
} catch(e) {}
delete window.__audioCtx;
delete window.__audioSrc;
delete window.__audioProc;
delete window.__audioStream;
delete window.__acb;
''']);
  }

  @override
  void dispose() {
    stopRecording();
  }
}
