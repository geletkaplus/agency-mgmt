#!/bin/bash

echo "🔧 Fixing Stuck Migration Issue..."
echo ""

# 1. First, let's check what migrations Django thinks are applied
echo "📋 Step 1: Checking current migration status..."
echo "Run this command:"
echo "python manage.py showmigrations agency"
echo ""
echo "Press Enter after running the above command..."
read

# 2. Check what migration files actually exist
echo "📋 Step 2: Checking actual migration files..."
ls -la agency_management/agency/migrations/00*.py
echo ""

# 3. Let's look for the problematic migration in the database
echo "📋 Step 3: Creating script to check and fix migration records..."
cat > fix_migration_records.py << 'EOF'
#!/usr/bin/env python
import os
import sys
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
sys.path.insert(0, os.path.abspath('.'))
django.setup()

from django.db import connection

print("🔍 Checking migration records in database...\n")

# Check what migrations Django thinks are applied
with connection.cursor() as cursor:
    cursor.execute("SELECT * FROM django_migrations WHERE app='agency' ORDER BY id")
    migrations = cursor.fetchall()
    
    print("Migrations recorded in database:")
    for migration in migrations:
        print(f"  ID: {migration[0]}, App: {migration[1]}, Name: {migration[2]}, Applied: {migration[3]}")

print("\n🔍 Looking for problematic migration...")
problematic = None
for migration in migrations:
    if '0010_alter_monthlycost' in migration[2]:
        problematic = migration
        print(f"❌ Found problematic migration: {migration[2]}")
        break

if problematic:
    print("\n⚠️  To remove this migration record, run:")
    print(f"python manage.py dbshell")
    print(f"DELETE FROM django_migrations WHERE id={problematic[0]};")
    print(".exit")
    print("\nOr run this Python script to do it automatically:")
    
    response = input("\nDo you want to remove this migration record? (y/N): ")
    if response.lower() == 'y':
        with connection.cursor() as cursor:
            cursor.execute(f"DELETE FROM django_migrations WHERE id={problematic[0]}")
            print("✅ Problematic migration record removed!")
            print("\nNow you can run: python manage.py migrate")
else:
    print("✅ No problematic migration found in database")

# Check if there are any pending migrations
print("\n🔍 Checking for actual migration files that need to be applied...")
import os
migration_dir = 'agency_management/agency/migrations'
migration_files = [f for f in os.listdir(migration_dir) if f.endswith('.py') and f != '__init__.py']
migration_files.sort()

print(f"\nMigration files found: {migration_files}")

# Get the last applied migration
if migrations:
    last_applied = migrations[-1][2]
    print(f"\nLast applied migration: {last_applied}")
EOF

chmod +x fix_migration_records.py

# 4. Create the corrected migration file
echo ""
echo "📋 Step 4: Creating corrected migration for is_project_manager..."
cat > agency_management/agency/migrations/0010_add_is_project_manager.py << 'EOF'
# Generated manually for is_project_manager field

from django.db import migrations, models

class Migration(migrations.Migration):

    dependencies = [
        ('agency', '0009_merge_20250528_2047'),
    ]

    operations = [
        migrations.AddField(
            model_name='userprofile',
            name='is_project_manager',
            field=models.BooleanField(default=False, help_text='Can manage projects and see PM dashboard'),
        ),
    ]
EOF

# 5. Create alternative approach using SQL
echo ""
echo "📋 Step 5: Creating direct SQL approach (if migrations still fail)..."
cat > add_pm_field_directly.py << 'EOF'
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
EOF

chmod +x add_pm_field_directly.py

echo ""
echo "✅ Fix scripts created!"
echo ""
echo "🎯 Steps to resolve the issue:"
echo ""
echo "1. Run the migration record checker:"
echo "   python fix_migration_records.py"
echo ""
echo "2. If the problematic migration is in the database, remove it as instructed"
echo ""
echo "3. Then try migrating again:"
echo "   python manage.py migrate agency"
echo ""
echo "4. If migrations still fail, use the direct SQL approach:"
echo "   python add_pm_field_directly.py"
echo ""
echo "5. After adding the field directly, fake the migration:"
echo "   python manage.py migrate agency 0010 --fake"
echo ""
echo "6. Verify everything worked:"
echo "   python manage.py shell"
echo "   from agency.models import UserProfile"
echo "   UserProfile._meta.get_field('is_project_manager')"
echo "   exit()"