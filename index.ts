import { server as wisp } from "@mercuryworkshop/wisp-js/server";
import { createServer } from "node:http";
import { SocksClient } from "socks";
import type { Socket } from "node:net";
import type { IncomingMessage } from "node:http";

const WISP_PORT = parseInt(process.env.WISP_PORT ?? "8080");
const SOCKS_HOST = "127.0.0.1";
const SOCKS_PORT = 10001;

async function socksConnect(hostname: string, port: number): Promise<Socket> {
  const { socket } = await SocksClient.createConnection({
    proxy: { host: SOCKS_HOST, port: SOCKS_PORT, type: 5 },
    command: "connect",
    destination: { host: hostname, port },
  });
  return socket as unknown as Socket;
}

wisp.options ??= {};
wisp.options.dns_result_order = "verbatim";
wisp.options.connect = socksConnect;

const server = createServer((_req: IncomingMessage, res) => {
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("Wisp-to-Xray Bridge Active\n");
});

// wisp-js needs the raw Node upgrade event — this is the only supported API my bad
server.on("upgrade", (req, socket, head) => {
  wisp.routeRequest(req, socket, head);
});

server.listen(WISP_PORT, "127.0.0.1", () => {
  console.log(`[wisp-gate] Listening on 127.0.0.1:${WISP_PORT}`);
  console.log(`[wisp-gate] Routing via SOCKS5 → Xray @ ${SOCKS_HOST}:${SOCKS_PORT}`);
});

server.on("error", (err: Error) => {
  console.error("[wisp-gate] Fatal:", err.message);
  process.exit(1);
});