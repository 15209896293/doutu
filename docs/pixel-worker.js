/*!
 * pixel-worker.js — 拼豆图纸生成 Web Worker
 * 通过 importScripts 复用 pixel-engine.js，后台执行转换，不阻塞 UI。
 */
'use strict';

importScripts('pixel-engine.js');

self.onmessage = function (e) {
  var input = e.data;
  try {
    var result = self.PixelEngine.convert(input);
    self.postMessage({ ok: true, result: result });
  } catch (err) {
    self.postMessage({ ok: false, error: String(err && err.stack || err) });
  }
};
