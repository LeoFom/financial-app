import { log, redact } from "../log.ts";
import { SYSTEM_PROMPT, userPrompt } from "./prompt.ts";
import { geminiResponseSchema, parsedTransactionSchema } from "./schema.ts";
import type { ParseContext, ParsedTransaction } from "./types.ts";
import { ProviderError } from "./types.ts";
import { validateParsed } from "./validate.ts";

async function timed<T>(label: string, work: () => Promise<T>): Promise<T> {
  const started = Date.now();
  try {
    const result = await work();
    log.ok(`${label}  ${Date.now() - started} мс`);
    return result;
  } catch (error) {
    log.error(`${label}  ${Date.now() - started} мс  ${error instanceof Error ? error.message : String(error)}`);
    throw error;
  }
}

function retryableStatus(status: number): boolean {
  return status === 429 || status === 500 || status === 502 || status === 503 || status === 529;
}

function openRouterKey(): string | undefined {
  return process.env.OR_API_KEY || process.env.OPENROUTER_API_KEY;
}

const DEFAULT_OPENROUTER_MODELS = [
  "qwen/qwen3.8-27b:free",
  "nvidia/nemotron-3.5-lightning:free",
  "google/gemma-4-26b-a4b-it:free"
];

export function openRouterModels(): string[] {
  const listed = (process.env.OPENROUTER_MODELS ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  if (listed.length > 0) return unique(listed);

  const primary = process.env.OPENROUTER_MODEL?.trim();
  const models = primary
    ? [primary, ...DEFAULT_OPENROUTER_MODELS.filter((model) => model !== primary)]
    : DEFAULT_OPENROUTER_MODELS;
  return unique(models);
}

function unique(values: string[]): string[] {
  return [...new Set(values)];
}

type ChatMessage = {
  content?: string | Array<{ type?: string; text?: string }>;
};

function extractChatText(body: string): string {
  const json = JSON.parse(body) as {
    choices?: { message?: ChatMessage }[];
  };
  const content = json.choices?.[0]?.message?.content;
  if (typeof content === "string") return content.trim();
  if (Array.isArray(content)) {
    return content.map((part) => part.text ?? "").join("").trim();
  }
  return "";
}

function parseModelJSON(text: string): unknown {
  const stripped = text
    .replace(/<think>[\s\S]*?<\/think>/gi, "")
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
  try {
    return JSON.parse(stripped);
  } catch {
    const start = stripped.indexOf("{");
    const end = stripped.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return JSON.parse(stripped.slice(start, end + 1));
    }
    throw new ProviderError("Model returned invalid JSON", 502, true);
  }
}

type GeminiTarget = { url: string; headers: Record<string, string> };

function geminiTargets(model: string, key: string): GeminiTarget[] {
  const project = (process.env.GEMINI_PROJECT ?? "").replace(/^projects\//, "");
  const location = process.env.GEMINI_LOCATION ?? "us-central1";
  const targets: GeminiTarget[] = [
    {
      url: `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      headers: { "Content-Type": "application/json", "x-goog-api-key": key }
    }
  ];
  if (process.env.GEMINI_USE_VERTEX === "1" && project) {
    targets.push({
      url: `https://${location}-aiplatform.googleapis.com/v1/projects/${project}/locations/${location}/publishers/google/models/${model}:generateContent`,
      headers: { "Content-Type": "application/json", "x-goog-api-key": key }
    });
  }
  return targets;
}

function extractModelText(body: string): string {
  const json = JSON.parse(body) as {
    candidates?: { content?: { parts?: { text?: string }[] } }[];
  };
  const parts = json.candidates?.[0]?.content?.parts ?? [];
  return parts.map((part) => part.text ?? "").join("").trim();
}

export async function parseWithOpenRouter(context: ParseContext): Promise<ParsedTransaction> {
  const key = openRouterKey();
  if (!key) throw new ProviderError("OR_API_KEY is missing");

  const models = openRouterModels();
  const errors: string[] = [];
  for (let index = 0; index < models.length; index++) {
    const model = models[index];
    try {
      return await timed(`OpenRouter ${model}`, () => parseWithOpenRouterModel(context, key, model));
    } catch (error) {
      errors.push(`${model}: ${errorMessage(error)}`);
      const next = models[index + 1];
      if (next) log.warn(`${model} не ответила, переключаюсь на ${next}`);
    }
  }
  throw new ProviderError(errors.join(" | "), 502, true);
}

