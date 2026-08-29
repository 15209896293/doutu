/*!
 * pixel-app.js — 豆图在线拼豆图纸生成器 UI 逻辑
 * 纯浏览器本地计算（Web Worker 后台执行，失败自动回退主线程）。
 */
(function () {
  'use strict';

  var $ = function (id) { return document.getElementById(id); };

  var PALETTE_META = [
    { id: 'mard_221', name: 'MARD 221', file: 'palettes/mard_221.json' },
    { id: 'mard_291', name: 'MARD 291', file: 'palettes/mard_291.json' },
    { id: 'perler', name: 'Perler', file: 'palettes/perler.json' },
    { id: 'hama', name: 'Hama', file: 'palettes/hama.json' },
  ];
  var WIDTHS = [52, 81, 104, 128];

  var palettes = {}; // id -> [{code,r,g,b,name,productCode}]
  var worker = null;
  try { worker = new Worker('pixel-worker.js'); } catch (e) { worker = null; }

  var state = {
    analysis: null,       // {data, width, height} ≤1024
    fileName: '',
    fileSize: 0,
    preset: 'anime',
    width: 81,
    paletteId: 'mard_221',
    removeBackground: true,
    detailed: false,
    result: null,         // 引擎结果
    grid: null,           // 当前显示网格（排除重映射后）
    bom: [],              // 当前 BOM
    totalBeads: 0,
    excluded: new Set(),  // 已排除色号 code
    view: 'grid',
  };

  // ====================================================================
  // 初始化
  // ====================================================================

  function init() {
    loadPalettes().then(function () {
      buildPresetChips();
      buildWidthSeg();
      buildPaletteSelect();
      bindEvents();
      var p = palettes[state.paletteId];
      if (p) $('paletteInfo').textContent = p.length + ' 色 · 官方/实测数据';
    });
  }

  function loadPalettes() {
    return Promise.all(PALETTE_META.map(function (meta) {
      return fetch(meta.file)
        .then(function (r) { if (!r.ok) throw new Error('色卡加载失败: ' + meta.file); return r.json(); })
        .then(function (arr) {
          palettes[meta.id] = arr.map(function (e) {
            var rgb = e.rgb || [];
            return {
              code: e.code,
              name: e.name || '',
              productCode: e.productCode || '',
              r: rgb.length ? rgb[0] : parseInt(e.hex.slice(1, 3), 16),
              g: rgb.length ? rgb[1] : parseInt(e.hex.slice(3, 5), 16),
              b: rgb.length ? rgb[2] : parseInt(e.hex.slice(5, 7), 16),
            };
          });
        })
        .catch(function (err) {
          console.error(err);
          palettes[meta.id] = [];
        });
    }));
  }

  function buildPresetChips() {
    var box = $('presetChips');
    box.innerHTML = '';
    (window.PixelEngine ? PixelEngine.PRESETS : []).forEach(function (p) {
      var b = document.createElement('button');
      b.className = 'chip' + (p.id === state.preset ? ' on' : '');
      b.innerHTML = '<span>' + p.label + '</span><span class="chip-sub">' + p.sub + '</span>';
      b.onclick = function () {
        state.preset = p.id;
        box.querySelectorAll('.chip').forEach(function (c) { c.classList.remove('on'); });
        b.classList.add('on');
        // 动漫/细腻档强制 CIEDE2000，其它档恢复用户开关
        if (p.id === 'detailed' || p.id === 'anime') {
          state.detailed = true;
          $('deToggle').classList.add('on');
        }
        updateDeToggleHint();
      };
      box.appendChild(b);
    });
  }

  function buildWidthSeg() {
    var seg = $('widthSeg');
    seg.innerHTML = '';
    WIDTHS.forEach(function (w) {
      var b = document.createElement('button');
      b.textContent = w;
      b.className = state.width === w ? 'on' : '';
      b.onclick = function () {
        state.width = w;
        $('customWidthRow').hidden = true;
        seg.querySelectorAll('button').forEach(function (c) { c.classList.remove('on'); });
        b.classList.add('on');
        $('widthLabel').innerHTML = '图纸宽度 <span class="dim">' + w + ' 格</span>';
      };
      seg.appendChild(b);
    });
    var custom = document.createElement('button');
    custom.textContent = '自定义';
    custom.onclick = function () {
      $('customWidthRow').hidden = false;
      seg.querySelectorAll('button').forEach(function (c) { c.classList.remove('on'); });
      custom.classList.add('on');
      state.width = parseInt($('customWidth').value, 10);
      $('widthLabel').innerHTML = '图纸宽度 <span class="dim">自定义 ' + state.width + ' 格</span>';
      $('customWidthVal').textContent = state.width + ' 格';
    };
    seg.appendChild(custom);
  }

  function buildPaletteSelect() {
    var sel = $('paletteSelect');
    sel.innerHTML = '';
    PALETTE_META.forEach(function (m) {
      var o = document.createElement('option');
      o.value = m.id;
      o.textContent = m.name + '（' + (palettes[m.id] ? palettes[m.id].length : '?') + ' 色）';
      sel.appendChild(o);
    });
    sel.value = state.paletteId;
    sel.onchange = function () {
      state.paletteId = sel.value;
      var p = palettes[state.paletteId];
      if (p) $('paletteInfo').textContent = p.length + ' 色 · 官方/实测数据';
    };
  }

  function bindEvents() {
    var dz = $('dropzone');
    dz.addEventListener('click', function () { $('fileInput').click(); });
    dz.addEventListener('dragover', function (e) {
      e.preventDefault();
      dz.classList.add('drag');
    });
    dz.addEventListener('dragleave', function () { dz.classList.remove('drag'); });
    dz.addEventListener('drop', function (e) {
      e.preventDefault();
      dz.classList.remove('drag');
      var f = e.dataTransfer.files && e.dataTransfer.files[0];
      if (f) handleFile(f);
    });
    $('fileInput').addEventListener('change', function (e) {
      var f = e.target.files && e.target.files[0];
      if (f) handleFile(f);
      e.target.value = '';
    });
    $('reChoose').addEventListener('click', function () { $('fileInput').click(); });

    $('bgToggle').addEventListener('click', function () {
      state.removeBackground = !state.removeBackground;
      this.classList.toggle('on', state.removeBackground);
    });
    $('deToggle').addEventListener('click', function () {
      state.detailed = !state.detailed;
      this.classList.toggle('on', state.detailed);
      updateDeToggleHint();
    });
    $('customWidth').addEventListener('input', function () {
      state.width = parseInt(this.value, 10);
      $('customWidthVal').textContent = state.width + ' 格';
      $('widthLabel').innerHTML = '图纸宽度 <span class="dim">自定义 ' + state.width + ' 格</span>';
    });

    $('generateBtn').addEventListener('click', generate);

    var viewSeg = $('viewSeg');
    viewSeg.querySelectorAll('button').forEach(function (b) {
      b.addEventListener('click', function () {
        state.view = b.getAttribute('data-view');
        viewSeg.querySelectorAll('button').forEach(function (c) { c.classList.remove('on'); });
        b.classList.add('on');
        renderCanvas();
      });
    });

    $('bomScroll').addEventListener('click', function (e) {
      var chip = e.target.closest ? e.target.closest('.bom-chip') : null;
      if (chip && chip.dataset.code) toggleExclude(chip.dataset.code);
    });

    $('copyBom').addEventListener('click', copyBom);
    $('restoreAll').addEventListener('click', restoreAll);
    $('dlPng').addEventListener('click', exportPng);
    $('printBtn').addEventListener('click', function () { window.print(); });
  }

  function updateDeToggleHint() {
    var t = $('deToggle');
    if (state.preset === 'detailed' || state.preset === 'anime') t.classList.add('on');
    // hint 文案
    $('deHint').textContent = state.detailed
      ? 'CIEDE2000 · 已开启'
      : 'OKLab · 感知最快';
  }

  // ====================================================================
  // 图片读取
  // ====================================================================

  function handleFile(file) {
    var MAX = 10 * 1024 * 1024;
    if (file.size > MAX) {
      showErr('图片超过 10MB，请压缩后再试');
      return;
    }
    detectHeic(file).then(function (isHeic) {
      if (isHeic) {
        showErr('这张图片实际是 HEIC（即使扩展名显示为 PNG）。请在手机相册中导出为 JPG/PNG 后再上传；这样可避免浏览器解码失败。');
        return;
      }
      if (!/^image\//.test(file.type)) {
        showErr('请选择 JPG / PNG / WebP 图片');
        return;
      }
      readImageFile(file);
    }).catch(function () { readImageFile(file); });
  }

  function readImageFile(file) {
    state.fileName = file.name;
    state.fileSize = file.size;
    decodeToAnalysis(file).then(function (img) {
      state.analysis = img;
      $('thumb').src = img.thumbUrl;
      $('thumbRow').hidden = false;
      $('fileName').textContent = file.name;
      $('fileInfo').textContent =
        img.width + '×' + img.height + 'px · ' + (file.size / 1024 / 1024).toFixed(1) + ' MB';
      $('dropzone').style.display = 'none';
      $('generateBtn').disabled = false;
      $('err').style.display = 'none';
    }).catch(function (err) {
      showErr('图片读取失败：' + err.message);
    });
  }

  function detectHeic(file) {
    return file.slice(0, 16).arrayBuffer().then(function (buffer) {
      var bytes = new Uint8Array(buffer);
      if (bytes.length < 12) return false;
      var brand = String.fromCharCode(bytes[4], bytes[5], bytes[6], bytes[7]) +
        String.fromCharCode(bytes[8], bytes[9], bytes[10], bytes[11]);
      return brand.slice(0, 4) === 'ftyp' && /heic|heix|hevc|hevx|mif1|msf1/.test(brand.slice(4));
    });
  }

  function decodeToAnalysis(file) {
    return new Promise(function (resolve, reject) {
      function fromBitmap(bmp) {
        try {
          var scale = Math.min(1, 1024 / Math.max(bmp.width, bmp.height));
          var w = Math.max(1, Math.round(bmp.width * scale));
          var h = Math.max(1, Math.round(bmp.height * scale));
          var canvas = document.createElement('canvas');
          canvas.width = w; canvas.height = h;
          var ctx = canvas.getContext('2d', { willReadFrequently: true });
          ctx.drawImage(bmp, 0, 0, w, h);
          var data = ctx.getImageData(0, 0, w, h);

          // 缩略图
          var thumbCanvas = document.createElement('canvas');
          thumbCanvas.width = 96; thumbCanvas.height = 96;
          var tctx = thumbCanvas.getContext('2d');
          var s = Math.max(w / 96, h / 96);
          tctx.drawImage(canvas, (w - 96 * s) / 2, (h - 96 * s) / 2, 96 * s, 96 * s, 0, 0, 96, 96);
          resolve({
            data: data.data, width: w, height: h,
            thumbUrl: thumbCanvas.toDataURL('image/png'),
          });
        } catch (err) { reject(err); }
      }
      if (window.createImageBitmap) {
        createImageBitmap(file).then(fromBitmap, function () { fallbackLoad(); });
      } else {
        fallbackLoad();
      }
      function fallbackLoad() {
        var url = URL.createObjectURL(file);
        var img = new Image();
        img.onload = function () {
          fromBitmap(img);
          URL.revokeObjectURL(url);
        };
        img.onerror = function () { URL.revokeObjectURL(url); reject(new Error('无法解码此图片')); };
        img.src = url;
      }
    });
  }

  // ====================================================================
  // 生成
  // ====================================================================

  function gridDims() {
    var a = state.analysis;
    var gw = state.width;
    var gh = Math.max(1, Math.round(gw * a.height / a.width));
    if (gh > 200) {
      var s = 200 / gh;
      gw = Math.max(16, Math.round(gw * s));
      gh = 200;
    }
    return { gridWidth: gw, gridHeight: gh };
  }

  function generate() {
    var a = state.analysis;
    if (!a) { showErr('请先选择一张图片'); return; }
    var dims = gridDims();
    var palette = palettes[state.paletteId];
    if (!palette || palette.length === 0) { showErr('色卡加载失败，请刷新重试'); return; }

    $('err').style.display = 'none';
    $('loading').style.display = 'block';
    $('generateBtn').disabled = true;

    var input = {
      imageData: { data: a.data, width: a.width, height: a.height },
      gridWidth: dims.gridWidth,
      gridHeight: dims.gridHeight,
      preset: state.preset,
      palette: palette,
      removeBackground: state.removeBackground,
      distance: state.detailed ? 'ciede2000' : 'oklab',
      maxColors: null,
    };

    runConvert(input).then(function (r) {
      state.result = r;
      state.excluded = new Set();
      state.grid = new Int32Array(r.grid);
      rebuildBom();
      $('loading').style.display = 'none';
      $('generateBtn').disabled = false;
      $('result').classList.add('show');
      renderStats();
      renderBom();
      renderCanvas();
      $('result').scrollIntoView({ behavior: 'smooth', block: 'start' });
    }).catch(function (err) {
      $('loading').style.display = 'none';
      $('generateBtn').disabled = false;
      showErr('生成失败：' + (err && err.message ? err.message : err));
    });
  }

  function runConvert(input) {
    return new Promise(function (resolve, reject) {
      if (worker) {
        worker.onmessage = function (e) {
          if (e.data.ok) resolve(e.data.result);
          else reject(new Error(e.data.error || 'worker 错误'));
        };
        worker.onerror = function (e) {
          reject(new Error(e.message || 'worker 异常'));
        };
        worker.postMessage(input);
      } else {
        try {
          resolve(PixelEngine.convert(input));
        } catch (e) { reject(e); }
      }
    });
  }

  // ====================================================================
  // 结果展示
  // ====================================================================

  function rebuildBom() {
    var palette = palettes[state.paletteId];
    var counts = new Map();
    for (var i = 0; i < state.grid.length; i++) {
      var v = state.grid[i];
      if (v < 0) continue;
      counts.set(v, (counts.get(v) || 0) + 1);
    }
    var bom = [];
    counts.forEach(function (count, idx) {
      var e = palette[idx];
      if (!e) return;
      bom.push({
        code: e.code, name: e.name || '', r: e.r, g: e.g, b: e.b,
        color: (e.r << 16) | (e.g << 8) | e.b, count: count,
      });
    });
    bom.sort(function (a, b) { return b.count - a.count; });
    state.bom = bom;
    state.totalBeads = bom.reduce(function (s, e) { return s + e.count; }, 0);
  }

  function renderStats() {
    var r = state.result;
    var parts = [];
    parts.push('尺寸 <b>' + r.size + '×' + r.height + '</b>');
    parts.push('色数 <b>' + state.bom.length + '</b>');
    parts.push('总颗数 <b>' + state.totalBeads.toLocaleString() + '</b>');
    parts.push('平均色差 <b>ΔE ' + r.meanMappingDistance.toFixed(1) + '</b>');
    var bgText;
    if (r.backgroundDetected) {
      bgText = '背景已移除（置信度 <b>' + Math.round(r.backgroundConfidence * 100) + '%</b>）';
    } else if (state.removeBackground) {
      bgText = '未检测到明显背景';
    } else {
      bgText = '未去背景';
    }
    var warns = [];
    if (r.rareColorCount > 0) warns.push('稀有色 ' + r.rareColorCount + ' 色');
    if (r.singleCellRegionCount > 0) warns.push('孤立单格 ' + r.singleCellRegionCount);
    var html = '';
    parts.forEach(function (p) { html += '<span class="stat">' + p + '</span>'; });
    html += '<span class="stat">' + bgText + '</span>';
    warns.forEach(function (w) { html += '<span class="stat warn">⚠️ ' + w + '</span>'; });
    $('stats').innerHTML = html;

    var meta = PALETTE_META.filter(function (m) { return m.id === state.paletteId; })[0];
    $('resultDesc').textContent =
      meta.name + ' 色卡 · ' + (PRESET_LABELS[state.preset] || state.preset) + ' 档 · 纯本地计算，图片未上传';
  }

  function renderBom() {
    var box = $('bomScroll');
    box.innerHTML = '';
    $('bomTotal').textContent = '共 ' + state.totalBeads.toLocaleString() + ' 颗 · ' + state.bom.length + ' 色';
    var palette = paletteOf();
    var shownCodes = {};
    state.bom.forEach(function (e) {
      shownCodes[e.code] = true;
      appendBomChip(box, e, state.excluded.has(e.code));
    });
    // 已排除的色号仍保留在清单里（置灰，可点击恢复）
    state.excluded.forEach(function (code) {
      if (shownCodes[code]) return;
      var e = null;
      for (var i = 0; i < palette.length; i++) {
        if (palette[i].code === code) { e = palette[i]; break; }
      }
      if (!e) return;
      appendBomChip(box, { code: e.code, name: e.name || '', r: e.r, g: e.g, b: e.b, count: 0 }, true);
    });
  }

  function appendBomChip(box, e, excluded) {
    var div = document.createElement('div');
    div.className = 'bom-chip' + (excluded ? ' excluded' : '');
    div.dataset.code = e.code;
    var lum = (0.2126 * e.r + 0.7152 * e.g + 0.0722 * e.b) / 255;
    var fg = lum > 0.5 ? '#1D1D1F' : '#FFFFFF';
    div.innerHTML =
      '<div class="bom-swatch" style="background:rgb(' + e.r + ',' + e.g + ',' + e.b + ');color:' + fg + '">' +
      (excluded ? '✕' : e.code) + '</div>' +
      '<div class="bom-code">' + e.code + '</div>' +
      '<div class="bom-count">' + (excluded ? '已排除' : e.count + ' 颗') + '</div>';
    box.appendChild(div);
  }

  // ====================================================================
  // 画布绘制
  // ====================================================================

  function paletteOf() { return palettes[state.paletteId]; }

  function cellPxFor(n, m, max) {
    return Math.max(2, Math.min(40, Math.floor((max || 880) / Math.max(n, m))));
  }

  function renderCanvas() {
    var r = state.result;
    if (!r) return;
    var wrap = $('canvasWrap');
    wrap.innerHTML = '';
    var palette = paletteOf();
    var cell = cellPxFor(r.size, r.height);
    var common = { grid: state.grid, n: r.size, m: r.height, palette: palette, cell: cell };

    if (state.view === 'compare') {
      var colL = document.createElement('div');
      colL.className = 'canvas-col';
      var capL = document.createElement('div');
      capL.className = 'cap';
      capL.textContent = '原图';
      colL.appendChild(capL);
      colL.appendChild(makeCanvas(common, { mode: 'original' }));
      wrap.appendChild(colL);

      var colR = document.createElement('div');
      colR.className = 'canvas-col';
      var capR = document.createElement('div');
      capR.className = 'cap';
      capR.textContent = '图纸';
      colR.appendChild(capR);
      colR.appendChild(makeCanvas(common, { mode: 'flat', codes: true }));
      wrap.appendChild(colR);
    } else {
      wrap.appendChild(makeCanvas(common, {
        mode: state.view === 'mock' ? 'round' : 'flat',
        codes: state.view === 'grid',
      }));
    }
  }

  function makeCanvas(common, opts) {
    var canvas = document.createElement('canvas');
    canvas.className = 'pattern';
    var ctx = canvas.getContext('2d');
    drawPattern(ctx, common.grid, common.n, common.m, common.palette, common.cell, opts);
    return canvas;
  }

  function drawPattern(ctx, grid, n, m, palette, cell, opts) {
    opts = opts || {};
    ctx.canvas.width = n * cell;
    ctx.canvas.height = m * cell;
    ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);

    if (opts.mode === 'original') {
      // 原图：最近邻缩放到网格尺寸
      var a = state.analysis;
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(imageFromAnalysis(), 0, 0, n * cell, m * cell);
      return;
    }

    for (var y = 0; y < m; y++) {
      for (var x = 0; x < n; x++) {
        var v = grid[y * n + x];
        var px = x * cell, py = y * cell;
        if (v < 0) {
          // 背景/透明：棋盘浅格
          ctx.fillStyle = (x + y) % 2 === 0 ? '#F5F5F7' : '#EDEDF0';
          ctx.fillRect(px, py, cell, cell);
          continue;
        }
        var e = palette[v];
        var color = 'rgb(' + e.r + ',' + e.g + ',' + e.b + ')';
        if (opts.mode === 'round') {
          drawBead(ctx, px, py, cell, color);
        } else {
          ctx.fillStyle = color;
          ctx.fillRect(px, py, cell, cell);
        }
      }
    }

    // 网格线：细 + 每 5 格中粗 + 每 10 格大粗
    if (opts.mode !== 'round') {
      ctx.lineWidth = Math.max(0.5, cell * 0.04);
      for (var i = 0; i <= n; i++) {
        var strong = i % 10 === 0 ? 0.22 : i % 5 === 0 ? 0.12 : 0.06;
        ctx.strokeStyle = 'rgba(0,0,0,' + strong + ')';
        ctx.beginPath();
        ctx.moveTo(i * cell + 0.5, 0);
        ctx.lineTo(i * cell + 0.5, m * cell);
        ctx.stroke();
      }
      for (var j = 0; j <= m; j++) {
        var strong2 = j % 10 === 0 ? 0.22 : j % 5 === 0 ? 0.12 : 0.06;
        ctx.strokeStyle = 'rgba(0,0,0,' + strong2 + ')';
        ctx.beginPath();
        ctx.moveTo(0, j * cell + 0.5);
        ctx.lineTo(n * cell, j * cell + 0.5);
        ctx.stroke();
      }
    }

    // 色号文字
    if (opts.codes && cell >= 9) {
      ctx.font = '700 ' + Math.max(8, Math.round(cell * 0.34)) + 'px "SF Mono", ui-monospace, Menlo, Consolas, monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      for (var yy = 0; yy < m; yy++) {
        for (var xx = 0; xx < n; xx++) {
          var vv = grid[yy * n + xx];
          if (vv < 0) continue;
          var ee = palette[vv];
          var lum = (0.2126 * ee.r + 0.7152 * ee.g + 0.0722 * ee.b) / 255;
          ctx.fillStyle = lum > 0.5 ? '#1D1D1F' : '#FFFFFF';
          ctx.fillText(ee.code, xx * cell + cell / 2, yy * cell + cell / 2 + 0.5);
        }
      }
    }
  }

  function drawBead(ctx, px, py, cell, color) {
    var cx = px + cell / 2, cy = py + cell / 2;
    var radius = cell * 0.46;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, Math.PI * 2);
    ctx.fill();
    // 高光
    ctx.fillStyle = 'rgba(255,255,255,0.35)';
    ctx.beginPath();
    ctx.arc(cx - radius * 0.25, cy - radius * 0.3, radius * 0.28, 0, Math.PI * 2);
    ctx.fill();
    // 中心孔
    ctx.fillStyle = 'rgba(255,255,255,0.85)';
    ctx.beginPath();
    ctx.arc(cx, cy, radius * 0.28, 0, Math.PI * 2);
    ctx.fill();
  }

  var _analysisCanvas = null;
  function imageFromAnalysis() {
    var a = state.analysis;
    if (!_analysisCanvas || _analysisCanvas.width !== a.width) {
      _analysisCanvas = document.createElement('canvas');
      _analysisCanvas.width = a.width;
      _analysisCanvas.height = a.height;
      _analysisCanvas.getContext('2d').putImageData(
        new ImageData(new Uint8ClampedArray(a.data), a.width, a.height), 0, 0);
    }
    return _analysisCanvas;
  }

  // ====================================================================
  // 色号排除 / 恢复
  // ====================================================================

  function toggleExclude(code) {
    var r = state.result;
    if (!r) return;
    if (!state.excluded.delete(code)) state.excluded.add(code);
    if (state.excluded.size === 0) {
      state.grid = new Int32Array(r.grid);
      rebuildBom();
      renderBom();
      renderCanvas();
      renderStats();
      return;
    }
    var palette = paletteOf();
    var used = new Set();
    for (var i = 0; i < r.grid.length; i++) if (r.grid[i] >= 0) used.add(r.grid[i]);
    var keep = [];
    used.forEach(function (idx) {
      if (!state.excluded.has(palette[idx].code)) keep.push(idx);
    });
    if (keep.length === 0) {
      state.excluded.delete(code); // 全部排除会导致无色可用，阻止
      return;
    }
    var distMode = state.detailed ? 'ciede2000' : 'oklab';
    var distFn = distMode === 'ciede2000' ? PixelEngine.ciede2000 : PixelEngine.oklabDistance;
    var labOf = function (e) {
      return distMode === 'ciede2000'
        ? PixelEngine.rgbToLab(e.r, e.g, e.b)
        : PixelEngine.srgbToOklab(e.r, e.g, e.b);
    };
    var keepLab = keep.map(function (idx) { return labOf(palette[idx]); });
    var grid = new Int32Array(r.grid.length);
    for (var k = 0; k < r.grid.length; k++) {
      var v = r.grid[k];
      if (v < 0) { grid[k] = -1; continue; }
      if (keep.indexOf(v) >= 0) { grid[k] = v; continue; }
      var bi = 0, bd = Infinity;
      for (var j = 0; j < keep.length; j++) {
        var d = distFn(labOf(palette[v]), keepLab[j]);
        if (d < bd) { bd = d; bi = j; }
      }
      grid[k] = keep[bi];
    }
    state.grid = grid;
    rebuildBom();
    renderBom();
    renderCanvas();
    renderStats();
  }

  function restoreAll() {
    if (!state.result) return;
    state.excluded.clear();
    state.grid = new Int32Array(state.result.grid);
    rebuildBom();
    renderBom();
    renderCanvas();
    renderStats();
  }

  // ====================================================================
  // 导出 / 复制
  // ====================================================================

  function exportPng() {
    var r = state.result;
    if (!r) return;
    var palette = paletteOf();
    var longSide = Math.max(r.size, r.height);
    var cell = 1080 / longSide;
    var gw = Math.max(1, Math.round(r.size * cell));
    var gh = Math.max(1, Math.round(r.height * cell));

    // 图纸板（drawPattern 会重置 canvas 尺寸，故先单独画板）
    var board = document.createElement('canvas');
    board.width = gw; board.height = gh;
    drawPattern(board.getContext('2d'), state.grid, r.size, r.height, palette, cell, { mode: 'flat', codes: true });

    // —— 清单区布局 ——
    var padX = 24, sw = 52, gap = 16, labelH = 24, titleH = 36, spaceTop = 28, padBottom = 24;
    var itemW = sw + gap;
    var cols = Math.max(1, Math.floor((gw - padX * 2) / itemW));
    var rows = state.bom.length ? Math.ceil(state.bom.length / cols) : 0;
    var extraH = spaceTop + titleH + rows * (sw + labelH) + padBottom;

    var out = document.createElement('canvas');
    out.width = gw; out.height = gh + extraH;
    var ctx = out.getContext('2d');
    ctx.fillStyle = '#FFFFFF'; ctx.fillRect(0, 0, gw, gh + extraH);
    ctx.drawImage(board, 0, 0);

    // 标题
    var y = gh + spaceTop;
    ctx.fillStyle = '#1D1D1F';
    ctx.font = '700 ' + Math.round(titleH * 0.6) + 'px -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif';
    ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
    ctx.fillText('用量清单 · 共 ' + state.totalBeads + ' 颗 / ' + state.bom.length + ' 色', padX, y + Math.round(titleH * 0.72));
    y += titleH;

    // 色块列表：色块带色号 + 颗数
    ctx.textBaseline = 'middle';
    state.bom.forEach(function (e, i) {
      var col = i % cols, row = Math.floor(i / cols);
      var x = padX + col * itemW;
      var yy = y + row * (sw + labelH);
      var lum = (0.2126 * e.r + 0.7152 * e.g + 0.0722 * e.b) / 255;

      ctx.fillStyle = 'rgb(' + e.r + ',' + e.g + ',' + e.b + ')';
      ctx.fillRect(x, yy, sw, sw);
      ctx.lineWidth = 1; ctx.strokeStyle = 'rgba(0,0,0,0.12)';
      ctx.strokeRect(x + 0.5, yy + 0.5, sw - 1, sw - 1);

      ctx.fillStyle = lum > 0.5 ? '#1D1D1F' : '#FFFFFF';
      ctx.font = '700 ' + Math.round(sw * 0.24) + 'px "SF Mono", ui-monospace, Menlo, Consolas, monospace';
      ctx.textAlign = 'center';
      ctx.fillText(e.code, x + sw / 2, yy + sw / 2 + 0.5);

      ctx.fillStyle = '#6E6E73';
      ctx.font = '600 ' + Math.round(sw * 0.22) + 'px -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif';
      ctx.fillText(e.count + ' 颗', x + sw / 2, yy + sw + labelH * 0.5);
    });

    out.toBlob(function (blob) {
      var a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = '豆图_' + r.size + 'x' + r.height + '.png';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(function () { URL.revokeObjectURL(a.href); }, 3000);
    }, 'image/png');
  }

  function copyBom() {
    var text = '拼豆用量清单\n共 ' + state.totalBeads + ' 颗 · ' + state.bom.length + ' 色\n';
    text += '--------------------------\n';
    state.bom.forEach(function (e) {
      text += e.code + '\t' + e.count + ' 颗\n';
    });
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () { flashCopied(); });
    } else {
      var ta = document.createElement('textarea');
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); flashCopied(); } catch (e) {}
      document.body.removeChild(ta);
    }
  }

  function flashCopied() {
    var b = $('copyBom');
    var old = b.textContent;
    b.textContent = '✅ 已复制';
    setTimeout(function () { b.textContent = old; }, 1500);
  }

  function showErr(msg) {
    var el = $('err');
    el.textContent = msg;
    el.style.display = 'block';
  }

  // 预设中文名（供结果描述）
  var PRESET_LABELS = {
    anime: '✦ 动漫增强', simplified: '⚡ 精简', standard: '✨ 标准',
    detailed: '🔬 细腻', smooth: '🌊 平滑',
  };

  document.addEventListener('DOMContentLoaded', init);
})();
