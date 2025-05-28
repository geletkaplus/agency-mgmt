import os
import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
django.setup()

from agency.models import UserProfile, Project
from django.contrib.auth.models import User

print("🧪 Setting up test project managers...")

try:
    # Set some users as PMs
    profiles = UserProfile.objects.filter(role__in=['leadership', 'account'])[:2]
    if not profiles:
        profiles = UserProfile.objects.all()[:2]
        
    for profile in profiles:
        profile.is_project_manager = True
        profile.save()
        print(f"✅ Made {profile.user.get_full_name()} a project manager")

    # Assign PMs to projects
    projects = Project.objects.all()[:3]
    pm_users = [p.user for p in UserProfile.objects.filter(is_project_manager=True)]
    
    if pm_users and projects:
        for i, project in enumerate(projects):
            project.project_manager = pm_users[i % len(pm_users)]
            project.save()
            print(f"✅ Assigned {project.project_manager.get_full_name()} to {project.name}")
    else:
        print("⚠️  No projects or PMs available for assignment")

    print("\n✅ Test setup complete!")
except Exception as e:
    print(f"❌ Error during setup: {e}")
