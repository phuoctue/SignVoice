#!/usr/bin/env tsx
/**
 * Create test accounts for USER, STAFF, and ADMIN
 */
import { connectDatabase } from '../src/config/database';
import { User } from '../src/models/User.model';
import * as argon2 from 'argon2';

interface TestAccount {
  email: string;
  password: string;
  displayName: string;
  role: 'USER' | 'STAFF' | 'ADMIN';
}

const testAccounts: TestAccount[] = [
  {
    email: 'user@test.com',
    password: 'User123!',
    displayName: 'Test User',
    role: 'USER',
  },
  {
    email: 'staff@test.com',
    password: 'Staff123!',
    displayName: 'Test Staff',
    role: 'STAFF',
  },
  {
    email: 'admin@signvoice.com',
    password: 'Admin123!',
    displayName: 'System Administrator',
    role: 'ADMIN',
  },
];

async function createTestAccounts() {
  console.log('🔧 Creating test accounts...\n');

  try {
    // Connect to database
    await connectDatabase();
    console.log('✅ Connected to MongoDB\n');

    const results: { email: string; role: string; status: string }[] = [];

    for (const account of testAccounts) {
      // Check if account already exists
      const existing = await User.findOne({ email: account.email });

      if (existing) {
        console.log(`⚠️  ${account.role}: ${account.email} already exists (skipped)`);
        results.push({
          email: account.email,
          role: account.role,
          status: 'EXISTS',
        });
        continue;
      }

      // Hash password
      const passwordHash = await argon2.hash(account.password);

      // Create user
      await User.create({
        email: account.email,
        passwordHash,
        displayName: account.displayName,
        role: account.role,
        status: 'ACTIVE',
        accountType: 'LOCAL',
        isGuest: false,
      });

      console.log(`✅ ${account.role}: ${account.email} created`);
      results.push({
        email: account.email,
        role: account.role,
        status: 'CREATED',
      });
    }

    console.log('\n' + '='.repeat(60));
    console.log('📋 Test Accounts Summary:\n');

    console.log('┌─────────────────────────────────────────────────────────┐');
    console.log('│ USER Account (Basic user permissions)                  │');
    console.log('├─────────────────────────────────────────────────────────┤');
    console.log('│ Email:    user@test.com                                │');
    console.log('│ Password: User123!                                      │');
    console.log('│ Role:     USER                                          │');
    console.log('└─────────────────────────────────────────────────────────┘');

    console.log('');
    console.log('┌─────────────────────────────────────────────────────────┐');
    console.log('│ STAFF Account (Content moderation)                     │');
    console.log('├─────────────────────────────────────────────────────────┤');
    console.log('│ Email:    staff@test.com                               │');
    console.log('│ Password: Staff123!                                     │');
    console.log('│ Role:     STAFF                                         │');
    console.log('└─────────────────────────────────────────────────────────┘');

    console.log('');
    console.log('┌─────────────────────────────────────────────────────────┐');
    console.log('│ ADMIN Account (Full system access)                     │');
    console.log('├─────────────────────────────────────────────────────────┤');
    console.log('│ Email:    admin@signvoice.com                          │');
    console.log('│ Password: Admin123!                                     │');
    console.log('│ Role:     ADMIN                                         │');
    console.log('└─────────────────────────────────────────────────────────┘');

    console.log('\n⚠️  IMPORTANT: These are TEST accounts only!');
    console.log('   Change passwords in production environment.\n');

    console.log('🧪 How to use in Swagger:');
    console.log('   1. Open http://localhost:3000/api-docs');
    console.log('   2. POST /api/v1/auth/login with credentials above');
    console.log('   3. Copy accessToken from response');
    console.log('   4. Click "Authorize" button');
    console.log('   5. Paste token (without "Bearer ")');
    console.log('   6. Test endpoints based on role permissions\n');

    console.log('📚 Documentation:');
    console.log('   docs/active/SWAGGER_TESTING_GUIDE.md\n');

  } catch (error) {
    console.error('❌ Error creating test accounts:', error);
    process.exit(1);
  } finally {
    process.exit(0);
  }
}

// Run
createTestAccounts();
