// assets/charts.js — 拼豆图纸转化器方案报告图表
(function () {
  var style = getComputedStyle(document.documentElement);
  var accent = style.getPropertyValue('--accent').trim();
  var accent2 = style.getPropertyValue('--accent2').trim();
  var ink = style.getPropertyValue('--ink').trim();
  var muted = style.getPropertyValue('--muted').trim();
  var rule = style.getPropertyValue('--rule').trim();
  var bg2 = style.getPropertyValue('--bg2').trim();
  var beadY = style.getPropertyValue('--bead-y').trim();
  var beadB = style.getPropertyValue('--bead-b').trim();
  var beadP = style.getPropertyValue('--bead-p').trim();

  var baseAxis = {
    axisLine: { lineStyle: { color: rule } },
    axisTick: { show: false },
    axisLabel: { color: ink, fontFamily: 'WorkSans, "PingFang SC", "Microsoft YaHei", sans-serif' },
    splitLine: { lineStyle: { color: rule } }
  };

  // --- Chart 1: 平台热度 ---
  var heatEl = document.getElementById('chart-heat');
  if (heatEl) {
    var chart1 = echarts.init(heatEl, null, { renderer: 'svg' });
    chart1.setOption({
      animation: false,
      tooltip: {
        trigger: 'axis',
        axisPointer: { type: 'shadow' },
        appendToBody: true,
        formatter: function (p) {
          return p[0].name + '：<b>' + p[0].value + ' 亿次</b>';
        }
      },
      grid: { left: 10, right: 40, top: 20, bottom: 10, containLabel: true },
      xAxis: Object.assign({ type: 'value', name: '亿次' }, baseAxis),
      yAxis: Object.assign({
        type: 'category',
        data: ['抖音 #拼豆 播放量\n（2026-06）', '小红书 "拼豆" 话题阅读\n（2026-03）', '小红书 "我染上了拼豆" 阅读\n（2026-06）'],
        inverse: true
      }, baseAxis),
      series: [{
        type: 'bar',
        data: [
          { value: 322.7, itemStyle: { color: accent } },
          { value: 96, itemStyle: { color: accent2 } },
          { value: 91.7, itemStyle: { color: beadY } }
        ],
        barWidth: 26,
        label: {
          show: true,
          position: 'right',
          color: ink,
          fontFamily: 'PixelifySans, sans-serif',
          fontSize: 15,
          formatter: '{c} 亿'
        }
      }]
    });
    window.addEventListener('resize', function () { chart1.resize(); });
  }

  // --- Chart 2: 市场规模 ---
  var marketEl = document.getElementById('chart-market');
  if (marketEl) {
    var chart2 = echarts.init(marketEl, null, { renderer: 'svg' });
    chart2.setOption({
      animation: false,
      tooltip: {
        trigger: 'axis',
        axisPointer: { type: 'shadow' },
        appendToBody: true,
        formatter: function (p) {
          return p[0].name + '：<b>' + p[0].value + ' 亿元</b>';
        }
      },
      grid: { left: 10, right: 30, top: 20, bottom: 10, containLabel: true },
      xAxis: Object.assign({
        type: 'category',
        data: ['2024 年\n（按增速倒推）', '2025 年\n（魔镜洞察实测）', '2026 年\n（行业预测）']
      }, baseAxis),
      yAxis: Object.assign({ type: 'value', name: '亿元' }, baseAxis),
      series: [{
        type: 'bar',
        data: [
          { value: 0.29, itemStyle: { color: rule } },
          { value: 2.91, itemStyle: { color: accent } },
          { value: 10, itemStyle: { color: accent2, borderRadius: [6, 6, 0, 0] } }
        ],
        barWidth: 46,
        itemStyle: { borderRadius: [6, 6, 0, 0] },
        label: {
          show: true,
          position: 'top',
          color: ink,
          fontFamily: 'PixelifySans, sans-serif',
          fontSize: 15,
          formatter: function (p) { return p.value + ' 亿'; }
        }
      }]
    });
    window.addEventListener('resize', function () { chart2.resize(); });
  }
})();
