# StudyMates Company Website

A modern, responsive website for StudyMates - Your AI-Powered Learning Companion.

## 🌐 Live Site

**Domain:** study-mates.net

## 📁 File Structure

```
website/
├── index.html          # Main landing page
├── privacy.html        # Privacy Policy page
├── terms.html          # Terms of Service page
├── styles.css          # All CSS styling
├── script.js           # JavaScript functionality
└── README.md           # This file
```

## ✨ Features

- **Responsive Design** - Works perfectly on desktop, tablet, and mobile
- **Modern UI** - Clean, professional design with smooth animations
- **Fast Loading** - Optimized for performance with minimal dependencies
- **SEO Optimized** - Proper meta tags and semantic HTML
- **Accessible** - WCAG compliant navigation and content structure

## 🎨 Design

- **Color Scheme:**
  - Primary: #4A90E2 (Blue)
  - Secondary: #FF6B9D (Pink)
  - Accent: #9B59B6 (Purple)

- **Typography:** Inter font family from Google Fonts

- **Animations:** Smooth scroll-based animations using Intersection Observer API

## 📄 Pages

1. **Home (index.html)**
   - Hero section with key stats
   - Features showcase (6 main features)
   - How It Works (3-step process)
   - Testimonials
   - Call-to-action section
   - Footer with links

2. **Privacy Policy (privacy.html)**
   - Comprehensive privacy information
   - COPPA compliance for children under 13
   - Data security and user rights

3. **Terms of Service (terms.html)**
   - User agreements and policies
   - Academic integrity guidelines
   - Subscription and payment terms

## 🚀 Deployment Instructions

### Option 1: Traditional Web Hosting (Recommended)

**Prerequisites:**
- Access to your domain registrar (where you bought study-mates.net)
- Web hosting account (Bluehost, SiteGround, HostGator, etc.)

**Steps:**

1. **Upload Files to Hosting:**
   ```bash
   # Via FTP/SFTP client (FileZilla, Cyberduck):
   # Connect to your hosting server
   # Upload all files from /website folder to public_html/ or www/
   ```

2. **Configure Domain:**
   - Log into your domain registrar
   - Point domain to your hosting nameservers
   - Wait 24-48 hours for DNS propagation

3. **Test:**
   - Visit https://study-mates.net
   - Check all pages load correctly
   - Test on mobile devices

### Option 2: GitHub Pages (Free)

1. **Create GitHub Repository:**
   ```bash
   cd /Users/bojiang/StudyAI_Workspace_GitHub/website
   git init
   git add .
   git commit -m "Initial commit: StudyMates website"
   git branch -M main
   git remote add origin https://github.com/YOUR_USERNAME/studymates-website.git
   git push -u origin main
   ```

2. **Enable GitHub Pages:**
   - Go to repository Settings
   - Scroll to "Pages" section
   - Source: Deploy from main branch
   - Custom domain: study-mates.net

3. **Configure Custom Domain:**
   - Add CNAME file to repository:
     ```bash
     echo "study-mates.net" > CNAME
     git add CNAME
     git commit -m "Add custom domain"
     git push
     ```
   - In your domain registrar, add DNS records:
     ```
     Type: CNAME
     Name: www
     Value: YOUR_USERNAME.github.io

     Type: A (4 records)
     Name: @
     Values:
       185.199.108.153
       185.199.109.153
       185.199.110.153
       185.199.111.153
     ```

### Option 3: Netlify (Easiest, Free)

1. **Sign up at Netlify.com**

2. **Deploy:**
   - Drag and drop the `website` folder into Netlify
   - Or connect to GitHub repository

3. **Configure Custom Domain:**
   - Site Settings → Domain Management
   - Add custom domain: study-mates.net
   - Follow DNS configuration instructions

4. **Enable HTTPS:**
   - Automatic with Netlify's free SSL certificate

### Option 4: Vercel (Modern, Free)

1. **Install Vercel CLI:**
   ```bash
   npm i -g vercel
   ```

2. **Deploy:**
   ```bash
   cd /Users/bojiang/StudyAI_Workspace_GitHub/website
   vercel
   ```

3. **Add Custom Domain:**
   ```bash
   vercel domains add study-mates.net
   ```

4. **Configure DNS** (as prompted by Vercel)

## 🔧 Customization

### Update Content

1. **Change App Store Links:**
   ```html
   <!-- In index.html, replace # with actual App Store URL -->
   <a href="YOUR_APP_STORE_URL" class="btn btn-primary">Download for iOS</a>
   ```

2. **Update Contact Information:**
   ```html
   <!-- In privacy.html and terms.html -->
   <li>Email: privacy@study-mates.net</li>
   ```

3. **Modify Stats:**
   ```html
   <!-- In index.html hero section -->
   <div class="stat">
       <span class="stat-number">10K+</span>
       <span class="stat-label">Students</span>
   </div>
   ```

### Change Colors

Edit `styles.css` root variables:
```css
:root {
    --primary-color: #4A90E2;     /* Change to your blue */
    --secondary-color: #FF6B9D;   /* Change to your pink */
    --accent-color: #9B59B6;      /* Change to your purple */
}
```

## 📱 Mobile Menu

The website includes a fully functional mobile menu that:
- Toggles on hamburger icon click
- Closes when clicking navigation links
- Smooth scrolling to sections

## 🔍 SEO Optimization

**Current meta tags:**
```html
<meta name="description" content="StudyMates - Your AI-Powered Learning Companion...">
<meta name="keywords" content="AI tutor, homework help, study app...">
```

**Recommendations:**
- Add Google Analytics tracking code
- Create sitemap.xml
- Add Open Graph tags for social sharing
- Submit to Google Search Console

## ⚡ Performance

- No heavy frameworks (vanilla JavaScript)
- Google Fonts with `preconnect` for faster loading
- Optimized CSS with minimal animations
- Lazy-loaded intersection observer animations

## 🌐 Browser Support

- Chrome (last 2 versions)
- Firefox (last 2 versions)
- Safari (last 2 versions)
- Edge (last 2 versions)
- Mobile browsers (iOS Safari, Chrome Mobile)

## 📞 Support

For questions or issues:
- Email: support@study-mates.net
- GitHub Issues: [Create an issue]

## 📝 License

Copyright © 2026 StudyMates. All rights reserved.

---

**Built with ❤️ for StudyMates students**
