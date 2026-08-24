-- ============================================================
--  SurfNStay – Properties Table Enhancement
--  Run this in Supabase SQL Editor → New Query → Run
-- ============================================================

-- 1. Property type: Room | Apartment | House | Villa
ALTER TABLE properties
  ADD COLUMN IF NOT EXISTS property_type TEXT NOT NULL DEFAULT 'Room';

-- 2. Guest preference: Any | Family | Female Only | Bachelors
ALTER TABLE properties
  ADD COLUMN IF NOT EXISTS guest_preference TEXT NOT NULL DEFAULT 'Any';

-- 3. Number of bedrooms
ALTER TABLE properties
  ADD COLUMN IF NOT EXISTS bedrooms INTEGER NOT NULL DEFAULT 1;

-- 4. Number of bathrooms
ALTER TABLE properties
  ADD COLUMN IF NOT EXISTS bathrooms INTEGER NOT NULL DEFAULT 1;

-- 5. Maximum guests allowed
ALTER TABLE properties
  ADD COLUMN IF NOT EXISTS max_guests INTEGER NOT NULL DEFAULT 1;

-- ── Optional: Add CHECK constraints for valid values ─────────────────────────

ALTER TABLE properties
  ADD CONSTRAINT chk_property_type
    CHECK (property_type IN ('Room', 'Apartment', 'House', 'Villa'));

ALTER TABLE properties
  ADD CONSTRAINT chk_guest_preference
    CHECK (guest_preference IN ('Any', 'Family', 'Female Only', 'Bachelors'));

ALTER TABLE properties
  ADD CONSTRAINT chk_bedrooms
    CHECK (bedrooms >= 1 AND bedrooms <= 20);

ALTER TABLE properties
  ADD CONSTRAINT chk_bathrooms
    CHECK (bathrooms >= 1 AND bathrooms <= 20);

ALTER TABLE properties
  ADD CONSTRAINT chk_max_guests
    CHECK (max_guests >= 1 AND max_guests <= 50);

-- ── Verify columns were added ────────────────────────────────────────────────
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'properties'
  AND column_name IN (
    'property_type', 'guest_preference',
    'bedrooms', 'bathrooms', 'max_guests'
  )
ORDER BY column_name;