async function parseWithOpenRouterModel(
  context: ParseContext,
  key: string,
  model: string
): Promise<ParsedTransaction> {
  log.info(`OpenRouter: модель ${model}`);

  const messages = [
    { role: "system", content: SYSTEM_PROMPT },
    { role: "user", content: userPrompt(context) }
  ];
  let useStructured = true;
  let lastError: ProviderError | undefined;

  for (let attempt = 0; attempt < 2; attempt++) {
    const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${key}`,
        "HTTP-Referer": "https://github.com/LeoFom/financial-app",
        "X-Title": "FinancialApp"
      },
      body: JSON.stringify({
        model,
        temperature: 0,
        max_tokens: Number(process.env.OPENROUTER_MAX_TOKENS ?? 2048),
        messages,
        ...(useStructured
          ? { response_format: { type: "json_object" }, reasoning: { enabled: false } }
          : {})
      }),
      signal: AbortSignal.timeout(25_000)
    });

    const body = await response.text();
    if (response.status === 400 && useStructured) {
      useStructured = false;
      log.warn(`${model}: 400, повторяю без json_object/reasoning`);
      continue;
    }
    if (!response.ok) {
      throw openRouterError(response.status, body);
    }

    const text = extractChatText(body);
    if (!text) {
      lastError = new ProviderError("OpenRouter returned an empty response", response.status, true);
      continue;
    }
    try {
      return validateParsed(parseModelJSON(text), context.categories, "openrouter");
    } catch (error) {
      lastError = new ProviderError(`OpenRouter JSON invalid: ${errorMessage(error)}`, 502, true);
      log.warn(`OpenRouter JSON: ${redact(text, 280)}`);
      continue;
    }
  }

  throw lastError ?? new ProviderError("OpenRouter request failed", 502, true);
}

function openRouterError(status: number, body: string): ProviderError {
  try {
    const parsed = JSON.parse(body) as { error?: { message?: string } };
    const message = parsed.error?.message ?? body;
    return new ProviderError(`OpenRouter ${status}: ${redact(message, 220)}`, status, retryableStatus(status));
  } catch {
    return new ProviderError(`OpenRouter ${status}: ${redact(body, 220)}`, status, retryableStatus(status));
  }
}

export async function parseWithGemini(context: ParseContext): Promise<ParsedTransaction> {
  return timed("Gemini", () => parseWithGeminiOnce(context));
}

async function parseWithGeminiOnce(context: ParseContext): Promise<ParsedTransaction> {
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw new ProviderError("GEMINI_API_KEY is missing");

  const model = process.env.GEMINI_MODEL ?? "gemini-3.6-flash";
  const targets = geminiTargets(model, key);
  let lastError: ProviderError | undefined;

  for (const target of targets) {
    for (let attempt = 0; attempt < 2; attempt++) {
      log.info(`Gemini:    модель ${model}, попытка ${attempt + 1}`);
      const response = await fetch(target.url, {
        method: "POST",
        headers: target.headers,
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
          contents: [{ role: "user", parts: [{ text: userPrompt(context) }] }],
          generationConfig: {
            responseMimeType: "application/json",
            responseSchema: geminiResponseSchema,
            temperature: 0
          }
        })
      });

      const body = await response.text();
      if (response.status === 503 && attempt === 0) {
        log.warn(`Gemini перегружен (503), повторяю через 400 мс`);
        await new Promise((resolve) => setTimeout(resolve, 400));
        continue;
      }
      if (!response.ok) {
        lastError = new ProviderError(`Gemini ${response.status}: ${redact(body, 220)}`, response.status, retryableStatus(response.status) || response.status === 403);
        break;
      }

      const text = extractModelText(body);
      if (!text) {
        lastError = new ProviderError("Gemini returned an empty response", response.status, true);
        break;
      }
      return validateParsed(parseModelJSON(text), context.categories, "gemini");
    }
  }

  throw lastError ?? new ProviderError("Gemini request failed", 502, true);
}

export async function parseWithOpenAI(context: ParseContext): Promise<ParsedTransaction> {
  return timed("OpenAI", () => parseWithOpenAIOnce(context));
}

async function parseWithOpenAIOnce(context: ParseContext): Promise<ParsedTransaction> {
  const key = process.env.OPENAI_API_KEY;
  if (!key) throw new ProviderError("OPENAI_API_KEY is missing");
  const model = process.env.OPENAI_MODEL ?? "gpt-4o-mini";
  log.info(`OpenAI:    модель ${model}`);

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`
    },
    body: JSON.stringify({
      model,
      temperature: 0,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userPrompt(context) }
      ],
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "parsed_transaction",
          strict: true,
          schema: parsedTransactionSchema
        }
      }
    })
  });

  const body = await response.text();
  if (!response.ok) {
    throw new ProviderError(`OpenAI ${response.status}: ${redact(body, 220)}`, response.status, retryableStatus(response.status));
  }

  const json = JSON.parse(body) as {
    choices?: { message?: { content?: string } }[];
  };
  const text = json.choices?.[0]?.message?.content;
  if (!text) throw new ProviderError("OpenAI returned an empty response", response.status, true);
  return validateParsed(parseModelJSON(text), context.categories, "openai");
}

export async function parseWithFallback(context: ParseContext): Promise<ParsedTransaction> {
  const chain = [
    { name: "OpenRouter", available: Boolean(openRouterKey()), run: () => parseWithOpenRouter(context) },
    { name: "Gemini", available: Boolean(process.env.GEMINI_API_KEY), run: () => parseWithGemini(context) },
    { name: "OpenAI", available: Boolean(process.env.OPENAI_API_KEY), run: () => parseWithOpenAI(context) }
  ].filter((item) => item.available);

  if (chain.length === 0) {
    throw new ProviderError("No AI provider keys configured", 500, false);
  }

  const errors: string[] = [];
  for (let index = 0; index < chain.length; index++) {
    const current = chain[index];
    try {
      return await current.run();
    } catch (error) {
      errors.push(`${current.name}: ${errorMessage(error)}`);
      const next = chain[index + 1];
      if (!next) break;
      log.warn(`${current.name} не сработал, переключаюсь на ${next.name}`);
    }
  }
  throw new ProviderError(errors.join(" | "), 502, false);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
