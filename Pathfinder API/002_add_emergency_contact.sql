-- Add emergency_contact column to vehicles table
ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS emergency_contact TEXT;
