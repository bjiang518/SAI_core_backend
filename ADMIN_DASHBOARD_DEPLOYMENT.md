# Admin Dashboard Deployment Guide (Railway)

Complete guide for deploying the StudyAI Admin Dashboard to Railway.

## Prerequisites

- Railway account (https://railway.app)
- GitHub repository access
- Admin JWT secret configured in backend

## Step 1: Prepare the Backend

### 1.1 Add Admin JWT Secret to Railway Backend

1. Go to your existing backend Railway project
2. Navigate to **Variables** tab
3. Add new environment variable:
   ```
   ADMIN_JWT_SECRET=<generate-secure-secret>
   ```
4. To generate a secure secret:
   ```bash
   node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"
   ```

### 1.2 Deploy Backend with Admin Routes

The admin routes are already integrated in your backend (`01_core_backend/src/gateway/routes/admin-routes.js`).

Push your changes to trigger Railway auto-deployment:

```bash
cd 01_core_backend
git add .
git commit -m "feat: Add admin dashboard API endpoints"
git push origin main
```

Wait for Railway to complete the deployment (usually 2-3 minutes).

### 1.3 Create Initial Admin User

Once backend is deployed, create your first admin user:

**Option A: Using curl (Development)**

```bash
curl -X POST https://sai-backend-production.up.railway.app/api/admin/setup/create-admin \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@studyai.com",
    "password": "YourSecurePassword123!",
    "name": "Admin User"
  }'
```

**Option B: Direct Database Insert (Production)**

Connect to your Railway PostgreSQL and run:

```sql
-- Create admin_users table
CREATE TABLE IF NOT EXISTS admin_users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  name VARCHAR(255),
  role VARCHAR(50) DEFAULT 'admin',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_login TIMESTAMPTZ
);

-- Insert admin user (replace password hash with bcrypt hash)
-- Generate hash: node -e "const bcrypt=require('bcrypt'); bcrypt.hash('YourPassword', 10, (e,h) => console.log(h))"
INSERT INTO admin_users (email, password_hash, name, role)
VALUES (
  'admin@studyai.com',
  '$2b$10$..your-bcrypt-hash-here..',
  'Admin User',
  'admin'
);
```

---

## Step 2: Deploy Dashboard to Railway

### 2.1 Create New Railway Project

1. Go to https://railway.app
2. Click **"New Project"**
3. Select **"Deploy from GitHub repo"**
4. Choose your StudyAI repository
5. **IMPORTANT**: Set root directory to `03_admin_dashboard`

### 2.2 Configure Build Settings

Railway should auto-detect Next.js, but verify:

- **Build Command**: `npm run build`
- **Start Command**: `npm start`
- **Install Command**: `npm install`
- **Root Directory**: `03_admin_dashboard`

If not auto-detected, add these manually in Settings → Deploy.

### 2.3 Set Environment Variables

In Railway dashboard → Variables tab, add:

```bash
# Backend API URL
NEXT_PUBLIC_API_URL=https://sai-backend-production.up.railway.app

# NextAuth Configuration
NEXTAUTH_URL=https://your-dashboard.railway.app
NEXTAUTH_SECRET=<generate-new-secret>

# Production mode
NODE_ENV=production
```

To generate NEXTAUTH_SECRET:
```bash
openssl rand -base64 32
```

### 2.4 Deploy

Click **"Deploy"** and Railway will:
1. Clone your repository
2. Install dependencies
3. Build Next.js app
4. Deploy to Railway's infrastructure

Deployment typically takes 3-5 minutes.

### 2.5 Get Your Dashboard URL

After deployment completes:
1. Go to **Settings** → **Networking**
2. You'll see a URL like: `studyai-admin-dashboard-production.up.railway.app`
3. Update `NEXTAUTH_URL` environment variable with this URL
4. Redeploy if needed

---

## Step 3: Configure Custom Domain (Optional)

### 3.1 Add Custom Domain in Railway

1. Go to Railway dashboard → **Settings** → **Networking**
2. Click **"Custom Domain"**
3. Enter: `admin.studyai.com`
4. Railway will provide a CNAME target

### 3.2 Update DNS Records

In your domain registrar (GoDaddy, Namecheap, Cloudflare, etc.):

1. Add CNAME record:
   ```
   Type: CNAME
   Name: admin
   Value: <railway-provided-cname>
   TTL: 3600
   ```

2. Wait for DNS propagation (5-60 minutes)

### 3.3 Update Environment Variables

Update `NEXTAUTH_URL`:
```bash
NEXTAUTH_URL=https://admin.studyai.com
```

Redeploy the dashboard.

---

## Step 4: Test the Dashboard

### 4.1 Access the Dashboard

1. Open your dashboard URL: `https://admin.studyai.com` (or Railway URL)
2. You should see the login page

### 4.2 Login with Admin Credentials

Use the credentials you created in Step 1.3:
- Email: `admin@studyai.com`
- Password: `YourSecurePassword123!`

### 4.3 Verify All Pages Work

- ✅ **Overview**: Check if metrics are displayed
- ✅ **Users**: Verify user list loads
- ✅ **System Health**: Confirm service status
- ✅ **Reports**: Check reports archive

---

## Step 5: Secure the Dashboard (Production)

### 5.1 IP Whitelisting (Optional)

Add to backend admin routes if you want to restrict access:

```javascript
// In admin-routes.js, add IP whitelist check
const ALLOWED_IPS = (process.env.ADMIN_IP_WHITELIST || '').split(',');

function checkIPWhitelist(request, reply) {
  if (ALLOWED_IPS.length > 0) {
    const clientIP = request.headers['x-forwarded-for'] || request.ip;
    if (!ALLOWED_IPS.includes(clientIP)) {
      return reply.code(403).send({ error: 'Access denied' });
    }
  }
}
```

### 5.2 HTTPS Only

Railway automatically provides HTTPS. Ensure your custom domain also uses HTTPS.

### 5.3 Strong Passwords

Enforce strong passwords for all admin users:
- Minimum 12 characters
- Mix of uppercase, lowercase, numbers, symbols

### 5.4 Rate Limiting

Admin routes already have authentication, but you can add extra rate limiting:

```javascript
fastify.register(require('@fastify/rate-limit'), {
  max: 10, // 10 requests
  timeWindow: '1 minute'
});
```

---

## Troubleshooting

### Issue: Dashboard shows 500 errors

**Solution**:
1. Check Railway logs: `railway logs --service=admin-dashboard`
2. Verify `NEXT_PUBLIC_API_URL` is correct
3. Ensure backend is deployed and running

### Issue: Login fails with "Invalid credentials"

**Solution**:
1. Verify admin user was created in database
2. Check `ADMIN_JWT_SECRET` is set in backend
3. Try recreating admin user

### Issue: Build fails on Railway

**Solution**:
1. Verify root directory is set to `03_admin_dashboard`
2. Check build logs for specific errors
3. Try deploying from a clean branch

### Issue: Cannot access backend API

**Solution**:
1. Check CORS settings in backend
2. Verify backend URL is accessible
3. Check network tab in browser dev tools for errors

### Issue: "NEXTAUTH_URL environment variable is not set"

**Solution**:
1. Add `NEXTAUTH_URL` to Railway environment variables
2. Redeploy the dashboard

---

## Monitoring & Maintenance

### Check Dashboard Health

```bash
curl https://admin.studyai.com/api/health
```

### View Logs

In Railway dashboard → **Deployments** → **View Logs**

### Update Dashboard

```bash
cd 03_admin_dashboard
# Make changes
git add .
git commit -m "Update dashboard"
git push origin main
# Railway auto-deploys
```

### Update Backend API

```bash
cd 01_core_backend
# Update admin-routes.js
git add .
git commit -m "Update admin API"
git push origin main
# Railway auto-deploys
```

---

## Cost Estimation (Railway)

**Hobby Plan (Free Tier)**:
- $5/month credit
- Sufficient for small dashboards with <1000 requests/day

**Developer Plan ($5-20/month)**:
- Pay for what you use
- Typical admin dashboard: $5-10/month
- Auto-scales with usage

---

## Security Checklist

Before going to production:

- [ ] Admin JWT secret is strong and unique
- [ ] Default admin password changed
- [ ] HTTPS enabled (automatic on Railway)
- [ ] Environment variables secured
- [ ] IP whitelist configured (if needed)
- [ ] Rate limiting enabled
- [ ] Logs monitored regularly
- [ ] Backup admin credentials stored securely

---

## Next Steps

1. **Add More Admin Users**:
   ```sql
   INSERT INTO admin_users (email, password_hash, name)
   VALUES ('user@studyai.com', '<bcrypt-hash>', 'User Name');
   ```

2. **Customize Dashboard**:
   - Edit pages in `03_admin_dashboard/app/(dashboard)/dashboard/`
   - Modify components in `components/`

3. **Add Real-Time Data**:
   - Implement polling in frontend
   - Or use WebSockets for live updates

4. **Set Up Alerts**:
   - Configure Railway alerts for downtime
   - Add Sentry for error tracking

---

## Support

For issues or questions:
- Check Railway docs: https://docs.railway.app
- Review dashboard README: `03_admin_dashboard/README.md`
- Check backend logs in Railway dashboard

---

**Deployment Complete!** 🎉

Your admin dashboard is now live and accessible at your configured URL.
