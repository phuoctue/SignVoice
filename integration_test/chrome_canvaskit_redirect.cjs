// Work around Flutter 3.47.6's Windows test host rejecting canvaskit\ paths.
// With the Flutter Chrome tests loading, pass their owned debugging port and a
// loopback static server serving build/web. No SDK files or app requests change.
const port = Number(process.argv[2]);
const assets = new URL(process.argv[3]);
if (!Number.isInteger(port) || port < 1024 || port > 65535 ||
    assets.protocol !== 'http:' || assets.hostname !== '127.0.0.1') throw new Error('Loopback test ports only');
(async () => {
  const pages = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = pages.find(p => p.title === 'Flutter Test Browser Host' && new URL(p.url).hostname === 'localhost');
  if (!page) throw new Error('No owned Flutter test host');
  const socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise(resolve => socket.addEventListener('open', resolve, {once: true}));
  let sequence = 0, redirects = 0;
  const command = (method, params) => socket.send(JSON.stringify({id: ++sequence, method, params}));
  socket.addEventListener('message', async event => {
    const response = JSON.parse(event.data);
    if (response.method === 'Fetch.requestPaused') {
      const paused = response.params;
      const url = new URL(paused.request.url);
      if (url.hostname !== 'localhost' || !url.pathname.startsWith('/canvaskit/')) {
        command('Fetch.continueRequest', {requestId: paused.requestId}); return;
      }
      const asset = await fetch(assets.origin + url.pathname);
      if (!asset.ok) throw new Error('Missing local CanvasKit asset: ' + url.pathname);
      redirects++;
      command('Fetch.fulfillRequest', {requestId: paused.requestId, responseCode: 200,
        responseHeaders: [{name: 'Content-Type', value: url.pathname.endsWith('.wasm') ? 'application/wasm' : 'text/javascript'}],
        body: Buffer.from(await asset.arrayBuffer()).toString('base64')});
      console.log('Served loopback CanvasKit asset:', url.pathname);
    }
    if (response.id === 1) command('Runtime.evaluate', {expression: 'document.querySelector("iframe").contentWindow.location.reload()'});
  });
  command('Fetch.enable', {patterns: [{urlPattern: '*/canvaskit/*', requestStage: 'Request'}]});
  const timer = setTimeout(() => {console.log('CanvasKit redirects:', redirects); socket.close();}, 300000);
  socket.addEventListener('close', () => clearTimeout(timer));
})().catch(error => {console.error(error); process.exitCode = 1;});
