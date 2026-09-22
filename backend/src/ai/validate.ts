import { z } from "zod";
import type { ParsedTransaction } from "./types.ts";

const emptyToNull = z
  .union([z.string(), z.null(), z.undefined()])
  .transform((value) => {
    if (value == null) return null;
    const trimmed = value.trim();
    return trimmed.length === 0 ? null : trimmed;
  });

const itemSchema = z.object({
  amount: z.coerce.number(),
  currency: emptyToNull,
  category: emptyToNull,
  description: emptyToNull,
  merchant: emptyToNull,
  date: emptyToNull,
  paymentMethod: z.preprocess((value) => {
    return value === "cash" || value === "card" || value === "bank_transfer" ? value : null;
  }, z.enum(["cash", "card", "bank_transfer"]).nullable())
});

const rawSchema = z.object({
  type: z.enum(["expense", "income", "transfer"]),
  items: z.array(itemSchema),
  needsConfirmation: z.boolean(),
  clarificationQuestion: z.string().nullable()
});

const MAX_AMOUNT = 100_000;

export function validateParsed(
  raw: unknown,
  allowedCategories: string[],
  provider: ParsedTransaction["provider"]
): ParsedTransaction {
  const parsed = rawSchema.parse(raw);
  const allowed = new Set(allowedCategories.map((value) => value.toLowerCase()));

  const items = parsed.items
    .filter((item) => Number.isFinite(item.amount) && item.amount > 0)
    .map((item) => {
      const category = item.category && allowed.has(item.category.toLowerCase())
        ? item.category
        : matchCategory(item.category, allowedCategories);
      return { ...item, category };
    });

  let needsConfirmation = parsed.needsConfirmation;
  let clarificationQuestion = parsed.clarificationQuestion;

  if (items.length === 0) {
    needsConfirmation = true;
    clarificationQuestion = clarificationQuestion ?? "Какую сумму вы имеете в виду?";
  }

  if (items.some((item) => !item.category || item.amount > MAX_AMOUNT)) {
    needsConfirmation = true;
  }

  return {
    type: parsed.type,
    items,
    needsConfirmation,
    clarificationQuestion,
    provider
  };
}

function matchCategory(value: string | null, allowed: string[]): string | null {
  if (!value) return null;
  const needle = value.toLowerCase();
  return allowed.find((item) => item.toLowerCase() === needle)
    ?? allowed.find((item) => item.toLowerCase().includes(needle) || needle.includes(item.toLowerCase()))
    ?? null;
}
