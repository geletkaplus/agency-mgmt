import os
import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
django.setup()

from agency.models import UserProfile, Project
from django.contrib.auth.models import User

print("🧪 Testing Dashboard Implementation...")

# 1. Check if is_project_manager field exists
try:
    pm_count = UserProfile.objects.filter(is_project_manager=True).count()
    print(f"✅ is_project_manager field works! Found {pm_count} PMs")
except Exception as e:
    print(f"❌ is_project_manager field error: {e}")

# 2. Set some users as PMs
print("\nSetting up test project managers...")
profiles = UserProfile.objects.filter(role__in=['leadership', 'account'])[:2]
for profile in profiles:
    profile.is_project_manager = True
    profile.save()
    print(f"✅ Made {profile.user.get_full_name()} a project manager")

# 3. Assign PMs to projects
print("\nAssigning PMs to projects...")
projects = Project.objects.all()[:3]
pm_users = [p.user for p in UserProfile.objects.filter(is_project_manager=True)]
for i, project in enumerate(projects):
    if pm_users:
        project.project_manager = pm_users[i % len(pm_users)]
        project.save()
        print(f"✅ Assigned {project.project_manager.get_full_name()} to {project.name}")

print("\n✅ Test setup complete!")
print("\nYou can now:")
print("1. Login as superadmin")
print("2. Use the dropdown to switch to a PM or employee view")
print("3. PMs will see their managed projects")
print("4. Employees will see their allocated hours")
