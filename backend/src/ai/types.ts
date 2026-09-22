export const ALLOWED_CATEGORIES = [
  "food",
  "groceries",
  "transport",
  "housing",
  "health",
  "entertainment",
  "shopping",
  "subscriptions",
  "education",
  "salary",
  "other"
] as const;

export type AllowedCategory = (typeof ALLOWED_CATEGORIES)[number];

export type ParseContext = {
  text: string;
  currentDate: string;
  timezone: string;
  defaultCurrency: string;
  categories: string[];
};

export type ParsedItem = {
  amount: number;
  currency: string | null;
  category: string | null;
  description: string | null;
  merchant: string | null;
  date: string | null;
  paymentMethod: "cash" | "card" | "bank_transfer" | null;
};

export type ParsedTransaction = {
  type: "expense" | "income" | "transfer";
  items: ParsedItem[];
  needsConfirmation: boolean;
  clarificationQuestion: string | null;
  provider: "gemini" | "openai";
};

export class ProviderError extends Error {
  constructor(
    message: string,
    readonly status?: number,
    readonly retryable = false
  ) {
    super(message);
  }
}

export function isRetryable(error: unknown): boolean {
  if (error instanceof ProviderError) return error.retryable;
  return true;
}
