// 用 Chrome DevTools Protocol 驱动 headless Chrome 做「真实渲染」探针。
// 用途：Flutter Web 的 UI 尺寸无法从代码静态推断时，截图 + 像素测量来定论。
// 用法：
//   node tools/cdp_probe.mjs '<json steps>' <out.png>
// steps 为数组，支持：
//   {"nav":"http://localhost:8080/#/capture"}  导航
//   {"wait":3000}                              等待 ms
//   {"click":[x,y]}                            鼠标点击（视口坐标）
//   {"shot":"/tmp/a.png"}                      截图存盘
//   {"eval":"document.title"}                  执行 JS 并打印结果
//   {"measure":"#0395FF"}                      在视口截图里统计该颜色像素的包围盒
//   {"interceptChooser":true}                  拦截系统文件选择器（配合 Flutter Web 选图）
//   {"pickFile":"/abs/a.jpg"}                  给刚弹出的文件选择器喂一张本地图片
//   {"scroll":[x,y,deltaY]}                    在 (x,y) 处滚轮滚动（Flutter 只认真实滚轮）
// 依赖：Node >= 22（内置 WebSocket），Chrome 需已用 --remote-debugging-port=9333 启动。
import { writeFileSync } from 'node:fs';

const PORT = process.env.CDP_PORT || 9333;
const steps = JSON.parse(process.argv[2] || '[]');
const out = process.argv[3];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function target() {
  for (let i = 0; i < 40; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      const page = list.find((t) => t.type === 'page');
      if (page?.webSocketDebuggerUrl) return page;
    } catch {}
    await sleep(250);
  }
  throw new Error('CDP target not found');
}

const t = await target();
const ws = new WebSocket(t.webSocketDebuggerUrl);
await new Promise((res, rej) => {
  ws.addEventListener('open', res, { once: true });
  ws.addEventListener('error', rej, { once: true });
});

let id = 0;
const pending = new Map();
const events = []; // CDP 事件（如 Page.fileChooserOpened）
const waiters = [];
ws.addEventListener('message', (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) {
    pending.get(msg.id)(msg);
    pending.delete(msg.id);
    return;
  }
  if (msg.method) {
    events.push(msg);
    for (let i = waiters.length - 1; i >= 0; i--) {
      if (waiters[i].method === msg.method) {
        waiters[i].resolve(msg.params);
        waiters.splice(i, 1);
      }
    }
  }
});

/** 等待某个 CDP 事件（先到先取，超时报错）。 */
function waitEvent(method, timeout = 8000) {
  const hit = events.find((e) => e.method === method);
  if (hit) {
    events.splice(events.indexOf(hit), 1);
    return Promise.resolve(hit.params);
  }
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`event timeout: ${method}`)), timeout);
    waiters.push({
      method,
      resolve: (p) => {
        clearTimeout(timer);
        resolve(p);
      },
    });
  });
}
function send(method, params = {}) {
  const mid = ++id;
  ws.send(JSON.stringify({ id: mid, method, params }));
  return new Promise((res) => pending.set(mid, res));
}

await send('Page.enable');
await send('Runtime.enable');
// 视口固定 900×1000（DeviceFrame 会以 1:1 呈现 390 宽的机身内容）。
await send('Emulation.setDeviceMetricsOverride', {
  width: 900,
  height: 1000,
  deviceScaleFactor: 1,
  mobile: false,
});

async function shot(path) {
  const r = await send('Page.captureScreenshot', { format: 'png' });
  writeFileSync(path, Buffer.from(r.result.data, 'base64'));
  console.log('shot ->', path);
}

/** 统计截图里某颜色的包围盒（用于验证元素真实像素尺寸）。s.crop = [x0,y0,x1,y1] 可限定区域。 */
async function measure(hex, path, crop) {
  const r = await send('Page.captureScreenshot', { format: 'png' });
  const buf = Buffer.from(r.result.data, 'base64');
  if (path) writeFileSync(path, buf);
  // 不引第三方图像库：用 Chrome 自己解码，避免装依赖。
  const dataUrl = 'data:image/png;base64,' + buf.toString('base64');
  const [cx0, cy0, cx1, cy1] = crop ?? [0, 0, 100000, 100000];
  const expr = `
    (async () => {
      const img = new Image();
      img.src = ${JSON.stringify(dataUrl)};
      await img.decode();
      const c = document.createElement('canvas');
      c.width = img.width; c.height = img.height;
      const g = c.getContext('2d');
      g.drawImage(img, 0, 0);
      const d = g.getImageData(0, 0, c.width, c.height).data;
      const target = [${parseInt(hex.slice(1, 3), 16)}, ${parseInt(hex.slice(3, 5), 16)}, ${parseInt(hex.slice(5, 7), 16)}];
      const x0 = ${cx0}, y0 = ${cy0}, x1 = Math.min(c.width, ${cx1}), y1 = Math.min(c.height, ${cy1});
      let minX = 1e9, minY = 1e9, maxX = -1, maxY = -1, n = 0;
      const rows = {};
      for (let y = y0; y < y1; y++) {
        for (let x = x0; x < x1; x++) {
          const i = (y * c.width + x) * 4;
          if (Math.abs(d[i]-target[0])<8 && Math.abs(d[i+1]-target[1])<8 && Math.abs(d[i+2]-target[2])<8 && d[i+3]>200) {
            n++;
            rows[y] = (rows[y] || 0) + 1;
            if (x<minX)minX=x; if (x>maxX)maxX=x; if (y<minY)minY=y; if (y>maxY)maxY=y;
          }
        }
      }
      return JSON.stringify({ pixels: n, x: minX, y: minY, w: maxX-minX+1, h: maxY-minY+1,
        rowRun: Object.keys(rows).length, widestRow: Math.max(0, ...Object.values(rows)) });
    })()
  `;
  const res = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
  console.log(`measure ${hex}:`, res.result?.result?.value ?? res.result);
}

for (const s of steps) {
  if (s.nav) await send('Page.navigate', { url: s.nav });
  else if (s.reload) await send('Page.reload', { ignoreCache: true });
  else if (s.wait) await sleep(s.wait);
  else if (s.click) {
    const [x, y] = s.click;
    for (const type of ['mousePressed', 'mouseReleased']) {
      await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
      await sleep(60);
    }
  } else if (s.scroll) {
    // Flutter 的滚动靠真实滚轮事件驱动（window.scrollTo 对 canvas 无效）。
    const [x, y, dy] = s.scroll;
    await send('Input.dispatchMouseEvent', {
      type: 'mouseWheel',
      x,
      y,
      deltaX: 0,
      deltaY: dy,
    });
  } else if (s.shot) await shot(s.shot);
  else if (s.interceptChooser) {
    // Flutter Web 的「拍照」会弹系统文件选择器（headless 无法人工选图）。
    // 打开拦截后，用 DOM.setFileInputFiles 直接喂一张本地图片。
    await send('DOM.enable');
    await send('Page.setInterceptFileChooserDialog', { enabled: true });
  } else if (s.pickFile) {
    const p = await waitEvent('Page.fileChooserOpened');
    await send('DOM.setFileInputFiles', {
      files: [s.pickFile],
      backendNodeId: p.backendNodeId,
    });
    console.log('pickFile ->', s.pickFile);
  } else if (s.measure) await measure(s.measure, s.shotTo, s.crop);
  else if (s.eval) {
    const r = await send('Runtime.evaluate', { expression: s.eval, returnByValue: true });
    console.log('eval:', r.result?.result?.value);
  }
}

if (out) await shot(out);
ws.close();
process.exit(0);
