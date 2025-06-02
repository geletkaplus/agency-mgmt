import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
django.setup()

from django.contrib.auth.models import User
from agency.models import Company, UserProfile

# Create superuser if doesn't exist
if not User.objects.filter(username='admin').exists():
    user = User.objects.create_superuser('admin', 'admin@example.com', 'admin123')
    print("Superuser created: admin/admin123")
    
    # Create company
    company, created = Company.objects.get_or_create(
        code='MAIN',
        defaults={'name': 'Main Company'}
    )
    
    # Create user profile
    UserProfile.objects.get_or_create(
        user=user,
        defaults={
            'company': company,
            'role': 'leadership',
            'status': 'full_time',
            'is_project_manager': True
        }
    )
    print("User profile created for admin")
else:
    print("Superuser already exists")
