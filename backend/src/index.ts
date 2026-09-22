import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { resolve } from "node:path";
import { parseWithFallback, parseWithGemini, parseWithOpenAI } from "./ai/providers.ts";
import { ALLOWED_CATEGORIES, type ParseContext } from "./ai/types.ts";
import { ProviderError } from "./ai/types.ts";

loadEnv(resolve(process.cwd(), ".env"));

const PORT = Number(process.env.PORT ?? 3001);

const server = createServer(async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.method === "GET" && req.url === "/health") {
    send(res, 200, { ok: true });
    return;
  }

  if (req.method === "POST" && req.url === "/transactions/parse") {
    try {
      const payload = JSON.parse(await readBody(req)) as Partial<ParseContext> & { provider?: string };
      const text = payload.text?.trim() ?? "";
      if (!text) {
        send(res, 400, { error: "text is required" });
        return;
      }
      const context: ParseContext = {
        text,
        currentDate: payload.currentDate ?? new Date().toISOString().slice(0, 10),
        timezone: payload.timezone ?? "Europe/Berlin",
        defaultCurrency: payload.defaultCurrency ?? "EUR",
        categories: payload.categories?.length ? payload.categories : [...ALLOWED_CATEGORIES]
      };
      const provider = typeof payload.provider === "string" ? payload.provider : undefined;
      console.log(`parse from ${req.socket.remoteAddress ?? "?"} ${text.slice(0, 80)}`);
      const parsed = provider === "openai"
        ? await parseWithOpenAI(context)
        : provider === "gemini"
          ? await parseWithGemini(context)
          : await parseWithFallback(context);
      send(res, 200, parsed);
    } catch (error) {
      const status = error instanceof ProviderError ? 502 : 500;
      send(res, status, { error: error instanceof Error ? error.message : "Parse failed" });
    }
    return;
  }

  send(res, 404, { error: "Not found" });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Parser listening on http://0.0.0.0:${PORT}`);
});

function send(res: import("node:http").ServerResponse, status: number, body: unknown) {
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(body));
}

function readBody(req: import("node:http").IncomingMessage): Promise<string> {
  return new Promise((resolveBody, reject) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => resolveBody(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function loadEnv(path: string) {
  try {
    const text = readFileSync(path, "utf8");
    for (const line of text.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const index = trimmed.indexOf("=");
      if (index < 0) continue;
      const key = trimmed.slice(0, index);
      const value = trimmed.slice(index + 1);
      if (!process.env[key]) process.env[key] = value;
    }
  } catch {
    // .env is optional when variables are already exported
  }
}
