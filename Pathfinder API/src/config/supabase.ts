import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';

dotenv.config();

const envUrl = process.env.SUPABASE_URL || '';
const supabaseUrl = envUrl.startsWith('http') ? envUrl : 'https://dummy-project.supabase.co';
const supabaseKey = process.env.SUPABASE_KEY || process.env.SUPABASE_PUBLISHABLE_KEY || 'dummy-key';

if (supabaseUrl === 'https://dummy-project.supabase.co') {
  console.warn('⚠️ SUPABASE_URL is missing or invalid in .env! Using dummy URL. Authentication will fail until you provide real credentials.');
}

// Create a single supabase client for interacting with your database
export const supabase = createClient(supabaseUrl, supabaseKey);
