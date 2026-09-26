// Local-only integration fixture: a separate SFU worker, never Matrix's backend or database.
import { randomBytes, randomUUID } from "node:crypto";
import { createServer } from "node:http";
import { createServer as createPortServer } from "node:net";
import { resolve } from "node:path";
import { chromium } from "../../matrix-sfu/node_modules/playwright/index.mjs";
import { build } from "../../matrix-sfu/node_modules/esbuild/lib/main.js";
import { readConfig } from "../../matrix-sfu/src/config.ts";
import { commandSchema } from "../../matrix-sfu/src/contracts.ts";
import { Sfu } from "../../matrix-sfu/src/sfu.ts";

const portSocket = createPortServer();
await new Promise<void>((done) => portSocket.listen(0, "127.0.0.1", done));
const mediaPort = (portSocket.address() as { port: number }).port;
await new Promise<void>((done) => portSocket.close(() => done()));
const sfu = await Sfu.create(readConfig({ SFU_API_TOKEN: randomBytes(32).toString("hex"), SFU_MEDIA_PORT: String(mediaPort) }));
const roomId = randomUUID();
const native = { peerId: randomUUID(), participantId: randomUUID() };
const web = { peerId: randomUUID(), participantId: randomUUID() };
await sfu.run(() => sfu.createRoom(roomId));
for (const peer of [native, web]) await sfu.run(() => sfu.command(roomId, { type: "join", ...peer }));
const heartbeat = setInterval(() => {
  void sfu.run(() => sfu.command(roomId, {type:"heartbeat", peerIds:[native.peerId, web.peerId]}));
}, 15_000);

const source = resolve(import.meta.dirname, "../../matrix-mobile/src/modules/calls/lib/SfuAudioSession.ts");
const bundle = await build({
  stdin: {
    contents: `
      import { SfuAudioSession } from ${JSON.stringify(source)};
      const rpc = async command => {
        const response = await fetch('/command/web', {method:'POST', body:JSON.stringify(command)});
        if (!response.ok) throw new Error(await response.text());
        return response.json();
      };
      const snapshot = () => fetch('/state').then(r => r.json());
      window.ready = (async () => {
        const stream = await navigator.mediaDevices.getUserMedia({audio:true});
        const state = await snapshot();
        window.audio = new SfuAudioSession(state.id, stream, rpc, [], e => window.failure=e, () => {}, () => {});
        await window.audio.start(state);
        window.timer = setInterval(async () => window.audio.sync(await snapshot()), 250);
        window.stats = async () => [...(await window.audio.recv.getStats()).values()];
      })().catch(e => window.failure=String(e));
    `,
    resolveDir: resolve(import.meta.dirname, "../../matrix-sfu"), loader: "ts",
  }, bundle: true, format: "esm", write: false,
});
const server = createServer(async (request, response) => {
  try {
    if (request.url === "/web") {
      response.setHeader("Content-Type", "text/html");
      response.end('<script type="module" src="/web.js"></script>'); return;
    }
    if (request.url === "/web.js") {
      response.setHeader("Content-Type", "text/javascript"); response.end(bundle.outputFiles[0].text); return;
    }
    response.setHeader("Content-Type", "application/json");
    if (request.url === "/state") {
      const state = await sfu.run(() => sfu.snapshot(roomId));
      response.end(JSON.stringify({
        id: roomId, chatId: null, title: "Local native/web test", myPeerId: native.peerId,
        myStatus: "JOINED", joinedHere: true, rtpCapabilities: state.rtpCapabilities,
        participants: state.peers.map(peer => ({id:peer.participantId, name:"Test", connections:[peer]})),
      })); return;
    }
    if (request.url === "/stats") {
      response.end(JSON.stringify(await page.evaluate("window.stats ? window.stats() : []"))); return;
    }
    if (request.url?.startsWith("/command/")) {
      const peer = request.url.endsWith("native") ? native : web;
      const chunks: Buffer[] = [];
      for await (const chunk of request) chunks.push(Buffer.from(chunk));
      const command = JSON.parse(Buffer.concat(chunks).toString());
      const result = await sfu.run(() => sfu.command(roomId, commandSchema.parse({
        ...command.data, type: command.operation, peerId: peer.peerId,
      })));
      response.end(JSON.stringify(result)); return;
    }
    response.writeHead(404); response.end("{}");
  } catch (error) { response.statusCode = 400; response.end(JSON.stringify({message:String(error)})); }
});
await new Promise<void>((done) => server.listen(38761, "127.0.0.1", done));
const browser = await chromium.launch({headless:true, args:["--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream", "--autoplay-policy=no-user-gesture-required"]});
const context = await browser.newContext({permissions:["microphone"]});
const page = await context.newPage();
await page.goto("http://127.0.0.1:38761/web");
await page.evaluate("window.ready");
const failure = await page.evaluate("window.failure");
if (failure) throw new Error(String(failure));
console.log("Local SFU/browser ready on http://127.0.0.1:38761");
async function close() {
  clearInterval(heartbeat);
  await browser.close();
  server.close();
  await sfu.close();
  process.exit(0);
}
process.on("SIGINT", close);
process.on("SIGTERM", close);
