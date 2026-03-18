import { server as wisp } from "@mercuryworkshop/wisp-js/server";
import { SocksClient } from "socks";
import type { Socket } from "node:net";

const WISP_PORT = parseInt(process.env.WISP_PORT ?? "8080");
const SOCKS_HOST = "127.0.0.1";
const SOCKS_PORT = 10001;

async function socksConnect(hostname: string, port: number): Promise<Socket> {
  const { socket } = await SocksClient.createConnection({
    proxy: {
      host: SOCKS_HOST,
      port: SOCKS_PORT,
      type: 5,
    },
    command: "connect",
    destination: {
      host: hostname,
      port,
    },
  });
  return socket as unknown as Socket;
}

// Patch wisp-js: pass hostnames through verbatim, let Xray resolve DNS
wisp.options ??= {};
wisp.options.dns_result_order = "verbatim";
wisp.options.connect = socksConnect;

const server = Bun.serve({
  port: WISP_PORT,
  hostname: "127.0.0.1",

  fetch(req, server) {
    const upgraded = server.upgrade(req);
    if (upgraded) return undefined;

    // Non-WS requests — plain health check
    return new Response("Wisp-to-Xray Bridge Active\n", {
      headers: { "Content-Type": "text/plain" },
    });
  },

  websocket: {
    open(ws) {
      wisp.handleOpen(ws);
    },
    message(ws, msg) {
      wisp.handleMessage(ws, msg);
    },
    close(ws, code, reason) {
      wisp.handleClose(ws, code, reason);
    },
  },
});

console.log(`[wisp-gate] Listening on ${server.hostname}:${server.port}`);
console.log(`[wisp-gate] Routing via SOCKS5 → Xray @ ${SOCKS_HOST}:${SOCKS_PORT}`);
