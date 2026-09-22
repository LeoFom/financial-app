export const parsedTransactionSchema = {
  type: "object",
  additionalProperties: false,
  required: ["type", "items", "needsConfirmation", "clarificationQuestion"],
  properties: {
    type: {
      type: "string",
      enum: ["expense", "income", "transfer"]
    },
    items: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "amount",
          "currency",
          "category",
          "description",
          "merchant",
          "date",
          "paymentMethod"
        ],
        properties: {
          amount: { type: "number" },
          currency: { type: ["string", "null"] },
          category: { type: ["string", "null"] },
          description: { type: ["string", "null"] },
          merchant: { type: ["string", "null"] },
          date: { type: ["string", "null"] },
          paymentMethod: {
            anyOf: [
              { type: "string", enum: ["cash", "card", "bank_transfer"] },
              { type: "null" }
            ]
          }
        }
      }
    },
    needsConfirmation: { type: "boolean" },
    clarificationQuestion: { type: ["string", "null"] }
  }
} as const;

export const geminiResponseSchema = {
  type: "OBJECT",
  properties: {
    type: { type: "STRING", enum: ["expense", "income", "transfer"] },
    items: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          amount: { type: "NUMBER" },
          currency: { type: "STRING", nullable: true },
          category: { type: "STRING", nullable: true },
          description: { type: "STRING", nullable: true },
          merchant: { type: "STRING", nullable: true },
          date: { type: "STRING", nullable: true },
          paymentMethod: { type: "STRING", nullable: true }
        },
        required: [
          "amount",
          "currency",
          "category",
          "description",
          "merchant",
          "date",
          "paymentMethod"
        ]
      }
    },
    needsConfirmation: { type: "BOOLEAN" },
    clarificationQuestion: { type: "STRING", nullable: true }
  },
  required: ["type", "items", "needsConfirmation", "clarificationQuestion"]
};
