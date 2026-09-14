require('dotenv').config();

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

async function rawSignup() {
  console.log('Sending raw fetch request to GoTrue API...');
  
  try {
    const response = await fetch(`${SUPABASE_URL}/auth/v1/signup`, {
      method: 'POST',
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email: `test_raw_${Date.now()}@example.com`,
        password: 'Password123!@#',
        data: { full_name: 'Test', role: 'owner' }
      })
    });

    const status = response.status;
    const text = await response.text();
    
    console.log(`Status: ${status}`);
    console.log(`Raw Response Text: ${text}`);
  } catch (err) {
    console.error('Fetch crashed:', err);
  }
}

rawSignup();
