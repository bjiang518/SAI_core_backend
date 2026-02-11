# StudyAI Admin Dashboard - Implementation Plan

## Project Overview

A modern, secure web dashboard for monitoring and managing the StudyAI platform. Built as a completely separate application to ensure zero risk to existing infrastructure.

**Project Status**: Planning Phase
**Estimated Complexity**: Medium
**Safety Level**: High (no modifications to existing backend core functionality)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Admin Dashboard                          │
│                   (Next.js 14 + React)                       │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │Overview  │  │ Users    │  │ System   │  │ Reports  │   │
│  │ Page     │  │ Mgmt     │  │ Health   │  │ Archive  │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         │ REST API Calls
                         │ (JWT Authentication)
                         ↓
┌─────────────────────────────────────────────────────────────┐
│              Backend Gateway (Fastify)                       │
│                                                              │
│  Existing APIs          │  New Admin APIs (Read-Only)       │
│  • /health              │  • /api/admin/stats                │
│  • /metrics             │  • /api/admin/users/list           │
│  • /api/auth/*          │  • /api/admin/sessions/recent      │
│                         │  • /api/admin/errors/summary       │
└────────────────────────┴──────────────────────────────────────┘
                         │
                         ↓
              ┌──────────────────────┐
              │  PostgreSQL Database │
              │  (Existing Schema)   │
              └──────────────────────┘
```

---

## Technology Stack

### Frontend (Admin Dashboard)

| Technology | Version | Purpose |
|-----------|---------|---------|
| **Next.js** | 14.x | React framework with SSR + API routes |
| **React** | 18.x | UI library |
| **TypeScript** | 5.x | Type safety |
| **Tailwind CSS** | 3.x | Styling |
| **Shadcn/ui** | Latest | Beautiful UI components |
| **Recharts** | 2.x | Data visualization |
| **Tanstack Query** | 5.x | Data fetching and caching |
| **Zustand** | 4.x | State management |
| **Axios** | 1.x | HTTP client |
| **NextAuth.js** | 4.x | Authentication |

### Backend (New Admin Endpoints)

| Technology | Purpose |
|-----------|---------|
| **Fastify** | Existing - add new routes only |
| **JWT** | Admin authentication |
| **PostgreSQL** | Existing - no schema changes needed |

### Deployment

| Component | Platform | URL |
|-----------|----------|-----|
| **Dashboard** | Vercel (Recommended) or Railway | `admin.studyai.com` |
| **Backend** | Railway (Existing) | `sai-backend-production.up.railway.app` |

---

## Dashboard Features

### 1. Overview/Home Page 🏠

**Purpose**: At-a-glance system health and key metrics

**Metrics to Display**:
- 👥 Total Users (with 7-day growth %)
- 📝 Homework Sessions Today (with trend chart)
- 🤖 AI Requests/Hour (real-time)
- ⚡ Avg Response Time (last hour)
- ❌ Error Rate (%)
- 💾 Database Status (connection pool)
- 🔴 Redis Cache Hit Rate

**UI Components**:
- 4x2 grid of metric cards with color-coded indicators
- Line charts for trends (last 7 days)
- Health status badges (🟢 Healthy, 🟡 Degraded, 🔴 Down)
- Quick links to detailed pages

**Data Sources**:
- Existing: `/health`, `/metrics`
- New: `GET /api/admin/stats/overview`

---

### 2. User Management Page 👥

**Purpose**: View and search users

**Features**:
- User list table with pagination
  - Columns: ID, Name, Email, Join Date, Last Active, Subscription Status
- Search by name/email
- Filters: Date range, subscription status
- User detail modal:
  - Profile info
  - Activity summary
  - Recent sessions
  - Subject progress

**Actions** (Phase 2):
- View user activity
- Manual report generation (for testing)
- ⚠️ Future: Disable/enable account (with confirmation)

**Data Sources**:
- New: `GET /api/admin/users/list?page=1&limit=50&search=...`
- New: `GET /api/admin/users/:userId/details`
- New: `GET /api/admin/users/:userId/activity`

---

### 3. System Health Page 🏥

**Purpose**: Deep dive into system status

**Sections**:

**A. Service Health**
- Backend Gateway: 🟢 Online
- AI Engine: 🟢 Online
- PostgreSQL: 🟢 Connected (12/20 connections used)
- Redis: 🟢 Connected (23.4 MB used)

**B. API Performance**
- Endpoint-level metrics table:
  - Route, Method, Avg Response Time, Request Count, Error Rate
- Sort by slowest/most used

**C. Error Monitoring**
- Recent errors table (last 100):
  - Timestamp, Endpoint, Error Message, User ID, Stack Trace
- Error rate chart (last 24 hours)

**D. Database Insights**
- Slowest queries (last hour)
- Table sizes
- Index health

**Data Sources**:
- Existing: `/health/detailed`, `/metrics`
- New: `GET /api/admin/system/services`
- New: `GET /api/admin/system/errors?limit=100`
- New: `GET /api/admin/system/performance`

---

### 4. Reports Archive Page 📊

**Purpose**: View generated parent reports

**Features**:
- List of report batches with filters:
  - Date range, report type (weekly/monthly)
- Batch detail view:
  - 8 specialized reports (summary, performance, behavior, etc.)
  - Download as PDF
  - Preview HTML

**Data Sources**:
- Existing: `GET /api/reports/passive/batches`
- Existing: `GET /api/reports/passive/batches/:id`

---

### 5. Sessions Explorer Page 💬 (Phase 2)

**Purpose**: Browse homework sessions and chat conversations

**Features**:
- Sessions list with search/filter
- Session detail viewer:
  - Full conversation thread
  - Images uploaded
  - AI responses
  - Subject detected
- Export session as JSON/PDF

**Data Sources**:
- New: `GET /api/admin/sessions/list`
- New: `GET /api/admin/sessions/:id`

---

### 6. Analytics Dashboard Page 📈 (Phase 2)

**Purpose**: Business and product analytics

**Metrics**:
- User growth chart (last 90 days)
- Most popular subjects
- Peak usage hours
- Retention rate (7-day, 30-day)
- Homework completion rate
- Average session duration

**Data Sources**:
- New: `GET /api/admin/analytics/growth`
- New: `GET /api/admin/analytics/subjects`
- New: `GET /api/admin/analytics/retention`

---

## Backend API Endpoints (New)

All new endpoints will be in a **separate file** to ensure safety:

**File**: `01_core_backend/src/gateway/routes/admin-routes.js`

### Authentication
- `POST /api/admin/auth/login` - Admin login (separate from user auth)

### Overview
- `GET /api/admin/stats/overview` - Dashboard overview metrics
  ```json
  {
    "totalUsers": 1247,
    "usersGrowth7d": 8.5,
    "sessionsToday": 342,
    "aiRequestsPerHour": 89,
    "avgResponseTime": 234,
    "errorRate": 0.3,
    "databaseStatus": "healthy",
    "cacheHitRate": 87.2
  }
  ```

### Users
- `GET /api/admin/users/list?page=1&limit=50&search=email` - Paginated user list
- `GET /api/admin/users/:userId/details` - User profile + stats
- `GET /api/admin/users/:userId/activity` - User activity history

### System Health
- `GET /api/admin/system/services` - Service status (backend, AI, DB, Redis)
- `GET /api/admin/system/errors?limit=100` - Recent errors
- `GET /api/admin/system/performance` - API endpoint performance metrics

### Sessions (Phase 2)
- `GET /api/admin/sessions/list?page=1&subject=math` - List sessions
- `GET /api/admin/sessions/:id` - Session details

### Analytics (Phase 2)
- `GET /api/admin/analytics/growth?days=90` - User growth data
- `GET /api/admin/analytics/subjects` - Subject popularity
- `GET /api/admin/analytics/retention` - Retention metrics

---

## Authentication & Security

### Admin User Management

**Approach**: Separate admin user table (not part of regular users)

**Database Schema** (new table):
```sql
CREATE TABLE admin_users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  name VARCHAR(255),
  role VARCHAR(50) DEFAULT 'admin', -- 'admin', 'superadmin', 'viewer'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_login TIMESTAMPTZ
);
```

**Initial Admin Creation**:
```bash
# Run script to create first admin
npm run create-admin -- --email=admin@studyai.com --password=securepass
```

### JWT Authentication Flow

1. Admin opens `admin.studyai.com/login`
2. Enters admin credentials
3. Backend validates against `admin_users` table
4. Returns JWT with `role: 'admin'`
5. Dashboard stores JWT in localStorage
6. All API requests include: `Authorization: Bearer <jwt>`
7. Backend middleware validates JWT and checks `role === 'admin'`

### Security Measures

✅ **Admin middleware** on all `/api/admin/*` routes
✅ **Rate limiting**: 100 requests/minute per admin
✅ **HTTPS only** in production
✅ **IP whitelist** (optional): Restrict to office/VPN IPs
✅ **Audit logging**: Log all admin actions
✅ **CORS**: Only allow dashboard domain
✅ **No destructive actions**: Read-only by default (Phase 1)

---

## Project Structure

```
studyai-admin-dashboard/
├── src/
│   ├── app/                         # Next.js 14 App Router
│   │   ├── (auth)/
│   │   │   └── login/
│   │   │       └── page.tsx         # Login page
│   │   ├── (dashboard)/
│   │   │   ├── layout.tsx           # Dashboard layout with sidebar
│   │   │   ├── page.tsx             # Overview page
│   │   │   ├── users/
│   │   │   │   ├── page.tsx         # Users list
│   │   │   │   └── [id]/page.tsx    # User detail
│   │   │   ├── system/
│   │   │   │   └── page.tsx         # System health
│   │   │   ├── reports/
│   │   │   │   └── page.tsx         # Reports archive
│   │   │   └── analytics/
│   │   │       └── page.tsx         # Analytics (Phase 2)
│   │   └── api/
│   │       └── auth/[...nextauth]/route.ts  # NextAuth config
│   ├── components/
│   │   ├── ui/                      # Shadcn components (buttons, cards, etc.)
│   │   ├── dashboard/
│   │   │   ├── MetricCard.tsx       # Reusable metric display
│   │   │   ├── StatusBadge.tsx      # Health status indicator
│   │   │   ├── TrendChart.tsx       # Line chart wrapper
│   │   │   └── Sidebar.tsx          # Navigation sidebar
│   │   └── layouts/
│   │       └── DashboardLayout.tsx  # Main layout wrapper
│   ├── lib/
│   │   ├── api.ts                   # API client (Axios instance)
│   │   ├── auth.ts                  # Auth utilities
│   │   └── utils.ts                 # Helper functions
│   ├── hooks/
│   │   ├── useOverviewStats.ts      # React Query hook for overview
│   │   ├── useUsers.ts              # React Query hook for users
│   │   └── useSystemHealth.ts       # React Query hook for health
│   ├── types/
│   │   ├── user.ts                  # User type definitions
│   │   ├── stats.ts                 # Stats type definitions
│   │   └── api.ts                   # API response types
│   └── store/
│       └── authStore.ts             # Zustand auth state
├── public/
│   └── logo.svg                     # StudyAI logo
├── .env.local                       # Environment variables
├── next.config.js                   # Next.js configuration
├── tailwind.config.ts               # Tailwind configuration
├── tsconfig.json                    # TypeScript configuration
└── package.json                     # Dependencies
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1) ✅

**Goals**: Basic dashboard with read-only data

**Tasks**:
1. ✅ Create Next.js project with TypeScript + Tailwind
2. ✅ Set up Shadcn/ui components
3. ✅ Build authentication (login page + JWT)
4. ✅ Create dashboard layout with sidebar
5. ✅ Implement Overview page with basic metrics
6. ✅ Add backend admin routes (users list, overview stats)
7. ✅ Deploy to Vercel (test environment)

**Deliverables**:
- Working dashboard at `studyai-admin-dashboard.vercel.app`
- Login with test admin account
- Overview page showing basic metrics

---

### Phase 2: Core Features (Week 2) 📊

**Goals**: User management and system health

**Tasks**:
1. Build Users page with table and search
2. Implement System Health page with service status
3. Add Reports Archive page (use existing API)
4. Create user detail modal with activity
5. Add error monitoring section
6. Implement real-time updates (polling every 30s)

**Deliverables**:
- Functional user management interface
- System health monitoring
- Reports viewing capability

---

### Phase 3: Advanced Features (Week 3) 🚀

**Goals**: Analytics and enhanced functionality

**Tasks**:
1. Build Analytics page with charts
2. Add Sessions Explorer
3. Implement data export (CSV/JSON)
4. Add admin audit logging
5. Performance optimization (caching)
6. Mobile responsive design

**Deliverables**:
- Full-featured admin dashboard
- Mobile-friendly UI
- Export capabilities

---

### Phase 4: Polish & Production (Week 4) 🎨

**Goals**: Production-ready deployment

**Tasks**:
1. Security audit (HTTPS, rate limiting, CORS)
2. Set up custom domain (`admin.studyai.com`)
3. Add monitoring and error tracking (Sentry)
4. Write admin user documentation
5. Load testing and optimization
6. Final deployment to production

**Deliverables**:
- Production dashboard at `admin.studyai.com`
- Admin documentation
- Monitoring and alerts configured

---

## Environment Variables

### Dashboard (.env.local)

```bash
# Backend API
NEXT_PUBLIC_API_URL=https://sai-backend-production.up.railway.app

# NextAuth
NEXTAUTH_URL=http://localhost:3000
NEXTAUTH_SECRET=your-nextauth-secret

# Optional: Monitoring
NEXT_PUBLIC_SENTRY_DSN=your-sentry-dsn
```

### Backend (Railway - New Variables)

```bash
# Admin Auth
ADMIN_JWT_SECRET=different-from-user-jwt-secret

# Optional: IP Whitelist
ADMIN_IP_WHITELIST=123.456.789.0/24
```

---

## Deployment Strategy

### Development Environment

```bash
# Local development
npm run dev  # Runs on localhost:3000
```

### Staging Environment (Vercel)

- **URL**: `studyai-admin-dashboard-staging.vercel.app`
- **Purpose**: Testing before production
- **Auto-deploy**: On push to `develop` branch

### Production Environment (Vercel + Custom Domain)

- **URL**: `admin.studyai.com`
- **DNS**: Add CNAME record pointing to Vercel
- **Auto-deploy**: On push to `main` branch
- **Environment**: Production environment variables

---

## Safety Checklist

✅ **Dashboard is a separate repository** (not in `StudyAI_Workspace_GitHub`)
✅ **Backend changes are additive only** (new routes, no modifications)
✅ **Admin routes in separate file** (`admin-routes.js`)
✅ **Read-only by default** (no delete/update in Phase 1)
✅ **Authentication required** for all admin endpoints
✅ **Can be disabled instantly** (unregister routes if needed)
✅ **No changes to existing API contracts** (iOS app unaffected)
✅ **Separate database table for admins** (no user table changes)
✅ **Deploy separately** (Vercel, not Railway backend)

---

## Rollback Plan

If anything goes wrong:

1. **Dashboard issues**: Stop Vercel deployment, revert commit
2. **Backend issues**: Comment out `admin-routes.js` registration
3. **Database issues**: Drop `admin_users` table (won't affect main app)
4. **Complete rollback**: Delete dashboard deployment, remove backend routes

**Estimated rollback time**: < 5 minutes

---

## Monitoring & Maintenance

### Dashboard Monitoring
- **Uptime**: Vercel analytics
- **Errors**: Sentry error tracking
- **Performance**: Vercel Web Vitals

### Backend Monitoring
- **Admin API usage**: Prometheus metrics
- **Failed login attempts**: Audit logs
- **Slow queries**: Query performance tracking

---

## Success Metrics

**Technical**:
- ✅ Dashboard loads in < 2 seconds
- ✅ All API responses < 500ms
- ✅ Zero impact on iOS app performance
- ✅ 99.9% uptime

**Functional**:
- ✅ View system health in real-time
- ✅ Search and view all users
- ✅ Monitor API performance
- ✅ Access parent reports easily

---

## Next Steps

1. **Review this plan** and approve architecture
2. **Create new repository** for dashboard (or subfolder in monorepo)
3. **Start Phase 1** implementation:
   - Set up Next.js project
   - Build login page
   - Add first backend endpoints
4. **Iterate and deploy**

---

## Questions to Resolve Before Starting

1. **Repository structure**: New repo or subfolder in existing repo?
2. **Admin credentials**: Who should have initial admin access?
3. **Domain preference**: `admin.studyai.com` or `studyai.com/admin`?
4. **Deployment platform**: Vercel (recommended) or Railway?
5. **Features priority**: Any specific features needed urgently?

---

## References

- **Backend Docs**: See `CLAUDE.md` for backend architecture
- **iOS App**: See `02_ios_app/StudyAI/README.md`
- **Next.js Docs**: https://nextjs.org/docs
- **Shadcn/ui**: https://ui.shadcn.com
- **Recharts**: https://recharts.org

---

**Document Version**: 1.0
**Last Updated**: 2026-02-11
**Author**: Claude Code
**Status**: Ready for Implementation
