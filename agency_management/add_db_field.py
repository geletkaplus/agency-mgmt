
import os
import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
django.setup()

from django.db import connection

with connection.cursor() as cursor:
    try:
        cursor.execute("ALTER TABLE agency_userprofile ADD COLUMN is_project_manager BOOLEAN DEFAULT 0 NOT NULL")
        print("✅ Field added to database")
    except Exception as e:
        if "duplicate column" in str(e).lower():
            print("✅ Field already exists in database")
        else:
            print(f"⚠️  {e}")
