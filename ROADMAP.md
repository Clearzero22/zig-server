# Web Framework Roadmap

## 1. Routing

### Core
- [x] Static path matching (`/users`)
- [x] Path parameters (`/users/:id`)
- [x] HTTP method routing (GET, POST, PUT, DELETE, PATCH)
- [x] Route groups with prefix (`/api/v1`)
- [x] Wildcard/glob routes (`/static/*path`)
- [x] Regex route patterns (`(\d+)`)
- [x] Route naming and URL generation (reverse routing)
- [x] Optional parameters (`/users/:id?`)
- [x] Multiple parameters per segment (`/files/:dir+:name`)
- [x] Route priorities and conflict detection
- [x] Custom matchers (header-based, host-based)

### Advanced
- [x] Sub-routers / resource routing
- [x] Route-level middleware
- [x] Route-level rate limiting
- [x] Route-level CORS policies
- [x] Route versioning

## 2. Middleware

### Core Chain
- [x] Middleware type definition (fn (ctx) bool)
- [x] Global middleware stack
- [x] Route-level middleware
- [ ] Group-level middleware
- [ ] Middleware with `next` callback for wrapping
- [ ] Post-processing (response after handler)
- [ ] Error middleware (catch errors from downstream)
- [ ] Short-circuit / abort chain

### Built-in Middleware
- [x] Request logger
- [x] Panic recovery / error handler
- [x] CORS (Cross-Origin Resource Sharing)
- [ ] Request ID generation
- [ ] Request timeout
- [ ] Rate limiting (token bucket, sliding window)
- [ ] Body size limit
- [ ] CSRF protection
- [ ] Secure headers (HSTS, X-Frame-Options, etc.)
- [ ] Gzip / Brotli compression
- [ ] ETag / conditional requests
- [ ] Request validation (schema-based)
- [ ] Basic auth / Bearer token
- [ ] Session middleware
- [ ] Cache control (client-side)
- [ ] Request deduplication
- [ ] Circuit breaker

## 3. Context / Request

### Request Parsing
- [x] Method, target, version, headers
- [x] Path parameters via `ctx.params.get("id")`
- [x] Query parameters (`ctx.query.get("page")`)
- [ ] Query string parsing (multi-value, nested)
- [ ] Form data (URL-encoded, multipart)
- [x] JSON body (`ctx.readBody()` → raw bytes)
- [ ] JSON body `ctx.readJson(T)` → typed struct
- [ ] XML body parsing
- [ ] File upload handling (multipart)
- [ ] Cookie parsing
- [ ] Header helpers (typed accessors)

### Validation
- [ ] JSON schema validation
- [ ] Struct tag validation (`validate:"required,min=3"`)
- [ ] Custom validators
- [ ] Type coercion from strings (query/params)

## 4. Response

### Response Writers
- [x] `ctx.text(status, body)`
- [x] `ctx.json(status, body)`
- [x] `ctx.html(status, body)`
- [ ] `ctx.xml(status, body)`
- [x] `ctx.redirect(status, url)`
- [ ] `ctx.stream(reader, content_type)` — streaming responses
- [ ] `ctx.file(path)` — file download
- [ ] `ctx.attachment(path, filename)` — force download
- [ ] `ctx.noContent()` — 204
- [ ] `ctx.status(code)` — set status only

### Serialization
- [x] JSON serializer (encode Zig structs to JSON)
- [ ] XML serializer
- [ ] Content negotiation (Accept header → serializer)
- [ ] Custom serializer per content type

### Headers & Cookies
- [ ] Response header setters (`ctx.header(name, value)`)
- [ ] Cookie setters (`ctx.cookie(name, value, options)`)
- [ ] Cache control helpers
- [ ] ETag auto-generation

## 5. Error Handling

- [x] Unified error handler (`router.onError(handler)`)
- [x] Panic catcher (recovery middleware)
- [ ] Typed error responses (custom error structs)
- [ ] HTTP exception types (`throw 404`, `throw 403`)
- [ ] Stack trace in debug mode
- [ ] Error response format configurable (JSON, XML, HTML)
- [ ] Multi-error format (validation errors)
- [ ] Development vs production error pages
- [ ] Error logging with stack traces

## 6. Security

