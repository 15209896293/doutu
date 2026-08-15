// assets/dev-charts.js — 开发计划书图表
(function () {
  var style = getComputedStyle(document.documentElement);
  var accent = style.getPropertyValue('--accent').trim();
  var accent2 = style.getPropertyValue('--accent2').trim();
  var ink = style.getPropertyValue('--ink').trim();
  var muted = style.getPropertyValue('--muted').trim();
  var rule = style.getPropertyValue('--rule').trim();
  var bg2 = style.getPropertyValue('--bg2').trim();
  var candyY = style.getPropertyValue('--candy-y').trim();
  var candyB = style.getPropertyValue('--candy-b').trim();
  var candyP = style.getPropertyValue('--candy-p').trim();
  var candyO = style.getPropertyValue('--candy-o').trim();

  var palette = [accent, accent2, candyY, candyB, candyP];

  // --- Chart: Gantt ---
  var ganttEl = document.getElementById('chart-gantt');
  if (ganttEl) {
    var chart = echarts.init(ganttEl, null, { renderer: 'svg' });

    var categories = [
      'Phase 4 · 验证与迭代',
      'Phase 3 · 测试与上架',
      'Phase 2 · 体验打磨',
      'Phase 1 · MVP 核心开发',
      'Phase 0 · 准备阶段'
    ];

    var phases = [
      { name: '环境搭建 + 色卡整理 + 算法原型', phase: 0, start: 0, end: 1 },
      { name: '基础架构 + 导入流程', phase: 1, start: 1, end: 2 },
      { name: '算法引擎 + 一键生成', phase: 1, start: 2, end: 3 },
      { name: '预览 + BOM + 导出', phase: 1, start: 3, end: 4 },
      { name: '编辑器 + 跟做 + 历史', phase: 2, start: 4, end: 5 },
      { name: '性能优化 + 可爱系动效', phase: 2, start: 4, end: 5 },
      { name: '盲测 + APK优化 + 备案 + 上架', phase: 3, start: 5, end: 6 },
      { name: '冷启动内容准备', phase: 3, start: 5, end: 6 },
      { name: '数据回收 + 质量调优 + 迭代', phase: 4, start: 6, end: 8 }
    ];

    var data = phases.map(function (p, i) {
      return {
        name: p.name,
        value: [4 - p.phase, p.start, p.end, palette[p.phase]],
        itemStyle: { color: palette[p.phase], borderRadius: 6 }
      };
    });

    chart.setOption({
      animation: false,
      tooltip: {
        trigger: 'item',
        appendToBody: true,
        formatter: function (p) {
          var v = p.value;
          var weeks = v[1] === v[2] - 1 ? '第 ' + (v[1] + 1) + ' 周' : '第 ' + (v[1] + 1) + '-' + v[2] + ' 周';
          return '<b>' + p.name + '</b><br/>' + weeks;
        }
      },
      grid: { left: 10, right: 30, top: 10, bottom: 10, containLabel: true },
      xAxis: {
        type: 'value',
        min: 0,
        max: 8,
        interval: 1,
        name: '周',
        nameLocation: 'end',
        nameTextStyle: { color: muted, fontSize: 12 },
        axisLine: { lineStyle: { color: rule } },
        axisTick: { show: false },
        axisLabel: {
          color: ink,
          formatter: function (v) { return v === 0 ? '' : 'W' + v; }
        },
        splitLine: { lineStyle: { color: rule, type: 'dashed' } }
      },
      yAxis: {
        type: 'category',
        data: categories,
        inverse: false,
        axisLine: { lineStyle: { color: rule } },
        axisTick: { show: false },
        axisLabel: { color: ink, fontSize: 12, width: 120, overflow: 'truncate' }
      },
      series: [{
        type: 'custom',
        renderItem: function (params, api) {
          var cat = api.value(0);
          var start = api.coord([api.value(1), cat]);
          var end = api.coord([api.value(2), cat]);
          var height = api.size([0, 1])[1] * 0.5;
          return {
            type: 'rect',
            shape: {
              x: start[0],
              y: start[1] - height / 2,
              width: end[0] - start[0],
              height: height,
              r: 6
            },
            style: api.style()
          };
        },
        data: data,
        encode: { x: [1, 2], y: 0 },
        label: {
          show: true,
          position: 'insideLeft',
          color: '#fff',
          fontSize: 11,
          fontWeight: 700,
          formatter: function (p) { return p.name; },
          padding: [0, 0, 0, 6]
        }
      }]
    });
    window.addEventListener('resize', function () { chart.resize(); });
  }
})();
