import os
import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
django.setup()

from django.contrib.auth.models import User
from agency.models import UserProfile, Company
from django.conf import settings

print("🔍 Diagnosing Agency Management Issues\n")

# Check static files settings
print("📁 Static Files Configuration:")
print(f"  STATIC_URL: {settings.STATIC_URL}")
print(f"  STATIC_ROOT: {settings.STATIC_ROOT}")
print(f"  STATICFILES_DIRS: {settings.STATICFILES_DIRS}")
print()

# Check if static directories exist
static_dirs = [
    'static/css',
    'static/js',
    'static/admin/css',
    'static/admin/js',
    'agency/static/css',
    'agency/static/js'
]

print("📂 Static Directory Check:")
for dir_path in static_dirs:
    full_path = os.path.join(settings.BASE_DIR, dir_path)
    exists = os.path.exists(full_path)
    print(f"  {dir_path}: {'✅ Exists' if exists else '❌ Missing'}")
print()

# Check users and profiles
print("👥 User and Profile Check:")
users = User.objects.all()
for user in users:
    has_profile = hasattr(user, 'profile')
    profile = user.profile if has_profile else None
    print(f"  {user.username}:")
    print(f"    - Has profile: {'✅' if has_profile else '❌'}")
    if profile:
        print(f"    - Role: {profile.get_role_display()}")
        print(f"    - Is PM: {'✅' if profile.is_project_manager else '❌'}")
        print(f"    - Company: {profile.company.name}")
print()

# Check session middleware
print("⚙️ Middleware Check:")
if 'django.contrib.sessions.middleware.SessionMiddleware' in settings.MIDDLEWARE:
    print("  ✅ Session middleware is installed")
else:
    print("  ❌ Session middleware is missing!")
print()

# Check templates
print("📄 Template Check:")
template_files = [
    'templates/base.html',
    'templates/dashboard.html',
    'templates/dashboards/pm_dashboard.html',
    'templates/dashboards/employee_dashboard.html',
    'templates/registration/login.html'
]

for template in template_files:
    full_path = os.path.join(settings.BASE_DIR, template)
    exists = os.path.exists(full_path)
    print(f"  {template}: {'✅ Exists' if exists else '❌ Missing'}")

print("\n✅ Diagnosis complete!")
