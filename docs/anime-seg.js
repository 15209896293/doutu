/*
 * anime-seg.js — 本地动漫主体识别适配器
 *
 * 模型仅在首次点击生成时下载到浏览器缓存；用户图片从不离开设备。
 * 模型：SkyTNT/anime-seg, Apache-2.0，固定 revision，详见 THIRD_PARTY_NOTICES.md。
 */
(function (global) {
  'use strict';

  var MODEL_SIZE = 1024;
  var MODEL_URL = 'https://huggingface.co/skytnt/anime-seg/resolve/493cb60893f47441b26ec4fb9a306bce9e342982/isnetis.onnx';
  var WASM_PATH = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.20.1/dist/';
  var sessionPromise = null;

  function hasRuntime() {
    return !!(global.ort && global.ort.InferenceSession && global.ort.Tensor);
  }

  function getSession() {
    if (!hasRuntime()) return Promise.reject(new Error('ONNX Runtime 未加载'));
    if (sessionPromise) return sessionPromise;
    // 先优先使用 WebGPU；不支持时降级 WASM。两者都在本机执行。
    global.ort.env.wasm.wasmPaths = WASM_PATH;
    sessionPromise = global.ort.InferenceSession.create(MODEL_URL, {
      executionProviders: global.navigator && global.navigator.gpu ? ['webgpu', 'wasm'] : ['wasm'],
    }).catch(function () {
      return global.ort.InferenceSession.create(MODEL_URL, { executionProviders: ['wasm'] });
    });
    return sessionPromise;
  }

  function resizeToModel(image) {
    var w = image.width, h = image.height;
    var scale = Math.min(MODEL_SIZE / w, MODEL_SIZE / h);
    var rw = Math.max(1, Math.round(w * scale)), rh = Math.max(1, Math.round(h * scale));
    var padX = Math.floor((MODEL_SIZE - rw) / 2), padY = Math.floor((MODEL_SIZE - rh) / 2);
    var out = new Float32Array(3 * MODEL_SIZE * MODEL_SIZE);
    var src = image.data;
    // 双线性采样；黑色 padding 与模型官方推理预处理一致。
    for (var y = 0; y < rh; y++) {
      var fy = (y + .5) / scale - .5;
      var y0 = Math.max(0, Math.min(h - 1, Math.floor(fy))), y1 = Math.min(h - 1, y0 + 1), wy = fy - Math.floor(fy);
      for (var x = 0; x < rw; x++) {
        var fx = (x + .5) / scale - .5;
        var x0 = Math.max(0, Math.min(w - 1, Math.floor(fx))), x1 = Math.min(w - 1, x0 + 1), wx = fx - Math.floor(fx);
        var i00 = (y0 * w + x0) * 4, i10 = (y0 * w + x1) * 4, i01 = (y1 * w + x0) * 4, i11 = (y1 * w + x1) * 4;
        var dst = (padY + y) * MODEL_SIZE + padX + x;
        for (var c = 0; c < 3; c++) {
          var a = src[i00 + c] * (1 - wx) + src[i10 + c] * wx;
          var b = src[i01 + c] * (1 - wx) + src[i11 + c] * wx;
          out[c * MODEL_SIZE * MODEL_SIZE + dst] = (a * (1 - wy) + b * wy) / 255;
        }
      }
    }
    return { tensor: out, scale: scale, rw: rw, rh: rh, padX: padX, padY: padY };
  }

  function makeBackgroundMask(output, prep, width, height) {
    var out = output.data, ow = output.dims[output.dims.length - 1], oh = output.dims[output.dims.length - 2];
    var mask = new Uint8Array(width * height);
    for (var y = 0; y < height; y++) {
      var my = Math.max(0, Math.min(prep.rh - 1, Math.floor((y + .5) * prep.scale)));
      var sy = Math.max(0, Math.min(oh - 1, Math.floor((prep.padY + my + .5) * oh / MODEL_SIZE)));
      for (var x = 0; x < width; x++) {
        var mx = Math.max(0, Math.min(prep.rw - 1, Math.floor((x + .5) * prep.scale)));
        var sx = Math.max(0, Math.min(ow - 1, Math.floor((prep.padX + mx + .5) * ow / MODEL_SIZE)));
        // 模型输出为角色概率：这里仅供取景，不直接镂空，避免出现大面积空白。
        var subject = out[sy * ow + sx];
        mask[y * width + x] = subject >= .42 ? 0 : 1;
      }
    }
    return mask;
  }

  /** 返回 1=背景 / 0=角色的 mask；失败返回 null，让普通安全算法继续工作。 */
  function segment(image) {
    if (!hasRuntime()) return Promise.resolve(null);
    var prep = resizeToModel(image);
    return getSession().then(function (session) {
      var feeds = {};
      feeds[session.inputNames[0]] = new global.ort.Tensor('float32', prep.tensor, [1, 3, MODEL_SIZE, MODEL_SIZE]);
      return session.run(feeds);
    }).then(function (outputs) {
      var key = Object.keys(outputs)[0];
      if (!key || !outputs[key] || !outputs[key].data) throw new Error('角色识别未返回蒙版');
      return makeBackgroundMask(outputs[key], prep, image.width, image.height);
    }).catch(function (err) {
      // 网络、浏览器算力或模型格式不兼容时不阻断创作，自动降级到本地视觉取景。
      console.warn('动漫主体识别已降级：', err && err.message ? err.message : err);
      return null;
    });
  }

  global.AnimeSegmenter = { segment: segment, modelUrl: MODEL_URL };
})(typeof self !== 'undefined' ? self : globalThis);