- [x] CORS middleware (origins, methods, headers, credentials)
- [ ] CSRF token generation & validation
- [ ] HSTS header
- [ ] X-Content-Type-Options
- [ ] X-Frame-Options
- [ ] Content-Security-Policy
- [ ] Referrer-Policy
- [ ] Input sanitization (XSS prevention)
- [ ] SQL injection prevention guidance
- [ ] Secure cookie defaults (HttpOnly, Secure, SameSite)
- [ ] TLS/HTTPS support
- [ ] TLS certificate auto-renewal (Let's Encrypt)
- [ ] Host header validation
- [ ] Rate limiting (per IP, per route, per user)

## 7. Performance & Concurrency

- [x] Thread-per-connection
- [x] Thread pool with configurable size
- [ ] Connection keep-alive (HTTP persistent connections)
- [ ] HTTP/2 support
- [ ] HTTP/3 (QUIC) support
- [ ] Connection pooling for reverse proxy
- [ ] Request body streaming without buffering
- [ ] Response streaming (chunked transfer)
- [ ] Static file serving with sendfile(2)
- [ ] Static file caching (ETag, Last-Modified, Cache-Control)
- [ ] Static file directory listing
- [ ] Static file pre-compression (.gz, .br)
- [ ] In-memory static file cache
- [x] Graceful shutdown (loopback connect to unblock accept)
- [ ] Connection timeout management
- [ ] Idle connection timeout
- [ ] Request timeout middleware
- [ ] Load balancer health check endpoint (`/healthz`)

### Async I/O
- [ ] Async event loop (epoll/kqueue/IOCP)
- [ ] Non-blocking request processing
- [ ] Fiber/coroutine-based concurrency

## 8. Developer Experience

### API Design
- [ ] Clean public API (`framework.zig` facade)
- [ ] Fluent builder patterns
- [ ] Convention over configuration
- [ ] Minimal boilerplate for common cases

### Hot Reload
- [ ] File watcher for development
- [ ] Auto-rebuild on source changes
- [ ] Graceful restart without dropping connections

### Debugging
- [ ] Request tracing / debug routes
- [ ] Memory allocation tracking
- [ ] Leak detection (GPA allocator)
- [ ] Performance profiling middleware
- [ ] Request timeline logging

### Documentation
- [ ] Inline doc comments (pub fn doc)
- [ ] Generated API reference
- [ ] Example projects
- [ ] Migration guides

## 9. Configuration

- [ ] Environment variable support
- [ ] Config file support (JSON, TOML, YAML)
- [x] Programmatic configuration
- [ ] Environment-specific configs (dev/staging/prod)
- [ ] Secrets management (env-based, vault)
- [ ] Config validation at startup

## 10. Logging

- [x] Request logging middleware
- [ ] Structured logging (JSON format)
- [ ] Log levels (debug, info, warn, error)
- [ ] Log rotation
- [ ] Request ID correlation
- [ ] Access log (Apache/NGINX format)
- [ ] Slow request logging
- [ ] Custom log writers (file, stdout, syslog)

## 11. Database & Storage

### SQLite
- [x] SQLite database wrapper (`builtins/db/sqlite.zig`)
- [x] In-memory database for testing (`db.initMemory()`)
- [x] File-based database (`db.init(path)`)
- [x] Prepared statements (`db.prepare()`)
- [x] Typed row reading (`stmt.oneAlloc(T)`, `stmt.all(T)`)
- [x] DDL operations (`CREATE TABLE`, etc.)
- [x] CRUD operations (INSERT, SELECT, UPDATE, DELETE)
- [x] Error handling with Zig error sets (SQLiteError, SQLiteConstraint)
- [x] `getLastInsertRowID()` support
- [x] Thread safety (`.Serialized` threading mode)
- [x] Inline DB test suite (13 tests)
- [ ] Connection pool management
- [ ] Transaction middleware / explicit transaction API
- [ ] Migration runner with version tracking

### Input Validation & Security
- [x] DB route auth (auth blocks `/admin` and `/db/*`)
- [x] Input length validation on INSERT/UPDATE fields
- [x] Typed DB error propagation (SQLiteConstraint → 409, SQLiteError → 400)

### SQLite Route Handlers
- [x] `POST /db/init` — create users table
- [x] `GET /db/users` — list all users (with `?limit=N&offset=M` pagination)
- [x] `GET /db/users/:id` — get single user
- [x] `POST /db/users` — create user (with input validation)
- [x] Pagination on `GET /db/users` (prevent OOM)
- [x] Error recovery in `getDb()` (return error instead of panic)

### Future
- [ ] Redis integration
- [ ] In-memory cache layer
- [ ] Session storage (memory, Redis, DB)

## 12. Authentication & Authorization

- [ ] Basic Auth middleware
- [ ] Bearer / JWT middleware
- [ ] OAuth 2.0 / OIDC integration
- [ ] API key authentication
- [ ] Session-based auth
- [ ] Role-based access control (RBAC)
- [ ] Permission middleware
- [ ] Login rate limiting
- [ ] Password hashing helpers

## 13. Real-time Communication

- [ ] WebSocket server (`ctx.upgrade()`)
- [ ] Server-Sent Events (SSE)
- [ ] WebSocket broadcast / pub-sub
- [ ] WebSocket room management
- [ ] WebSocket authentication

## 14. API Features

- [x] JSON responses
- [x] RESTful resource routing
- [ ] Content negotiation
- [ ] Pagination helpers
- [ ] Sorting & filtering conventions
- [ ] API versioning (URL prefix / Accept header)
- [ ] HATEOAS / hypermedia support
- [ ] OpenAPI / Swagger doc generation
- [ ] GraphQL integration (optional)

## 15. Template Rendering

- [ ] Server-side template engine
- [ ] Template inheritance / layouts
- [ ] Template caching
- [ ] Custom template functions
- [ ] Auto-escaping (XSS prevention)
- [ ] Multiple template engines (if applicable)

## 16. CLI & Tooling

- [ ] Project scaffolding (`zig init` for web)
- [ ] Code generator (resource scaffold)
- [ ] Database migration CLI
- [ ] Route listing CLI
- [ ] Development server CLI
- [ ] Production deployment checks

## 17. Testing

- [ ] Test request builder (mock HTTP requests)
- [ ] Test response assertions
- [ ] In-process test server
- [ ] Middleware unit tests
- [ ] Integration test helpers
- [ ] Benchmarking harness
- [ ] Fuzz testing support

## 18. Integration / Extensibility

- [ ] Plugin system
- [ ] Custom Io implementation support
- [ ] Third-party middleware registry
- [ ] Event hooks / lifecycle callbacks
- [ ] Service container / dependency injection

---

**Legend:** `[x]` = implemented, `[ ]` = planned
