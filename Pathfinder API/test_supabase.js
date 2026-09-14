const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

console.log('Testing against URL:', supabaseUrl);

const supabase = createClient(supabaseUrl, supabaseKey);

async function testSignup() {
  console.log('Attempting signup...');
  const { data, error } = await supabase.auth.signUp({
    email: 'test_user_123456@example.com',
    password: 'SecurePassword123!',
    options: {
      data: {
        full_name: 'Test User',
        phone: '1234567890',
        role: 'owner'
      }
    }
  });

  if (error) {
    console.error('Raw Error:', error);
    console.error('Error Status:', error.status);
    console.error('Error Name:', error.name);
    console.error('Error Message:', error.message);
  } else {
    console.log('Signup Successful!');
    console.log('User ID:', data.user?.id);
  }
}

testSignup();
