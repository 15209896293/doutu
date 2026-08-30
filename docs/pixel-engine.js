/*!
 * pixel-engine.js — 拼豆图纸生成引擎（纯浏览器端计算）
 *
 * 移植自「豆图 · 拼豆图纸转化器」Dart 核心（lib/core/），算法与 pixel-beads.com
 * 同源：dominant-bucket 众数采样 → 双阈值 flood-fill 去背景 → OKLab / CIEDE2000
 * 感知色差 → 贪心最大覆盖选色 / 聚类吸附 → 可选抖动 → 邻域多数表决清理。
 *
 * 无任何 DOM 依赖，可在 Web Worker 或主线程运行。
 */
(function (global) {
  'use strict';

  // ======================================================================
  // 一、色彩空间
  // ======================================================================

  function srgbToLinear(c) {
    const v = c / 255;
    return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  }

  /** sRGB（0-255）→ OKLab（Björn Ottosson） */
  function srgbToOklab(r, g, b) {
    const rl = srgbToLinear(r);
    const gl = srgbToLinear(g);
    const bl = srgbToLinear(b);
    const l = 0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl;
    const m = 0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl;
    const s = 0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl;
    const l_ = Math.cbrt(l);
    const m_ = Math.cbrt(m);
    const s_ = Math.cbrt(s);
    return {
      l: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
      a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
      b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    };
  }

  /** OKLab 欧氏距离 ×100（与 ΔE 同量纲） */
  function oklabDistance(a, b) {
    const dl = a.l - b.l;
    const da = a.a - b.a;
    const db = a.b - b.b;
    return Math.sqrt(dl * dl + da * da + db * db) * 100;
  }

  /** sRGB（0-255）→ CIELAB（D65） */
  function rgbToLab(r, g, b) {
    const rl = srgbToLinear(r);
    const gl = srgbToLinear(g);
    const bl = srgbToLinear(b);
    const x = rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375;
    const y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750;
    const z = rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041;
    return xyzToLab(x, y, z);
  }

  function xyzToLab(x, y, z) {
    const xn = 0.95047, yn = 1.0, zn = 1.08883;
    const fx = fLab(x / xn), fy = fLab(y / yn), fz = fLab(z / zn);
    return { l: 116.0 * fy - 16.0, a: 500.0 * (fx - fy), b: 200.0 * (fy - fz) };
  }

  function fLab(t) {
    const delta = 6.0 / 29.0;
    return t > delta * delta * delta
      ? Math.cbrt(t)
      : t / (3 * delta * delta) + 4.0 / 29.0;
  }

  /** CIEDE2000 色差（Sharma et al. 2005） */
  function ciede2000(c1, c2) {
    const l1 = c1.l, a1 = c1.a, b1 = c1.b;
    const l2 = c2.l, a2 = c2.a, b2 = c2.b;

    const c1ab = Math.sqrt(a1 * a1 + b1 * b1);
    const c2ab = Math.sqrt(a2 * a2 + b2 * b2);
    const cab = (c1ab + c2ab) / 2.0;

    const g = 0.5 * (1.0 - Math.sqrt(Math.pow(cab, 7) / (Math.pow(cab, 7) + Math.pow(25.0, 7))));

    const a1p = (1.0 + g) * a1;
    const a2p = (1.0 + g) * a2;

    const c1p = Math.sqrt(a1p * a1p + b1 * b1);
    const c2p = Math.sqrt(a2p * a2p + b2 * b2);

    let h1p;
    if (a1p === 0 && b1 === 0) h1p = 0;
    else {
      h1p = Math.atan2(b1, a1p) * 180 / Math.PI;
      if (h1p < 0) h1p += 360;
    }
    let h2p;
    if (a2p === 0 && b2 === 0) h2p = 0;
    else {
      h2p = Math.atan2(b2, a2p) * 180 / Math.PI;
      if (h2p < 0) h2p += 360;
    }

    const dlp = l2 - l1;
    const dcp = c2p - c1p;

    let dhp;
    if (c1p * c2p === 0) dhp = 0;
    else if (Math.abs(h2p - h1p) <= 180) dhp = h2p - h1p;
    else if (h2p - h1p > 180) dhp = h2p - h1p - 360;
    else dhp = h2p - h1p + 360;

    const dlhp = 2 * Math.sqrt(c1p * c2p) * Math.sin(rad(dhp / 2));

    const lp = (l1 + l2) / 2.0;
    const cp = (c1p + c2p) / 2.0;

    let hpp;
    if (c1p * c2p === 0) hpp = h1p + h2p;
    else if (Math.abs(h1p - h2p) <= 180) hpp = (h1p + h2p) / 2.0;
    else if (Math.abs(h1p - h2p) > 180 && h1p + h2p < 360) hpp = (h1p + h2p + 360) / 2.0;
    else hpp = (h1p + h2p - 360) / 2.0;

    const t = 1 -
      0.17 * Math.cos(rad(hpp - 30)) +
      0.24 * Math.cos(rad(2 * hpp)) +
      0.32 * Math.cos(rad(3 * hpp + 6)) -
      0.20 * Math.cos(rad(4 * hpp - 63));

    const dtheta = 30 * Math.exp(-Math.pow((hpp - 275) / 25, 2));
    const rc = 2 * Math.sqrt(Math.pow(cp, 7) / (Math.pow(cp, 7) + Math.pow(25.0, 7)));

    const sl = 1 + (0.015 * Math.pow(lp - 50, 2)) / Math.sqrt(20 + Math.pow(lp - 50, 2));
    const sc = 1 + 0.045 * cp;
    const sh = 1 + 0.015 * cp * t;
    const rt = -Math.sin(rad(2 * dtheta)) * rc;

    const dl = dlp / sl;
    const dc = dcp / sc;
    const dh = dlhp / sh;
    return Math.sqrt(dl * dl + dc * dc + dh * dh + rt * dc * dh);
  }

  function rad(deg) { return deg * Math.PI / 180.0; }

  // ======================================================================
  // 二、背景检测（像素级：边界聚类锚点 + 置信度 + 双阈值 flood-fill）
  // ======================================================================

  /**
   * @param {Uint8ClampedArray} rgba 分析图像素（RGBA）
   * @param {number} w @param {number} h
   * @param {object} opts {seedDeltaE, fillDeltaE, minimumConfidence, minimumForegroundCoverage, maxAnchorColors, alphaThreshold}
   * @returns {{mask: Uint8Array, detected: boolean, confidence: number}}
   */
  function detectBackground(rgba, w, h, opts) {
    const o = Object.assign({
      seedDeltaE: 8, fillDeltaE: 14, minimumConfidence: 0.85,
      minimumForegroundCoverage: 0.05, maxAnchorColors: 3, alphaThreshold: 16,
    }, opts || {});
    const total = w * h;

    const alphaMask = new Uint8Array(total);
    for (let i = 0; i < total; i++) {
      if (rgba[i * 4 + 3] <= o.alphaThreshold) alphaMask[i] = 1;
    }

    // 边界不透明像素
    const borderRgb = [];
    for (let x = 0; x < w; x++) {
      pushOpaque(borderRgb, rgba, alphaMask, x, 0, w);
      pushOpaque(borderRgb, rgba, alphaMask, x, h - 1, w);
    }
    for (let y = 1; y < h - 1; y++) {
      pushOpaque(borderRgb, rgba, alphaMask, 0, y, w);
      pushOpaque(borderRgb, rgba, alphaMask, w - 1, y, w);
    }
    if (borderRgb.length === 0) {
      return { mask: alphaMask, detected: false, confidence: 1.0 };
    }

    const anchors = clusterBorderColors(borderRgb, o.maxAnchorColors);
    if (anchors.length === 0) {
      return { mask: alphaMask, detected: false, confidence: 0 };
    }
    const anchorLabs = anchors.map(rgbToLabOf);

    // 置信度：边界像素被任一锚点覆盖的并集占比
    let covered = 0;
    for (const rgb of borderRgb) {
      const lab = rgbToLabOf(rgb);
      for (const a of anchorLabs) {
        if (ciede2000(lab, a) <= o.seedDeltaE) { covered++; break; }
      }
    }
    const confidence = covered / borderRgb.length;
    if (confidence < o.minimumConfidence) {
      return { mask: alphaMask, detected: false, confidence };
    }

    // 松档 flood-fill → 前景占比把关
    let res = floodFill(rgba, w, h, alphaMask, anchorLabs, o.seedDeltaE, o.fillDeltaE, o.alphaThreshold);

    if (res.fgRatio < o.minimumForegroundCoverage) {
      const tightFill = o.fillDeltaE / 1.6;
      const tight = floodFill(rgba, w, h, alphaMask, anchorLabs, o.seedDeltaE, tightFill, o.alphaThreshold);
      if (tight.fgRatio >= o.minimumForegroundCoverage) {
        res = tight;
      } else {
        return { mask: alphaMask, detected: false, confidence };
      }
    }
    return { mask: res.mask, detected: true, confidence };
  }

  function pushOpaque(out, rgba, mask, x, y, w) {
    const i = y * w + x;
    if (mask[i] === 1) return;
    const o = i * 4;
    out.push((rgba[o] << 16) | (rgba[o + 1] << 8) | rgba[o + 2]);
  }

  function rgbToLabOf(rgb) {
    return rgbToLab((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
  }

  /** 边界颜色聚类：量化桶频率 top-K 的均值色，合并相近锚点 */
  function clusterBorderColors(colors, maxColors) {
    const step = 24;
    const qn = Math.ceil(256 / step);
    const count = new Map(), sumR = new Map(), sumG = new Map(), sumB = new Map();
    for (const c of colors) {
      const bkt = (((c >> 16) & 0xFF) / step | 0) * qn * qn +
        ((((c >> 8) & 0xFF) / step | 0)) * qn +
        ((c & 0xFF) / step | 0);
      count.set(bkt, (count.get(bkt) || 0) + 1);
      sumR.set(bkt, (sumR.get(bkt) || 0) + ((c >> 16) & 0xFF));
      sumG.set(bkt, (sumG.get(bkt) || 0) + ((c >> 8) & 0xFF));
      sumB.set(bkt, (sumB.get(bkt) || 0) + (c & 0xFF));
    }
    const sorted = [...count.entries()].sort((a, b) => b[1] - a[1]);
    const out = [];
    for (const [bkt, n] of sorted) {
      out.push((Math.round(sumR.get(bkt) / n) << 16) |
        (Math.round(sumG.get(bkt) / n) << 8) |
        Math.round(sumB.get(bkt) / n));
      if (out.length >= maxColors) break;
    }
    const merged = [];
    for (const c of out) {
      let dup = false;
      const lab = rgbToLabOf(c);
      for (const m of merged) {
        if (ciede2000(lab, rgbToLabOf(m)) <= 4.0) { dup = true; break; }
      }
      if (!dup) merged.push(c);
    }
    return merged.length ? merged : out;
  }

  /** 多锚点双阈值 flood-fill：返回 {mask, fgRatio} */
  function floodFill(rgba, w, h, baseMask, anchorLabs, seedDeltaE, fillDeltaE, alphaThreshold) {
    const mask = Uint8Array.from(baseMask);
    const visited = new Uint8Array(w * h);
    const q = [];
    const total = w * h;

    function trySeed(x, y) {
      const i = y * w + x;
      if (visited[i] === 1 || mask[i] === 1) return;
      const o = i * 4;
      if (rgba[o + 3] <= alphaThreshold) {
        visited[i] = 1; mask[i] = 1; q.push(i); return;
      }
      const lab = rgbToLab(rgba[o], rgba[o + 1], rgba[o + 2]);
      for (const a of anchorLabs) {
        if (ciede2000(lab, a) <= seedDeltaE) {
          visited[i] = 1; mask[i] = 1; q.push(i); return;
        }
      }
    }

    for (let x = 0; x < w; x++) { trySeed(x, 0); trySeed(x, h - 1); }
    for (let y = 1; y < h - 1; y++) { trySeed(0, y); trySeed(w - 1, y); }

    let head = 0;
    while (head < q.length) {
      const cur = q[head++];
      const cx = cur % w;
      const cy = (cur / w) | 0;
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nx = cx + dx, ny = cy + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        const ni = ny * w + nx;
        if (visited[ni] === 1 || mask[ni] === 1) continue;
        const o = ni * 4;
        if (rgba[o + 3] <= alphaThreshold) {
          visited[ni] = 1; mask[ni] = 1; q.push(ni); continue;
        }
        const lab = rgbToLab(rgba[o], rgba[o + 1], rgba[o + 2]);
        for (const a of anchorLabs) {
          if (ciede2000(lab, a) <= fillDeltaE) {
            visited[ni] = 1; mask[ni] = 1; q.push(ni); break;
          }
        }
      }
    }

    let fg = 0;
    for (let i = 0; i < total; i++) if (mask[i] === 0) fg++;
    return { mask, fgRatio: fg / total };
  }

  // ======================================================================
  // 三、网格采样（dominant-bucket 众数 / 区域均值 + 轮廓检测）
  // ======================================================================

  /**
   * @param {Uint8ClampedArray} rgba 分析图像素（RGBA）
   * @param {number} w @param {number} h
   * @param {object} opts {
   *   gridWidth, gridHeight, mode: 'dominant'|'average', bits,
   *   outlineDarkLuminance, outlineDarkRatio, outlineContrast,
   *   minimumForegroundCoverage, backgroundMask
   * }
   * @returns {{colors: Int32Array, avgColors: Int32Array, cells: Array, gridWidth, gridHeight}}
   *   cells[i] = {rgb, coverage, darkRatio, luminanceRange, isOutline} | null
   */
  function sampleGrid(rgba, w, h, opts) {
    const o = Object.assign({
      mode: 'dominant', bits: 4,
      outlineDarkLuminance: 0.32, outlineDarkRatio: 0.20, outlineContrast: 0.16,
      minimumForegroundCoverage: 0.15, backgroundMask: null,
    }, opts || {});
    const n = o.gridWidth;
    const m = o.gridHeight;
    const total = n * m;

    const colors = new Int32Array(total);
    const avgColors = new Int32Array(total);
    const cells = new Array(total).fill(null);

    const bits = o.bits;
    const bucketCount = 1 << (3 * bits);
    const shift = 8 - bits;

    const hist = new Int32Array(bucketCount);
    const sumR = new Int32Array(bucketCount);
    const sumG = new Int32Array(bucketCount);
    const sumB = new Int32Array(bucketCount);
    const touched = [];
    const mask = o.backgroundMask;

    for (let gy = 0; gy < m; gy++) {
      const y0f = gy * h / m;
      const y1f = (gy + 1) * h / m;
      const y0 = Math.max(0, Math.floor(y0f));
      const y1 = Math.min(h, Math.ceil(y1f));
      for (let gx = 0; gx < n; gx++) {
        const x0f = gx * w / n;
        const x1f = (gx + 1) * w / n;
        const x0 = Math.max(0, Math.floor(x0f));
        const x1 = Math.min(w, Math.ceil(x1f));

        let weight = 0, wR = 0, wG = 0, wB = 0;
        let darkW = 0, dR = 0, dG = 0, dB = 0;
        let minLum = 1, maxLum = 0;
        touched.length = 0;

        for (let py = y0; py < y1; py++) {
          const overlapY = overlap(y0f, y1f, py);
          if (overlapY === 0) continue;
          const row = py * w;
          for (let px = x0; px < x1; px++) {
            const pi = row + px;
            if (mask && mask[pi] === 1) continue;
            const overlapX = overlap(x0f, x1f, px);
            const ov = overlapX * overlapY;
            if (ov === 0) continue;
            const o4 = pi * 4;
            const a = rgba[o4 + 3];
            if (a === 0) continue;
            const alpha = a / 255.0;
            const yw = ov * alpha;
            if (yw === 0) continue;
            const r = rgba[o4], g = rgba[o4 + 1], b = rgba[o4 + 2];

            weight += yw;
            wR += r * yw; wG += g * yw; wB += b * yw;

            const lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
            if (lum < minLum) minLum = lum;
            if (lum > maxLum) maxLum = lum;
            if (lum <= o.outlineDarkLuminance) {
              darkW += yw; dR += r * yw; dG += g * yw; dB += b * yw;
            }

            if (o.mode === 'dominant') {
              const bucket = ((r >> shift) << (2 * bits)) |
                ((g >> shift) << bits) |
                (b >> shift);
              if (hist[bucket] === 0) touched.push(bucket);
              hist[bucket]++;
              sumR[bucket] += r; sumG[bucket] += g; sumB[bucket] += b;
            }
          }
        }

        const idx = gy * n + gx;
        const cellArea = (x1f - x0f) * (y1f - y0f);
        const coverage = cellArea > 0 ? weight / cellArea : 0;

        let ar = 0, ag = 0, ab = 0;
        if (weight > 0) { ar = wR / weight; ag = wG / weight; ab = wB / weight; }
        avgColors[idx] = (clamp8(Math.round(ar)) << 16) | (clamp8(Math.round(ag)) << 8) | clamp8(Math.round(ab));

        if (weight <= 0 || coverage < o.minimumForegroundCoverage) {
          colors[idx] = 0;
          cells[idx] = null;
          continue;
        }

        const darkRatio = darkW / weight;
        const lumRange = maxLum - minLum;
        const meanLum = (0.2126 * wR + 0.7152 * wG + 0.0722 * wB) / weight / 255.0;
        const isOutline = darkW > 0 &&
          darkRatio >= o.outlineDarkRatio &&
          (lumRange >= o.outlineContrast || meanLum <= o.outlineDarkLuminance);

        let cr, cg, cb;
        if (isOutline) {
          cr = clamp8(Math.round(dR / darkW));
          cg = clamp8(Math.round(dG / darkW));
          cb = clamp8(Math.round(dB / darkW));
        } else if (o.mode === 'dominant' && touched.length > 0) {
          let bestBucket = touched[0], bestCount = -1;
          for (const bkt of touched) {
            if (hist[bkt] > bestCount) { bestCount = hist[bkt]; bestBucket = bkt; }
          }
          cr = clamp8(Math.round(sumR[bestBucket] / bestCount));
          cg = clamp8(Math.round(sumG[bestBucket] / bestCount));
          cb = clamp8(Math.round(sumB[bestBucket] / bestCount));
        } else {
          cr = clamp8(Math.round(wR / weight));
          cg = clamp8(Math.round(wG / weight));
          cb = clamp8(Math.round(wB / weight));
        }

        colors[idx] = (cr << 16) | (cg << 8) | cb;
        cells[idx] = { rgb: (cr << 16) | (cg << 8) | cb, coverage, darkRatio, luminanceRange: lumRange, isOutline };

        for (const bkt of touched) {
          hist[bkt] = 0; sumR[bkt] = 0; sumG[bkt] = 0; sumB[bkt] = 0;
        }
      }
    }
    return { colors, avgColors, cells, gridWidth: n, gridHeight: m };
  }

  function overlap(f, t, coord) {
    const a = Math.max(f, coord);
    const b = Math.min(t, coord + 1);
    const v = b - a;
    return v > 0 ? v : 0;
  }

  function clamp8(v) { return v < 0 ? 0 : v > 255 ? 255 : v; }

  // ======================================================================
  // 四、选色与映射
  // ======================================================================

  /**
   * @param {Array} cells 采样格子（null=背景）
   * @param {Array} palette [{r,g,b}] 色卡
   * @param {object} opts {gridWidth, maxColors, mode:'greedy'|'cluster', outlineWeight, distance:'oklab'|'ciede2000', allowedIndices, smoothCap}
   * @returns {{grid: Int32Array, selectedIndices: number[], meanMappingDistance: number}}
   */
  function selectAndMap(cells, palette, opts) {
    const o = Object.assign({
      maxColors: 0, mode: 'greedy', outlineWeight: 2.5,
      distance: 'oklab', allowedIndices: null, smoothCap: 48,
    }, opts || {});
    const palIdx = o.allowedIndices || palette.map((_, i) => i);
    const grid = new Int32Array(cells.length).fill(-1);
    if (palIdx.length === 0) {
      return { grid, selectedIndices: [], meanMappingDistance: 0 };
    }

    // 预计算色卡色空间（按距离模式）
    const distFn = o.distance === 'ciede2000' ? ciede2000 : oklabDistance;
    const palLab = palIdx.map((j) => {
      const e = palette[j];
      return o.distance === 'ciede2000'
        ? rgbToLab(e.r, e.g, e.b)
        : srgbToOklab(e.r, e.g, e.b);
    });

    if (o.mode === 'cluster') return clusterThenSnap(cells, palette, palIdx, palLab, grid, distFn, o);

    // —— fixed-palette-greedy ——
    // ① 按 RGB 聚合（覆盖度加权，轮廓 ×outlineWeight）
    const weightByRgb = new Map();
    const cellByRgb = new Map();
    for (let i = 0; i < cells.length; i++) {
      const c = cells[i];
      if (!c) continue;
      const wgt = c.coverage * (c.isOutline ? o.outlineWeight : 1.0);
      weightByRgb.set(c.rgb, (weightByRgb.get(c.rgb) || 0) + wgt);
      if (!cellByRgb.has(c.rgb)) cellByRgb.set(c.rgb, i);
    }
    if (weightByRgb.size === 0) {
      return { grid, selectedIndices: [], meanMappingDistance: 0 };
    }

    let distinct = [...weightByRgb.keys()];
    // 大图保护：distinct 过多时按权重保留 top-K（贪心质量影响可忽略）
    const MAX_DISTINCT = 1500;
    if (distinct.length > MAX_DISTINCT) {
      distinct = distinct
        .map((rgb) => [rgb, weightByRgb.get(rgb)])
        .sort((a, b) => b[1] - a[1])
        .slice(0, MAX_DISTINCT)
        .map((p) => p[0]);
    }
    const weights = distinct.map((k) => weightByRgb.get(k));

    // 预计算 distinct 色空间 + 距离矩阵（distinct × palIdx）
    const labCache = new Map();
    function labOfRgb(rgb) {
      let lab = labCache.get(rgb);
      if (!lab) {
        lab = distFn === ciede2000
          ? rgbToLab((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF)
          : srgbToOklab((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
        labCache.set(rgb, lab);
      }
      return lab;
    }
    const matrix = new Float64Array(distinct.length * palIdx.length);
    for (let i = 0; i < distinct.length; i++) {
      const lab = labOfRgb(distinct[i]);
      for (let j = 0; j < palIdx.length; j++) {
        const d = distFn(lab, palLab[j]);
        matrix[i * palIdx.length + j] = d * d;
      }
    }

    const k = o.maxColors <= 0
      ? palIdx.length
      : Math.min(o.maxColors, Math.min(palIdx.length, distinct.length));

    // ② 加权第一选：最近色按权重投票
    const vote = new Float64Array(palIdx.length);
    const acc = new Float64Array(palIdx.length);
    for (let i = 0; i < distinct.length; i++) {
      let bestJ = 0, bestD = Infinity;
      for (let j = 0; j < palIdx.length; j++) {
        const d = matrix[i * palIdx.length + j];
        if (d < bestD) { bestD = d; bestJ = j; }
      }
      vote[bestJ] += weights[i];
      acc[bestJ] += matrix[i * palIdx.length + bestJ] * weights[i];
    }
    let firstPick = 0;
    for (let j = 1; j < palIdx.length; j++) {
      if (vote[j] > vote[firstPick] || (vote[j] === vote[firstPick] && acc[j] < acc[firstPick])) {
        firstPick = j;
      }
    }

    const selected = [palIdx[firstPick]];
    const selectedSet = new Set([palIdx[firstPick]]);
    const best = new Float64Array(distinct.length);
    for (let i = 0; i < distinct.length; i++) best[i] = matrix[i * palIdx.length + firstPick];

    while (selected.length < k) {
      let bestJ = -1, bestGain = 0;
      for (let j = 0; j < palIdx.length; j++) {
        if (selectedSet.has(palIdx[j])) continue;
        let gain = 0;
        for (let i = 0; i < distinct.length; i++) {
          const u = best[i] - matrix[i * palIdx.length + j];
          if (u > 0) gain += u * weights[i];
        }
        if (gain > bestGain) { bestGain = gain; bestJ = j; }
      }
      if (bestJ < 0 || bestGain <= 1e-9) break;
      selected.push(palIdx[bestJ]);
      selectedSet.add(palIdx[bestJ]);
      for (let i = 0; i < distinct.length; i++) {
        const d = matrix[i * palIdx.length + bestJ];
        if (d < best[i]) best[i] = d;
      }
    }

    // ③ 映射：每格 → 选中色中最近者
    const selLabs = selected.map((j) => {
      const e = palette[j];
      return distFn === ciede2000
        ? rgbToLab(e.r, e.g, e.b)
        : srgbToOklab(e.r, e.g, e.b);
    });
    return mapCells(cells, palette, selected, selLabs, labCache, distFn, grid);
  }

  /** 每格映射到 selected 中最近色，并统计平均映射色差 */
  function mapCells(cells, palette, selected, selLabs, labCache, distFn, grid) {
    let sum = 0, total = 0;
    for (let i = 0; i < cells.length; i++) {
      const c = cells[i];
      if (!c) continue;
      let bestJ = 0, bestD = Infinity;
      for (let si = 0; si < selected.length; si++) {
        const d = distFn(cellLab(c.rgb, distFn, labCache), selLabs[si]);
        if (d < bestD) { bestD = d; bestJ = selected[si]; }
      }
      grid[i] = bestJ;
      const w = Math.max(0.01, c.coverage);
      sum += bestD * w;
      total += w;
    }
    const meanMappingDistance = total > 0 ? sum / total : 0;
    return { grid, selectedIndices: selected, meanMappingDistance };
  }

  function cellLab(rgb, distFn, cache) {
    let lab = cache.get(rgb);
    if (!lab) {
      lab = distFn === ciede2000
        ? rgbToLab((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF)
        : srgbToOklab((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
      cache.set(rgb, lab);
    }
    return lab;
  }

  /** cluster-then-snap：加权 k-means（CIELAB）→ 吸附色卡（平滑自然档） */
  function clusterThenSnap(cells, palette, palIdx, palLab, grid, distFn, o) {
    const pts = [];
    for (let i = 0; i < cells.length; i++) {
      const c = cells[i];
      if (!c) continue;
      pts.push({
        index: i,
        lab: rgbToLab((c.rgb >> 16) & 0xFF, (c.rgb >> 8) & 0xFF, c.rgb & 0xFF),
        weight: Math.max(0.01, c.coverage) * (c.isOutline ? o.outlineWeight : 1.0),
        isOutline: c.isOutline,
      });
    }
    if (pts.length === 0) return { grid, selectedIndices: [], meanMappingDistance: 0 };

    const k = o.maxColors <= 0
      ? Math.min(o.smoothCap, palIdx.length, pts.length)
      : Math.min(o.maxColors, Math.min(palIdx.length, pts.length));

    // 种子：最暗起步（轮廓优先），随后最远点采样（加权）
    const seeds = [];
    const pool = pts.filter((p) => p.isOutline);
    const firstPool = pool.length ? pool : pts;
    let first = firstPool[0];
    for (const p of firstPool) if (p.lab.l < first.lab.l) first = p;
    seeds.push(first.lab);
    while (seeds.length < k) {
      let pick = null, bestScore = 0;
      for (const p of pts) {
        let minD2 = Infinity;
        for (const s of seeds) {
          const d2 = distSq(p.lab, s);
          if (d2 < minD2) minD2 = d2;
        }
        const score = minD2 * p.weight;
        if (score > bestScore) { bestScore = score; pick = p; }
      }
      if (!pick || bestScore <= 1e-12) break;
      seeds.push(pick.lab);
    }

    // 加权 Lloyd（≤12 迭代）
    const centroids = seeds.slice();
    for (let iter = 0; iter < 12; iter++) {
      const accL = new Float64Array(centroids.length);
      const accA = new Float64Array(centroids.length);
      const accB = new Float64Array(centroids.length);
      const accW = new Float64Array(centroids.length);
      for (const p of pts) {
        let j = 0, minD2 = Infinity;
        for (let c = 0; c < centroids.length; c++) {
          const d2 = distSq(p.lab, centroids[c]);
          if (d2 < minD2) { minD2 = d2; j = c; }
        }
        accL[j] += p.lab.l * p.weight;
        accA[j] += p.lab.a * p.weight;
        accB[j] += p.lab.b * p.weight;
        accW[j] += p.weight;
      }
      let maxShift = 0;
      for (let c = 0; c < centroids.length; c++) {
        if (accW[c] === 0) continue;
        const nl = accL[c] / accW[c], na = accA[c] / accW[c], nb = accB[c] / accW[c];
        maxShift = Math.max(maxShift, distSq(centroids[c], { l: nl, a: na, b: nb }));
        centroids[c] = { l: nl, a: na, b: nb };
      }
      if (maxShift < 1e-4) break;
    }

    // 簇中心 → 色卡吸附（CIELAB 欧氏最近，聚类空间一致）
    const snapped = [];
    const snappedSet = new Set();
    for (const c of centroids) {
      let bestJ = 0, bestD = Infinity;
      for (let j = 0; j < palIdx.length; j++) {
        const e = palette[palIdx[j]];
        const d2 = distSq(c, rgbToLab(e.r, e.g, e.b));
        if (d2 < bestD) { bestD = d2; bestJ = j; }
      }
      const idx = palIdx[bestJ];
      if (!snappedSet.has(idx)) { snappedSet.add(idx); snapped.push(idx); }
    }
    if (snapped.length === 0) return { grid, selectedIndices: [], meanMappingDistance: 0 };

    // 轮廓格 → 最暗被选色（CIELAB L）
    let darkest = snapped[0];
    let darkestL = rgbToLab(palette[darkest].r, palette[darkest].g, palette[darkest].b).l;
    for (const s of snapped) {
      const ls = rgbToLab(palette[s].r, palette[s].g, palette[s].b).l;
      if (ls < darkestL) { darkest = s; darkestL = ls; }
    }

    // 每格用「感知距离」映射到被选色（RGB 源，与其它预设一致）
    function labOfRgb(rgb) {
      const r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF;
      return distFn === ciede2000 ? rgbToLab(r, g, b) : srgbToOklab(r, g, b);
    }
    let sum = 0, total = 0;
    for (const p of pts) {
      let idx;
      if (p.isOutline) {
        idx = darkest;
      } else {
        let j = 0, bestD = Infinity;
        const lab = labOfRgb(cells[p.index].rgb);
        for (let c = 0; c < snapped.length; c++) {
          const e = palette[snapped[c]];
          const d = distFn(lab, labOfRgb((e.r << 16) | (e.g << 8) | e.b));
          if (d < bestD) { bestD = d; j = c; }
        }
        idx = snapped[j];
      }
      grid[p.index] = idx;
      const w = Math.max(0.01, cells[p.index].coverage);
      const d = distFn(labOfRgb(cells[p.index].rgb), labOfRgb((palette[idx].r << 16) | (palette[idx].g << 8) | palette[idx].b));
      sum += d * w;
      total += w;
    }
    return { grid, selectedIndices: snapped, meanMappingDistance: total > 0 ? sum / total : 0 };
  }

  function distSq(a, b) {
    const dl = a.l - b.l, da = a.a - b.a, db = a.b - b.b;
    return dl * dl + da * da + db * db;
  }

  // ======================================================================
  // 五、抖动（Floyd–Steinberg，蛇形扫描，跳过背景/轮廓格）
  // ======================================================================

  function dither(grid, cells, colors, palette, opts) {
    const o = Object.assign({ distance: 'oklab' }, opts || {});
    const n = o.gridWidth, m = o.gridHeight;
    const distFn = o.distance === 'ciede2000' ? ciede2000 : oklabDistance;
    const errR = new Float64Array(n * m);
    const errG = new Float64Array(n * m);
    const errB = new Float64Array(n * m);

    function labOf(e, mode) {
      return mode === 'ciede2000'
        ? rgbToLab(e.r, e.g, e.b)
        : srgbToOklab(e.r, e.g, e.b);
    }

    for (let y = 0; y < m; y++) {
      if (y % 2 === 0) {
        for (let x = 0; x < n; x++) visit(x, y, 1);
      } else {
        for (let x = n - 1; x >= 0; x--) visit(x, y, -1);
      }
    }

    function visit(x, y, dir) {
      const i = y * n + x;
      const c = cells[i];
      if (!c || c.isOutline) return; // 背景/轮廓不抖动
      const src = colors[i];
      let r = ((src >> 16) & 0xFF) + errR[i];
      let g = ((src >> 8) & 0xFF) + errG[i];
      let b = (src & 0xFF) + errB[i];
      r = r < 0 ? 0 : r > 255 ? 255 : r;
      g = g < 0 ? 0 : g > 255 ? 255 : g;
      b = b < 0 ? 0 : b > 255 ? 255 : b;

      // 映射到最近色
      let bestJ = 0, bestD = Infinity;
      const lab = labOf({ r, g, b }, o.distance);
      for (let j = 0; j < palette.length; j++) {
        const d = distFn(lab, labOf(palette[j], o.distance));
        if (d < bestD) { bestD = d; bestJ = j; }
      }
      grid[i] = bestJ;
      const pe = palette[bestJ];
      const er = r - pe.r, eg = g - pe.g, eb = b - pe.b;

      // 误差扩散（仅扩散到有效格）
      const coords = dir > 0
        ? [[x + 1, y, 7 / 16], [x - 1, y + 1, 3 / 16], [x, y + 1, 5 / 16], [x + 1, y + 1, 1 / 16]]
        : [[x - 1, y, 7 / 16], [x + 1, y + 1, 3 / 16], [x, y + 1, 5 / 16], [x - 1, y + 1, 1 / 16]];
      for (const [nx, ny, k] of coords) {
        if (nx < 0 || ny < 0 || nx >= n || ny >= m) continue;
        const ni = ny * n + nx;
        const nc = cells[ni];
        if (!nc || nc.isOutline) continue;
        errR[ni] += er * k;
        errG[ni] += eg * k;
        errB[ni] += eb * k;
      }
    }
  }

  // ======================================================================
  // 六、邻域多数表决清理
  // ======================================================================

  function cleanup(grid, cells, opts) {
    const o = Object.assign({ minNeighbors: 4, iterations: 2, gridWidth: 0 }, opts || {});
    const n = o.gridWidth, m = cells.length / n;
    for (let iter = 0; iter < o.iterations; iter++) {
      const copy = Int32Array.from(grid);
      for (let y = 0; y < m; y++) {
        for (let x = 0; x < n; x++) {
          const i = y * n + x;
          if (grid[i] < 0) continue;
          const c = cells[i];
          if (c && c.isOutline) continue;
          const counts = new Map();
          for (let dy = -1; dy <= 1; dy++) {
            for (let dx = -1; dx <= 1; dx++) {
              if (dx === 0 && dy === 0) continue;
              const nx = x + dx, ny = y + dy;
              if (nx < 0 || ny < 0 || nx >= n || ny >= m) continue;
              const ni = ny * n + nx;
              const v = grid[ni];
              if (v < 0) continue;
              counts.set(v, (counts.get(v) || 0) + 1);
            }
          }
          const own = grid[i];
          const ownCount = counts.get(own) || 0;
          if (ownCount >= o.minNeighbors) continue;
          // 找邻域众数
          let mode = -1, modeCount = 0;
          for (const [v, cnt] of counts) {
            if (cnt > modeCount) { modeCount = cnt; mode = v; }
          }
          if (mode >= 0 && mode !== own && modeCount >= o.minNeighbors) {
            copy[i] = mode;
          }
        }
      }
      grid.set(copy);
    }
  }

  // ======================================================================
  // 动漫图预处理：保边色彩增强 + 线稿存活
  // ======================================================================
  // AI 生成的动漫图通常有很细的深色线稿、眼睛高光与大量相近色块。普通
  // 线性缩小会平均掉这些关键信号。这里不重绘原图，而是在分析分辨率上用
  // 局部对比度控制锐化强度，让强边缘在后续采样中仍然可见。
  function animeEnhance(rgba, w, h) {
    const out = new Uint8ClampedArray(rgba);
    const lum = new Float32Array(w * h);
    for (let i = 0; i < w * h; i++) {
      const p = i * 4;
      lum[i] = 0.2126 * rgba[p] + 0.7152 * rgba[p + 1] + 0.0722 * rgba[p + 2];
    }
    for (let y = 1; y < h - 1; y++) {
      for (let x = 1; x < w - 1; x++) {
        const i = y * w + x;
        const p = i * 4;
        if (rgba[p + 3] === 0) continue;
        let sumR = 0, sumG = 0, sumB = 0, minL = 255, maxL = 0;
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            const q = ((y + dy) * w + x + dx) * 4;
            sumR += rgba[q]; sumG += rgba[q + 1]; sumB += rgba[q + 2];
            const l = lum[(y + dy) * w + x + dx];
            minL = Math.min(minL, l); maxL = Math.max(maxL, l);
          }
        }
        const edge = Math.max(0, Math.min(1, (maxL - minL - 22) / 95));
        const blurR = sumR / 9, blurG = sumG / 9, blurB = sumB / 9;
        const base = lum[i];
        const amount = 0.12 + edge * 0.58;
        const saturation = 1.03 + edge * 0.10;
        const apply = (value, blur) => {
          const sharpened = value + (value - blur) * amount;
          return Math.max(0, Math.min(255, base + (sharpened - base) * saturation));
        };
        out[p] = apply(rgba[p], blurR);
        out[p + 1] = apply(rgba[p + 1], blurG);
        out[p + 2] = apply(rgba[p + 2], blurB);
      }
    }
    return out;
  }

  /** 将面积不超过 maxSize 的同色连通域并入相邻主色，去除压缩噪点。 */
  function mergeSmallRegions(grid, width, height, maxSize) {
    if (!maxSize || maxSize < 1) return 0;
    let changed = 0;
    for (let pass = 0; pass < 3; pass++) {
      const seen = new Uint8Array(grid.length);
      const replacements = [];
      for (let i = 0; i < grid.length; i++) {
        if (seen[i] || grid[i] < 0) continue;
        const color = grid[i];
        const cells = [i]; seen[i] = 1;
        for (let head = 0; head < cells.length; head++) {
          const cur = cells[head], x = cur % width, y = Math.floor(cur / width);
          for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            const nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
            const ni = ny * width + nx;
            if (!seen[ni] && grid[ni] === color) { seen[ni] = 1; cells.push(ni); }
          }
        }
        if (cells.length > maxSize) continue;
        const neighborCounts = new Map();
        for (const cur of cells) {
          const x = cur % width, y = Math.floor(cur / width);
          for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
            if (!dx && !dy) continue;
            const nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
            const v = grid[ny * width + nx];
            if (v >= 0 && v !== color) neighborCounts.set(v, (neighborCounts.get(v) || 0) + 1);
          }
        }
        let best = -1, bestCount = 0;
        for (const [candidate, count] of neighborCounts) {
          if (count > bestCount) { best = candidate; bestCount = count; }
        }
        if (best >= 0) replacements.push([cells, best]);
      }
      if (!replacements.length) break;
      for (const [cells, color] of replacements) for (const i of cells) {
        if (grid[i] !== color) { grid[i] = color; changed++; }
      }
    }
    return changed;
  }

  // ======================================================================
  // 六点五、主体取景（背景检测后的安全裁切）
  // ======================================================================

  /**
   * 从前景连通块中推断主要角色的取景框。
   *
   * 这不是把背景简单设为透明：先找到主体，再让主体占据合理画幅。
   * 小而贴近主体的配件会合并；远处水印、字幕和零散噪点不会拉大画面。
   */
  function findSubjectFrame(backgroundMask, w, h) {
    if (!backgroundMask) return null;
    const total = w * h;
    const seen = new Uint8Array(total);
    const components = [];
    const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]];

    for (let start = 0; start < total; start++) {
      if (backgroundMask[start] || seen[start]) continue;
      const queue = [start];
      seen[start] = 1;
      let head = 0, area = 0, left = w, right = 0, top = h, bottom = 0;
      while (head < queue.length) {
        const cur = queue[head++];
        const x = cur % w, y = Math.floor(cur / w);
        area++;
        if (x < left) left = x; if (x > right) right = x;
        if (y < top) top = y; if (y > bottom) bottom = y;
        for (const [dx, dy] of dirs) {
          const nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          const ni = ny * w + nx;
          if (!backgroundMask[ni] && !seen[ni]) { seen[ni] = 1; queue.push(ni); }
        }
      }
      components.push({ area, left, right, top, bottom });
    }
    if (!components.length) return null;

    // 面积优先，同时轻微偏向画面中心，减少把边缘字幕当作主体的概率。
    const diagonal = Math.sqrt(w * w + h * h);
    components.sort((a, b) => score(b) - score(a));
    function score(c) {
      const cx = (c.left + c.right) / 2, cy = (c.top + c.bottom) / 2;
      const dist = Math.sqrt((cx - w / 2) ** 2 + (cy - h / 2) ** 2) / diagonal;
      return c.area * (1.12 - Math.min(.32, dist));
    }
    const main = components[0];
    if (main.area < total * .012) return null;
    let left = main.left, right = main.right, top = main.top, bottom = main.bottom;
    const minAccessoryArea = Math.max(8, total * .0015);
    const maxGap = Math.max(w, h) * .055;

    // 合并角色身体、发饰等靠近主块的独立部件。
    for (const c of components.slice(1)) {
      if (c.area < minAccessoryArea) continue;
      const gapX = c.left > right ? c.left - right - 1 : left > c.right ? left - c.right - 1 : 0;
      const gapY = c.top > bottom ? c.top - bottom - 1 : top > c.bottom ? top - c.bottom - 1 : 0;
      if (Math.sqrt(gapX * gapX + gapY * gapY) > maxGap) continue;
      left = Math.min(left, c.left); right = Math.max(right, c.right);
      top = Math.min(top, c.top); bottom = Math.max(bottom, c.bottom);
    }

    const pad = Math.max(4, Math.round(Math.max(right - left + 1, bottom - top + 1) * .09));
    left = Math.max(0, left - pad); right = Math.min(w - 1, right + pad);
    top = Math.max(0, top - pad); bottom = Math.min(h - 1, bottom + pad);
    const frameArea = (right - left + 1) * (bottom - top + 1);
    if (frameArea > total * .94) return null;
    return { left, top, width: right - left + 1, height: bottom - top + 1 };
  }

  function cropToFrame(rgba, backgroundMask, w, h, frame) {
    const data = new Uint8ClampedArray(frame.width * frame.height * 4);
    const mask = backgroundMask ? new Uint8Array(frame.width * frame.height) : null;
    let foreground = 0;
    for (let y = 0; y < frame.height; y++) {
      const srcStart = ((frame.top + y) * w + frame.left);
      const dstStart = y * frame.width;
      data.set(rgba.subarray(srcStart * 4, (srcStart + frame.width) * 4), dstStart * 4);
      if (mask) {
        mask.set(backgroundMask.subarray(srcStart, srcStart + frame.width), dstStart);
        for (let x = 0; x < frame.width; x++) if (!mask[dstStart + x]) foreground++;
      }
    }
    return {
      rgba: data, mask, width: frame.width, height: frame.height,
      foregroundCoverage: foreground / (frame.width * frame.height),
    };
  }

  // ======================================================================
  // 六点六、视觉主体取景（没有纯色背景时的保守兜底）
  // ======================================================================

  /**
   * 在没有可靠背景蒙版时，寻找「成片的角色色彩」而不是整张图的最大轮廓。
   *
   * 漫画截图里常见的大对白框是白底 + 黑线；把它当作前景会吞掉角色。
   * 因此这里刻意只以中高饱和度的连续区域建立候选，并只合并靠近它的
   * 发饰、衣服等区域。它是保守回退：信心不足时返回 null，保持原图，
   * 绝不把一张普通照片随意裁掉。
   */
  function findVisualSubjectFrame(rgba, w, h) {
    const step = Math.max(2, Math.ceil(Math.max(w, h) / 240));
    const sw = Math.ceil(w / step), sh = Math.ceil(h / step), total = sw * sh;
    const active = new Uint8Array(total);
    const weight = new Float32Array(total);
    let totalWeight = 0;

    for (let sy = 0; sy < sh; sy++) for (let sx = 0; sx < sw; sx++) {
      const x0 = sx * step, y0 = sy * step;
      const x1 = Math.min(w, x0 + step), y1 = Math.min(h, y0 + step);
      let score = 0, count = 0;
      for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
        const o = (y * w + x) * 4;
        if (rgba[o + 3] < 16) continue;
        const r = rgba[o], g = rgba[o + 1], b = rgba[o + 2];
        const hi = Math.max(r, g, b), lo = Math.min(r, g, b);
        const sat = hi ? (hi - lo) / hi : 0;
        const lum = (r * 0.2126 + g * 0.7152 + b * 0.0722) / 255;
        // 纯白对白框、灰黑文字的 score 接近 0；角色头发、服装的颜色保留。
        // 阈值故意比一般“显著性检测”更高：浅蓝/米白漫画底色不能占用角色框。
        if (sat > .20 && lum > .08 && lum < .93) {
          score += (sat - .17) * (0.55 + 0.45 * (1 - Math.abs(lum - .56)));
        }
        count++;
      }
      const i = sy * sw + sx;
      const v = count ? score / count : 0;
      weight[i] = v;
      // 低阈值先连通，最终再按色彩总量和集中度做安全把关。
      if (v > .070) { active[i] = 1; totalWeight += v; }
    }
    if (totalWeight <= 0) return null;

    const seen = new Uint8Array(total), components = [];
    const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]];
    for (let start = 0; start < total; start++) {
      if (!active[start] || seen[start]) continue;
      const q = [start]; seen[start] = 1;
      let head = 0, area = 0, mass = 0, left = sw, right = 0, top = sh, bottom = 0;
      while (head < q.length) {
        const cur = q[head++], x = cur % sw, y = (cur / sw) | 0;
        area++; mass += weight[cur];
        if (x < left) left = x; if (x > right) right = x;
        if (y < top) top = y; if (y > bottom) bottom = y;
        for (const d of dirs) {
          const nx = x + d[0], ny = y + d[1];
          if (nx < 0 || ny < 0 || nx >= sw || ny >= sh) continue;
          const ni = ny * sw + nx;
          if (active[ni] && !seen[ni]) { seen[ni] = 1; q.push(ni); }
        }
      }
      if (area >= Math.max(4, total * .00035)) components.push({ area, mass, left, right, top, bottom });
    }
    if (!components.length) return null;

    const diag = Math.sqrt(sw * sw + sh * sh);
    function score(c) {
      const cx = (c.left + c.right) / 2, cy = (c.top + c.bottom) / 2;
      const dist = Math.sqrt((cx - sw / 2) ** 2 + (cy - sh / 2) ** 2) / diag;
      return c.mass * (1.08 - Math.min(.28, dist));
    }
    components.sort((a, b) => score(b) - score(a));
    const main = components[0];
    // 没有足够的色彩证据，不擅自裁切。例如灰阶照片或高饱和背景图。
    if (main.mass < totalWeight * .10 || main.area < total * .002) return null;

    let left = main.left, right = main.right, top = main.top, bottom = main.bottom;
    const maxGap = Math.max(sw, sh) * .085;
    for (const c of components.slice(1)) {
      // 大块独立内容即使碰到角色（对白气泡的尾巴很常见）也不能并入。
      // 真正的发饰、衣摆通常只是主体色块的一小部分，会由外扩留白保住。
      if (c.area > main.area * .060 || c.mass > main.mass * .075) continue;
      if (c.mass < main.mass * .028) continue;
      const gapX = c.left > right ? c.left - right - 1 : left > c.right ? left - c.right - 1 : 0;
      const gapY = c.top > bottom ? c.top - bottom - 1 : top > c.bottom ? top - c.bottom - 1 : 0;
      if (Math.hypot(gapX, gapY) > maxGap) continue;
      left = Math.min(left, c.left); right = Math.max(right, c.right);
      top = Math.min(top, c.top); bottom = Math.max(bottom, c.bottom);
    }

    let l = Math.max(0, left * step), r = Math.min(w, (right + 1) * step);
    let t = Math.max(0, top * step), b = Math.min(h, (bottom + 1) * step);
    const pad = Math.max(8, Math.round(Math.max(r - l, b - t) * .14));
    l = Math.max(0, l - pad); r = Math.min(w, r + pad);
    t = Math.max(0, t - pad); b = Math.min(h, b + pad);

    // 保持原始宽高比；app 已在裁切前决定网格高宽，不能让角色被二次拉伸。
    const ratio = w / h;
    let fw = r - l, fh = b - t;
    if (fw / fh < ratio) {
      const target = Math.min(w, fh * ratio), extra = target - fw;
      l = Math.max(0, l - extra / 2); r = Math.min(w, l + target); l = Math.max(0, r - target);
    } else {
      const target = Math.min(h, fw / ratio), extra = target - fh;
      t = Math.max(0, t - extra / 2); b = Math.min(h, t + target); t = Math.max(0, b - target);
    }
    l = Math.floor(l); t = Math.floor(t); r = Math.ceil(r); b = Math.ceil(b);
    const area = (r - l) * (b - t);
    if (area > w * h * .86 || r - l < 24 || b - t < 24) return null;
    return { left: l, top: t, width: r - l, height: b - t, visual: true };
  }

  // ======================================================================
  // 七、主流程
  // ======================================================================

  /**
   * @param {object} input {
   *   imageData: {data: Uint8ClampedArray, width, height},   // 分析图（≤1024）
   *   gridWidth, gridHeight,
   *   preset: 'anime'|'simplified'|'standard'|'detailed'|'smooth',
   *   palette: [{code, r, g, b, name?, productCode?}],
   *   removeBackground: boolean,
   *   distance: 'oklab'|'ciede2000' | null(按预设),
   *   maxColors: number | null(按预设),
   *   seedDeltaE, fillDeltaE
   * }
   * @returns result
   */
  function convert(input) {
    const img = input.imageData;
    const sourceRgba = img.data;
    const w = img.width, h = img.height;

    const presetDefs = {
      anime:      { bits: 5, mode: 'dominant', maxColors: 18, distance: 'ciede2000', dither: false, cleanup: 3, region: 2, anime: true },
      simplified: { bits: 4, mode: 'dominant', maxColors: 8, distance: 'oklab', dither: false, cleanup: 4, region: 3 },
      standard:   { bits: 4, mode: 'dominant', maxColors: 0, distance: 'oklab', dither: false, cleanup: 4 },
      detailed:   { bits: 5, mode: 'dominant', maxColors: 16, distance: 'ciede2000', dither: true, cleanup: 7 },
      smooth:     { bits: 4, mode: 'average', maxColors: 0, distance: 'oklab', dither: false, cleanup: 0, selection: 'cluster' },
    };
    const p = presetDefs[input.preset] || presetDefs.standard;
    const rgba = p.anime ? animeEnhance(sourceRgba, w, h) : sourceRgba;
    const distance = input.distance || p.distance;
    const maxColors = input.maxColors != null ? input.maxColors : p.maxColors;

    // ① 背景检测（像素级，映射前）。AI mask 只参与取景，默认不直接镂空。
    let bg = { mask: null, detected: false, confidence: 0 };
    const semanticMask = input.subjectMask && input.subjectMask.length === w * h ? input.subjectMask : null;
    if (semanticMask) {
      bg = { mask: semanticMask, detected: true, confidence: 1, semantic: true };
    } else if (input.removeBackground) {
      bg = detectBackground(rgba, w, h, {
        seedDeltaE: input.seedDeltaE || 8,
        fillDeltaE: input.fillDeltaE || 14,
      });
    }

    // ② 智能取景：优先使用可靠背景蒙版；没有蒙版时再用保守的视觉主体回退。
    // 只有裁切后的前景覆盖足够时才真正清背景；否则保留背景，避免空洞图纸。
    let workRgba = rgba, workMask = bg.detected ? bg.mask : null, workW = w, workH = h;
    let frame = null, backgroundApplied = !!workMask && !input.frameOnly;
    if (input.autoFrameSubject) {
      // 角色分割很擅长找出人物，但漫画对白框偶尔会和线稿连成一个前景块。
      // 有足够色彩线索时，用视觉角色框把对白排除；色彩线索不足再回退 AI 蒙版。
      const visualFrame = findVisualSubjectFrame(rgba, w, h);
      frame = visualFrame || (workMask ? findSubjectFrame(workMask, w, h) : null);
      if (frame) {
        const cropped = cropToFrame(workRgba, workMask, w, h, frame);
        workRgba = cropped.rgba; workMask = cropped.mask; workW = cropped.width; workH = cropped.height;
        // 主体在框内仍过稀疏，说明 flood-fill 不可靠或图源并非纯背景。
        if (cropped.foregroundCoverage < .28) { workMask = null; backgroundApplied = false; }
      }
    }

    // ③ 网格采样
    const sampled = sampleGrid(workRgba, workW, workH, {
      gridWidth: input.gridWidth,
      gridHeight: input.gridHeight,
      mode: p.mode,
      bits: p.bits,
      backgroundMask: backgroundApplied ? workMask : null,
    });

    // ④ 选色 + 映射
    const selectionMode = p.selection === 'cluster' ? 'cluster' : 'greedy';
    const sel = selectAndMap(sampled.cells, input.palette, {
      gridWidth: input.gridWidth,
      maxColors,
      mode: selectionMode,
      distance,
    });

    // ⑤ 抖动（细腻档）
    if (p.dither && maxColors > 0) {
      // 只对选中色抖动
      const usedPalette = sel.selectedIndices.map((j) => input.palette[j]);
      const usedMap = new Map(sel.selectedIndices.map((j, k) => [j, k]));
      const gridCopy = new Int32Array(sel.grid.length);
      for (let i = 0; i < sel.grid.length; i++) {
        const v = sel.grid[i];
        gridCopy[i] = v < 0 ? -1 : usedMap.get(v) ?? 0;
      }
      dither(gridCopy, sampled.cells, sampled.colors, usedPalette, {
        distance, gridWidth: input.gridWidth, gridHeight: input.gridHeight,
      });
      for (let i = 0; i < gridCopy.length; i++) {
        const v = gridCopy[i];
        sel.grid[i] = v < 0 ? -1 : sel.selectedIndices[v];
      }
    }

    // ⑥ 清理（多数表决）
    if (p.cleanup > 0) {
      cleanup(sel.grid, sampled.cells, {
        minNeighbors: p.cleanup, iterations: 2, gridWidth: input.gridWidth,
      });
    }
    if (p.region) mergeSmallRegions(sel.grid, input.gridWidth, input.gridHeight, p.region);

    // ⑦ 统计 BOM / 诊断
    return buildResult(sel, sampled, input, bg, distance, frame, backgroundApplied);
  }

  function buildResult(sel, sampled, input, bg, distance, frame, backgroundApplied) {
    const grid = sel.grid;
    const n = input.gridWidth, m = input.gridHeight;
    const palette = input.palette;
    const counts = new Map();
    for (const v of grid) {
      if (v < 0) continue;
      counts.set(v, (counts.get(v) || 0) + 1);
    }
    const bom = [];
    for (const [idx, count] of counts) {
      const e = palette[idx];
      bom.push({ code: e.code, name: e.name || '', r: e.r, g: e.g, b: e.b, color: (e.r << 16) | (e.g << 8) | e.b, count });
    }
    bom.sort((a, b) => b.count - a.count);

    // 稀有色（用量 ≤2）与孤立单格区域数
    let rareColorCount = 0;
    for (const e of bom) if (e.count <= 2) rareColorCount++;
    const singleCellRegionCount = countSingleCellRegions(grid, n, m);

    let totalBeads = 0;
    for (const e of bom) totalBeads += e.count;

    return {
      grid,
      size: n,
      height: m,
      selectedIndices: sel.selectedIndices,
      meanMappingDistance: sel.meanMappingDistance,
      backgroundDetected: backgroundApplied,
      backgroundConfidence: bg.confidence,
      autoFramed: !!frame,
      semanticFrame: !!bg.semantic && !!frame,
      frame,
      bom,
      totalBeads,
      colorCount: bom.length,
      rareColorCount,
      singleCellRegionCount,
      avgColors: sampled.avgColors,
    };
  }

  /** 孤立单格区域计数（上下左右均无同色邻格） */
  function countSingleCellRegions(grid, n, m) {
    let count = 0;
    for (let y = 0; y < m; y++) {
      for (let x = 0; x < n; x++) {
        const i = y * n + x;
        const v = grid[i];
        if (v < 0) continue;
        let alone = true;
        for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
          const nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= n || ny >= m) continue;
          if (grid[ny * n + nx] === v) { alone = false; break; }
        }
        if (alone) count++;
      }
    }
    return count;
  }

  /** 预设元信息（供 UI 展示） */
  const PRESETS = [
    { id: 'anime', label: '✦ 动漫增强', sub: '线稿五官 · 默认推荐', maxColors: 18 },
    { id: 'simplified', label: '⚡ 精简', sub: '8 色内 · 干净利落', maxColors: 8 },
    { id: 'standard', label: '✨ 标准', sub: '均衡 · 默认推荐', maxColors: 0 },
    { id: 'detailed', label: '🔬 细腻', sub: 'CIEDE2000 最准', maxColors: 16 },
    { id: 'smooth', label: '🌊 平滑', sub: '渐变过渡自然', maxColors: 0 },
  ];

  global.PixelEngine = {
    srgbToOklab, oklabDistance, rgbToLab, ciede2000,
    detectBackground, findSubjectFrame, findVisualSubjectFrame, sampleGrid, selectAndMap, dither, cleanup, mergeSmallRegions, animeEnhance, convert,
    PRESETS,
  };
})(typeof self !== 'undefined' ? self : globalThis);
