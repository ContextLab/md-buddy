import { createServer, IncomingMessage, ServerResponse } from "node:http";

interface Route {
  method: "GET" | "POST";
  path: string;
  handler: (req: IncomingMessage, res: ServerResponse) => void;
}

const routes: Route[] = [
  { method: "GET", path: "/health", handler: (_req, res) => res.end("ok") },
];

createServer((req, res) => {
  const route = routes.find((r) => r.method === req.method && r.path === req.url);
  route ? route.handler(req, res) : (res.statusCode = 404, res.end("not found"));
}).listen(8080);
