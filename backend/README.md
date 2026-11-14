# SignVoice Backend API

**Version:** 1.0.0  
**Status:** Production-Ready for Integration  
**Stack:** Node.js + Express + TypeScript + MongoDB  

---

## Quick Start

```powershell
# 1. Install dependencies
npm install

# 2. Start MongoDB
docker compose up -d

# 3. Start development server
npm run dev

# Server runs at http://localhost:3000
# Health check: http://localhost:3000/health/live
```

---

## Project Structure

```
backend/
├── src/
│   ├── models/          # Mongoose models (9 collections)
│   ├── services/        # Business logic
│   ├── controllers/     # HTTP request handlers
│   ├── routes/          # API route definitions
│   ├── middlewares/     # Auth, validation, error handling
│   ├── utils/           # Password hashing, JWT utilities
│   ├── validation/      # Zod validation schemas
│   ├── common/          # Shared utilities and errors
│   ├── config/          # Environment and database config
│   ├── app.ts           # Express app configuration
│   └── server.ts        # Server entry point
├── tests/               # Vitest + Supertest tests
├── docs/                # API documentation
├── docker-compose.yml   # MongoDB container
├── .env                 # Environment variables
├── package.json         # Dependencies
└── tsconfig.json        # TypeScript configuration
```

---

## Available Scripts

```powershell
npm run dev          # Start development server with auto-reload
npm run build        # Compile TypeScript to JavaScript
npm start            # Run built backend (not the production launcher)
npm run typecheck    # Check TypeScript types
npm test             # Run tests
npm run test:watch   # Run tests in watch mode
npm run lint         # Run ESLint
npm run lint:fix     # Fix ESLint errors
```

---

## Environment Variables

Copy `.env.example` to `.env` (already configured):

```env
NODE_ENV=development
PORT=3000

# MongoDB
MONGODB_URI=mongodb://localhost:27017/signvoice

# JWT Secrets (generated, do not change in development)
JWT_ACCESS_SECRET=<secret>
JWT_REFRESH_SECRET=<secret>
JWT_ACCESS_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d

# CORS (add production domains)
CORS_ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080
```

---

## API Documentation

### Base URL
```
Local: http://localhost:3000/api/v1
```

### Authentication

**Register:**
```http
POST /api/v1/auth/register
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "Test1234",
  "displayName": "User Name"
}
```

**Login:**
```http
POST /api/v1/auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "Test1234"
}
```

**Get Current User:**
```http
GET /api/v1/auth/me
Authorization: Bearer {accessToken}
```

### Dictionary

**Get Entries:**
```http
GET /api/v1/dictionary?categoryId={id}&search={query}&limit=20&skip=0
```

**Get Entry Detail:**
```http
GET /api/v1/dictionary/{entryId}
```

### Full API Reference

See [docs/FRONTEND_INTEGRATION_HANDOFF.md](docs/FRONTEND_INTEGRATION_HANDOFF.md) for complete API documentation with examples.

---

## Testing

```powershell
# Run all tests
npm test

# Run specific test file
npm test auth.test.ts

# Watch mode
npm run test:watch
```

**Test Files:**
- `tests/auth.test.ts` - Authentication tests
- `tests/dictionary.test.ts` - Dictionary API tests

---

## Database

### Collections (9)

1. **users** - User accounts
2. **auth_sessions** - JWT sessions
3. **user_settings** - User preferences
4. **categories** - Dictionary categories
5. **dictionary_entries** - Sign language dictionary
6. **favorites** - User bookmarks
7. **search_history** - Viewed entries
8. **conversations** - Chat history (structure only)
9. **audit_logs** - Security audit trail

### MongoDB Management

```powershell
# Start MongoDB
docker compose up -d

# Stop MongoDB
docker compose down

# View logs
docker compose logs -f

# Access MongoDB shell
docker exec -it signvoice_mongodb mongosh

# Backup database
docker exec signvoice_mongodb mongodump --archive > backup.dump

# Restore database
docker exec -i signvoice_mongodb mongorestore --archive < backup.dump
```

