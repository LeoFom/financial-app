function stamp(): string {
  return new Date().toISOString().replace("T", " ").slice(0, 19);
}

function line(message: string) {
  console.log(`${stamp()}  ${message}`);
}

export function redact(text: string, max = 240): string {
  const cleaned = text
    .replace(/sk-[A-Za-z0-9_-]{10,}/g, "sk-***")
    .replace(/AQ\.[A-Za-z0-9_-]{10,}/g, "AQ.***")
    .replace(/AIza[A-Za-z0-9_-]{10,}/g, "AIza***")
    .replace(/Bearer\s+[A-Za-z0-9._-]+/gi, "Bearer ***");
  const oneLine = cleaned.replace(/\s+/g, " ").trim();
  return oneLine.length > max ? `${oneLine.slice(0, max)}…` : oneLine;
}

export const log = {
  line,
  banner(title: string) {
    console.log("");
    line(`──────── ${title} ────────`);
  },
  info(message: string) {
    line(message);
  },
  warn(message: string) {
    line(`⚠  ${redact(message, 320)}`);
  },
  error(message: string) {
    line(`✖  ${redact(message, 320)}`);
  },
  ok(message: string) {
    line(`✓  ${message}`);
  }
};
