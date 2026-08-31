-- Indici standalone per la pulizia automatica voce (sessioni 24h, log 90 giorni).

CREATE INDEX IF NOT EXISTS "VoiceSession_expiresAt_idx"
  ON "print-farm"."VoiceSession" ("expiresAt");

CREATE INDEX IF NOT EXISTS "VoiceCommandLog_createdAt_idx"
  ON "print-farm"."VoiceCommandLog" ("createdAt");
