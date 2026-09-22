import { SYSTEM_PROMPT, userPrompt } from "./prompt.ts";
import { geminiResponseSchema, parsedTransactionSchema } from "./schema.ts";
import type { ParseContext, ParsedTransaction } from "./types.ts";
import { ProviderError } from "./types.ts";
import { validateParsed } from "./validate.ts";

function retryableStatus(status: number): boolean {
  return status === 429 || status === 500 || status === 503 || status === 529;
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

function parseModelJSON(text: string): unknown {
  const trimmed = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  return JSON.parse(trimmed);
}

export async function parseWithGemini(context: ParseContext): Promise<ParsedTransaction> {
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw new ProviderError("GEMINI_API_KEY is missing");

  const model = process.env.GEMINI_MODEL ?? "gemini-3.6-flash";
  const targets = geminiTargets(model, key);
  let lastError: ProviderError | undefined;

  for (const target of targets) {
    for (let attempt = 0; attempt < 2; attempt++) {
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
      const host = new URL(target.url).host;
      if (response.status === 503 && attempt === 0) {
        console.warn(`Gemini 503 ${model} ${host}, retrying once`);
        await new Promise((resolve) => setTimeout(resolve, 400));
        continue;
      }
      if (!response.ok) {
        console.warn(`Gemini ${response.status} ${model} ${host}: ${body.slice(0, 220)}`);
        lastError = new ProviderError(`Gemini ${response.status}: ${body.slice(0, 400)}`, response.status, retryableStatus(response.status) || response.status === 403);
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
  const key = process.env.OPENAI_API_KEY;
  if (!key) throw new ProviderError("OPENAI_API_KEY is missing");
  const model = process.env.OPENAI_MODEL ?? "gpt-4o-mini";

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
    throw new ProviderError(`OpenAI ${response.status}: ${body.slice(0, 400)}`, response.status, retryableStatus(response.status));
  }

  const json = JSON.parse(body) as {
    choices?: { message?: { content?: string } }[];
  };
  const text = json.choices?.[0]?.message?.content;
  if (!text) throw new ProviderError("OpenAI returned an empty response", response.status, true);
  return validateParsed(parseModelJSON(text), context.categories, "openai");
}

export async function parseWithFallback(context: ParseContext): Promise<ParsedTransaction> {
  try {
    return await parseWithGemini(context);
  } catch (first) {
    if (!isQuotaOrRetry(first)) throw first;
    try {
      return await parseWithOpenAI(context);
    } catch (second) {
      const message = [errorMessage(first), errorMessage(second)].join(" | ");
      throw new ProviderError(message, 502, false);
    }
  }
}

function isQuotaOrRetry(error: unknown): boolean {
  if (error instanceof ProviderError) return error.retryable || (error.status ?? 0) >= 400;
  return true;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
