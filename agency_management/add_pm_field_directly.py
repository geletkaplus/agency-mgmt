#!/usr/bin/env python
import os
import sys
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
sys.path.insert(0, os.path.abspath('.'))
django.setup()

from django.db import connection

print("🔧 Adding is_project_manager field directly via SQL...")

try:
    with connection.cursor() as cursor:
        # Check if column already exists
        cursor.execute("PRAGMA table_info(agency_userprofile)")
        columns = cursor.fetchall()
        column_names = [col[1] for col in columns]
        
        if 'is_project_manager' in column_names:
            print("✅ Field 'is_project_manager' already exists!")
        else:
            print("Adding is_project_manager field...")
            cursor.execute("""
                ALTER TABLE agency_userprofile 
                ADD COLUMN is_project_manager BOOLEAN DEFAULT 0 NOT NULL
            """)
            print("✅ Field added successfully!")
            
            # Mark some users as project managers based on their role
            cursor.execute("""
                UPDATE agency_userprofile 
                SET is_project_manager = 1 
                WHERE role IN ('leadership', 'account')
            """)
            print("✅ Updated project managers based on leadership/account roles")
            
    print("\n✅ Done! The field has been added directly to the database.")
    print("You may need to fake the migration if it's still pending:")
    print("python manage.py migrate agency 0010 --fake")
    
except Exception as e:
    print(f"❌ Error: {e}")