---

## Security

### Implemented

- ✅ Argon2id password hashing
- ✅ JWT access + refresh tokens
- ✅ Token hashing in database
- ✅ RBAC (USER/STAFF/ADMIN)
- ✅ CORS configuration
- ✅ Helmet security headers
- ✅ Input validation (Zod)
- ✅ Audit logging
- ✅ MongoDB injection prevention

### TODO (Before Production)

- ⚠️ Rate limiting
- ⚠️ CSRF protection
- ⚠️ API key management
- ⚠️ File upload virus scanning
- ⚠️ DDoS protection

---

## Deployment

### Development

Already configured. Run `npm run dev`.

### Production Checklist

1. Set `NODE_ENV=production`
2. Use production MongoDB (replica set recommended)
3. Configure HTTPS/TLS
4. Add rate limiting
5. Set up monitoring (PM2, etc.)
6. Configure production CORS origins
7. Set up log aggregation
8. Add email service
9. Configure backups
10. Set up error tracking

**Production operations:** The checklist above is general guidance, not the
current deployment procedure. Use the pinned-release launcher from checkout E
with `backend/.env.production.local`, as documented in
[the production runbook](../docs/OPERATIONS.md). Do not use `npm start` or the
development `.env` as the production path; direct Node/PM2 startup bypasses the
reviewed launch checks.

---

## Architecture

### Design Patterns

- **MVC Pattern:** Controllers → Services → Models
- **Middleware Chain:** Auth → Validation → Controller → Error Handler
- **Repository Pattern:** Mongoose models encapsulate data access
- **DTO Pattern:** Zod schemas validate input/output

### Key Features

- **TypeScript Strict Mode:** No `any` types, full type safety
- **Async/Await:** All async operations use async/await
- **Error Handling:** Centralized error handler with error codes
- **Validation:** Zod schemas for request validation
- **Logging:** Request ID tracking, audit logs
- **Session Management:** JWT with refresh token rotation
- **RBAC:** Middleware-based role enforcement

---

## Troubleshooting

### Server Won't Start

1. Check MongoDB is running: `docker ps`
2. Check environment variables: `.env` file exists
3. Check TypeScript compiles: `npm run typecheck`
4. Check logs for errors

### Database Connection Failed

1. Verify MongoDB container: `docker ps --filter "name=signvoice_mongodb"`
2. Restart MongoDB: `docker compose restart`
3. Check MongoDB logs: `docker compose logs mongodb`

### Tests Failing

1. Ensure MongoDB is running
2. Check test database is isolated
3. Run `npm run typecheck` first
4. Check for port conflicts

### TypeScript Errors

1. Run `npm run typecheck` to see all errors
2. Check tsconfig.json is correct
3. Verify all dependencies installed: `npm install`

---

## Contributing

### Code Style

- TypeScript strict mode
- ESLint configuration enforced
- Prettier formatting (if configured)
- JSDoc comments on public APIs

### Git Workflow

1. Create feature branch
2. Implement changes
3. Run tests: `npm test`
4. Run typecheck: `npm run typecheck`
5. Commit with descriptive message
6. Push and create pull request

---

## Documentation

- **API Coverage:** [docs/API_COVERAGE_MATRIX.md](docs/API_COVERAGE_MATRIX.md)
- **Flutter Integration:** [docs/FRONTEND_INTEGRATION_HANDOFF.md](docs/FRONTEND_INTEGRATION_HANDOFF.md)
- **Completion Report:** [docs/BATCH_01_COMPLETION_REPORT.md](docs/BATCH_01_COMPLETION_REPORT.md)
- **Progress Tracking:** [PROGRESS.md](PROGRESS.md)

---

## License

ISC

---

## Support

For integration questions or issues:
1. Check [docs/FRONTEND_INTEGRATION_HANDOFF.md](docs/FRONTEND_INTEGRATION_HANDOFF.md)
2. Review source code in `src/`
3. Check tests in `tests/` for usage examples

---

**Last Updated:** 2026-10-09  
**Status:** ✅ Ready for Flutter Integration
