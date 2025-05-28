import os
import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
django.setup()

from django.db import connection
from agency.models import UserProfile

print("🔧 Checking if is_project_manager field exists...")

# Get all fields from UserProfile
field_names = [f.name for f in UserProfile._meta.get_fields()]

if 'is_project_manager' in field_names:
    print("✅ Field 'is_project_manager' already exists in the model!")
else:
    print("❌ Field 'is_project_manager' not found in model")
    print("   Make sure you've added it to your models.py file!")

# Check database
with connection.cursor() as cursor:
    cursor.execute("PRAGMA table_info(agency_userprofile)")
    columns = cursor.fetchall()
    column_names = [col[1] for col in columns]
    
    if 'is_project_manager' in column_names:
        print("✅ Field exists in database!")
    else:
        print("❌ Field not in database")
        print("   Trying to add it...")
        try:
            cursor.execute("""
                ALTER TABLE agency_userprofile 
                ADD COLUMN is_project_manager BOOLEAN DEFAULT 0 NOT NULL
            """)
            print("✅ Field added to database!")
        except Exception as e:
            print(f"Error adding field: {e}")

print("\nTesting the field...")
try:
    # Test querying with the field
    count = UserProfile.objects.filter(is_project_manager=True).count()
    print(f"✅ Field is working! Found {count} project managers.")
except Exception as e:
    print(f"❌ Error using field: {e}")

print("\nSetting some users as project managers based on role...")
try:
    # Make leadership and account managers into project managers
    updated = UserProfile.objects.filter(
        role__in=['leadership', 'account']
    ).update(is_project_manager=True)
    print(f"✅ Updated {updated} users to be project managers")
except Exception as e:
    print(f"Error updating users: {e}")
