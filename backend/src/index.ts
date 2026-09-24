import { readFileSync } from "node:fs";
import type { IncomingMessage, ServerResponse } from "node:http";
import { createServer } from "node:http";
import { resolve } from "node:path";
import { parseWithFallback, parseWithGemini, parseWithOpenAI } from "./ai/providers.ts";
import { ALLOWED_CATEGORIES, type ParseContext, type ParsedTransaction } from "./ai/types.ts";
import { ProviderError } from "./ai/types.ts";
import { log, redact } from "./log.ts";

loadEnv(resolve(process.cwd(), ".env"));

const PORT = Number(process.env.PORT ?? 3001);
let requestCount = 0;

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

  const id = ++requestCount;
  const started = Date.now();
  const client = clientLabel(req);

  if (req.method === "POST" && req.url === "/transactions/parse") {
    log.banner(`запрос #${id}  POST /transactions/parse`);
    log.info(`клиент:    ${client}`);
    try {
      const payload = JSON.parse(await readBody(req)) as Partial<ParseContext> & { provider?: string };
      const text = payload.text?.trim() ?? "";
      if (!text) {
        log.warn("текст пустой — 400");
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
      log.info(`текст:     «${redact(text, 180)}»`);
      log.info(`контекст:  дата ${context.currentDate}  ${context.timezone}  валюта ${context.defaultCurrency}`);
      log.info(`категории: ${context.categories.join(", ")}`);
      log.info(`маршрут:   ${provider ? `только ${provider}` : "авто: Gemini, при сбое OpenAI"}`);

      const parsed = provider === "openai"
        ? await parseWithOpenAI(context)
        : provider === "gemini"
          ? await parseWithGemini(context)
          : await parseWithFallback(context);

      logResult(parsed);
      send(res, 200, parsed);
      log.ok(`ответ 200 за ${Date.now() - started} мс  провайдер ${parsed.provider}`);
    } catch (error) {
      const status = error instanceof ProviderError ? 502 : 500;
      const message = error instanceof Error ? error.message : "Parse failed";
      log.error(`ответ ${status} за ${Date.now() - started} мс  ${message}`);
      send(res, status, { error: message });
    }
    return;
  }

  log.banner(`запрос #${id}  ${req.method ?? "?"} ${req.url ?? "/"}`);
  log.info(`клиент:    ${client}`);
  log.warn("маршрут не найден — 404");
  send(res, 404, { error: "Not found" });
});

server.listen(PORT, "0.0.0.0", () => {
  log.banner("сервер запущен");
  log.info(`порт:      ${PORT}`);
  log.info(`Gemini:    ${process.env.GEMINI_API_KEY ? "ключ есть" : "ключа нет"}  модель ${process.env.GEMINI_MODEL ?? "gemini-3.6-flash"}`);
  log.info(`OpenAI:    ${process.env.OPENAI_API_KEY ? "ключ есть" : "ключа нет"}  модель ${process.env.OPENAI_MODEL ?? "gpt-4o-mini"}`);
  log.info("логи:      /health не пишем, чтобы не засорять консоль проверками Render");
});

function logResult(parsed: ParsedTransaction) {
  log.ok(`результат: ${parsed.type}, операций ${parsed.items.length}`
    + (parsed.needsConfirmation ? ", нужна проверка" : ", можно подтверждать"));
  if (parsed.clarificationQuestion) {
    log.info(`вопрос:    ${parsed.clarificationQuestion}`);
  }
  parsed.items.forEach((item, index) => {
    const bits = [
      `${item.amount}${item.currency ? ` ${item.currency}` : ""}`,
      item.category ?? "без категории",
      item.description ? `«${item.description}»` : null,
      item.merchant ? `магазин ${item.merchant}` : null,
      item.date ?? null
    ].filter(Boolean);
    log.info(`  ${index + 1}) ${bits.join(" · ")}`);
  });
}

function clientLabel(req: IncomingMessage): string {
  const forwarded = header(req, "x-forwarded-for")?.split(",")[0]?.trim();
  const ip = forwarded
    || header(req, "cf-connecting-ip")
    || req.socket.remoteAddress
    || "?";
  const agent = header(req, "user-agent") ?? "без user-agent";
  const country = header(req, "cf-ipcountry") || header(req, "x-forwarded-country");
  return [ip, country, shortAgent(agent)].filter(Boolean).join("  ");
}

function shortAgent(agent: string): string {
  if (/FinancialApp\/ios/i.test(agent)) return "iPhone / приложение Финансы";
  if (/FinancialApp|CFNetwork|Darwin/i.test(agent)) return "iPhone / iOS приложение";
  if (/curl\//i.test(agent)) return "curl";
  if (/Mozilla|Chrome|Safari/i.test(agent)) return "браузер";
  return redact(agent, 80);
}

function header(req: IncomingMessage, name: string): string | undefined {
  const value = req.headers[name];
  return Array.isArray(value) ? value[0] : value;
}

function send(res: ServerResponse, status: number, body: unknown) {
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(body));
}

function readBody(req: IncomingMessage): Promise<string> {
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
