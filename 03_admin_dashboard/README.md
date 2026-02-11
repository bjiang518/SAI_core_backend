# StudyAI Admin Dashboard

Modern admin dashboard for monitoring and managing the StudyAI platform.

## Features

- **Overview Dashboard**: Real-time metrics and system health
- **User Management**: View and search all registered users
- **System Health**: Monitor services, database, and performance
- **Reports Archive**: Access generated parent reports

## Tech Stack

- **Framework**: Next.js 14 with App Router
- **Language**: TypeScript
- **Styling**: Tailwind CSS
- **Components**: Custom UI components (Button, Card, Badge, etc.)
- **Charts**: Recharts for data visualization
- **Authentication**: JWT-based auth with localStorage

## Project Structure

```
03_admin_dashboard/
├── app/
│   ├── (dashboard)/        # Protected dashboard routes
│   │   ├── dashboard/
│   │   │   ├── page.tsx    # Overview page
│   │   │   ├── users/      # User management
│   │   │   ├── system/     # System health
│   │   │   └── reports/    # Reports archive
│   │   └── layout.tsx      # Dashboard layout with sidebar
│   ├── login/              # Login page
│   ├── layout.tsx          # Root layout
│   └── globals.css         # Global styles
├── components/
│   ├── ui/                 # Base UI components
│   │   ├── button.tsx
│   │   ├── card.tsx
│   │   └── badge.tsx
│   └── dashboard/          # Dashboard-specific components
│       ├── Sidebar.tsx
│       └── MetricCard.tsx
├── lib/
│   ├── api.ts             # API client and endpoints
│   └── utils.ts           # Utility functions
└── types/
    └── index.ts           # TypeScript type definitions
```

## Development

### Prerequisites

- Node.js 18+
- npm or yarn

### Installation

```bash
cd 03_admin_dashboard
npm install
```

### Environment Variables

Create a `.env.local` file:

```bash
NEXT_PUBLIC_API_URL=https://sai-backend-production.up.railway.app
NEXTAUTH_URL=http://localhost:3000
NEXTAUTH_SECRET=your-secret-here
```

### Running Locally

```bash
npm run dev
```

**Note**: If you encounter `EPERM: operation not permitted` errors on macOS, this is due to security restrictions. Try:

1. **Use sudo** (not recommended for development):
   ```bash
   sudo npm run dev
   ```

2. **Use a different port**:
   ```bash
   PORT=8080 npm run dev
   ```

3. **Deploy directly to Railway** (recommended):
   See deployment section below.

### Building for Production

```bash
npm run build
npm start
```

## Deployment to Railway

### Step 1: Create Railway Project

1. Go to [railway.app](https://railway.app)
2. Create a new project
3. Select "Deploy from GitHub repo"

### Step 2: Configure Build Settings

In Railway dashboard:

- **Build Command**: `npm run build`
- **Start Command**: `npm start`
- **Install Command**: `npm install`

### Step 3: Set Environment Variables

In Railway project settings, add:

```bash
NEXT_PUBLIC_API_URL=https://sai-backend-production.up.railway.app
NEXTAUTH_URL=https://your-dashboard-url.railway.app
NEXTAUTH_SECRET=generate-a-secure-random-string
```

### Step 4: Deploy

Push to your main branch and Railway will auto-deploy.

### Step 5: Set Custom Domain (Optional)

1. Go to Railway project settings
2. Add custom domain: `admin.studyai.com`
3. Update DNS CNAME record to point to Railway URL

## Current Status

### ✅ Completed (Phase 1)

- [x] Project setup with Next.js 14 + TypeScript + Tailwind
- [x] UI component library (Button, Card, Badge)
- [x] Dashboard layout with sidebar navigation
- [x] Login page (mock authentication)
- [x] Overview page with metrics cards
- [x] Users management page
- [x] System Health monitoring page
- [x] Reports archive page

### 🚧 In Progress

- [ ] Backend admin API endpoints
- [ ] Real data integration (currently showing mock data)
- [ ] JWT authentication implementation

### 📋 Planned (Phase 2)

- [ ] Real-time data updates (polling/websockets)
- [ ] Advanced filtering and search
- [ ] Data export (CSV/JSON)
- [ ] Mobile responsive optimizations
- [ ] Dark mode support

## Backend Integration

The dashboard requires backend API endpoints at `/api/admin/*`. These need to be implemented in the backend:

### Required Endpoints

```
POST /api/admin/auth/login           - Admin authentication
GET  /api/admin/stats/overview       - Dashboard metrics
GET  /api/admin/users/list           - User list with pagination
GET  /api/admin/users/:id/details    - User details
GET  /api/admin/users/:id/activity   - User activity
GET  /api/admin/system/services      - Service health status
GET  /api/admin/system/errors        - Recent errors
GET  /api/admin/system/performance   - API performance metrics
```

See `ADMIN_DASHBOARD_PLAN.md` in the root directory for complete API specifications.

## Authentication

Currently using mock authentication for development. To implement real auth:

1. Add admin users table to database
2. Implement JWT generation in backend `/api/admin/auth/login`
3. Update `lib/api.ts` to use real authentication

## Troubleshooting

### Port Permission Errors

If you see `EPERM: operation not permitted` on macOS:
- This is a known macOS security restriction
- Deploy to Railway instead (recommended)
- Or use `sudo` (not recommended)

### Build Errors

If you encounter build errors:
```bash
rm -rf .next node_modules
npm install
npm run build
```

### TypeScript Errors

Ensure all dependencies are installed:
```bash
npm install --save-dev @types/node @types/react @types/react-dom
```

## Contributing

This dashboard is part of the StudyAI platform. For questions or issues, contact the dev team.

## License

Proprietary - StudyAI Platform
