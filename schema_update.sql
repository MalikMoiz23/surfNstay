-- Add blocking support to travellers and hosts tables
ALTER TABLE travellers ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN DEFAULT FALSE;
ALTER TABLE hosts ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN DEFAULT FALSE;
