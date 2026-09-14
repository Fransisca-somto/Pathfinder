const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

const supabase = createClient(supabaseUrl, supabaseKey);

async function testAdminCreate() {
  console.log('Attempting admin create...');
  const { data, error } = await supabase.auth.admin.createUser({
    email: 'test_admin_create_' + Date.now() + '@example.com',
    password: 'SecurePassword123!',
    email_confirm: true,
    user_metadata: {
      full_name: 'Test Admin Create',
      phone: '1234567890',
      role: 'owner'
    }
  });

  if (error) {
    console.error('Error:', error);
  } else {
    console.log('Success!', data.user.id);
  }
}

testAdminCreate();
