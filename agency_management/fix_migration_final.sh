#!/bin/bash

echo "🔧 Final Migration Fix..."
echo ""

# 1. First, let's check what migration files exist
echo "📋 Checking migration files in the correct path..."
ls -la agency/migrations/00*.py 2>/dev/null || echo "Migration files not found in agency/migrations/"

# 2. Let's look for the problematic migration file
echo ""
echo "📋 Looking for the problematic migration file..."
if [ -f "agency/migrations/0010_alter_monthlycost_unique_together_and_more.py" ]; then
    echo "❌ Found problematic migration file!"
    echo "Content preview:"
    head -20 agency/migrations/0010_alter_monthlycost_unique_together_and_more.py
    
    echo ""
    echo "This migration is trying to modify MonthlyCost which doesn't exist in your models."
    echo "Let's rename it to disable it:"
    mv agency/migrations/0010_alter_monthlycost_unique_together_and_more.py \
       agency/migrations/0010_alter_monthlycost_unique_together_and_more.py.disabled
    echo "✅ Migration file disabled"
else
    echo "✅ Problematic migration file not found (good!)"
fi

# 3. Create our proper migration
echo ""
echo "📋 Creating proper migration for is_project_manager field..."
cat > agency/migrations/0010_add_is_project_manager.py << 'EOF'
# Manual migration for is_project_manager field

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

echo "✅ Created new migration: 0010_add_is_project_manager.py"

# 4. Create a Python script to add the field directly (backup approach)
echo ""
echo "📋 Creating direct field addition script..."
cat > add_pm_field.py << 'EOF'
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
EOF

# 5. Update models.py to ensure the field is there
echo ""
echo "📋 Creating models.py update patch..."
cat > update_models.py << 'EOF'
import os

print("📝 Checking if is_project_manager field is in models.py...")

models_path = "agency/models.py"
with open(models_path, 'r') as f:
    content = f.read()

if 'is_project_manager' in content:
    print("✅ Field already in models.py")
else:
    print("❌ Field not found in models.py")
    print("   Adding it now...")
    
    # Find the UserProfile class and add the field
    lines = content.split('\n')
    new_lines = []
    in_userprofile = False
    field_added = False
    
    for i, line in enumerate(lines):
        new_lines.append(line)
        
        if 'class UserProfile' in line:
            in_userprofile = True
        
        if in_userprofile and not field_added and 'utilization_target' in line:
            # Add after utilization_target field
            new_lines.append('    is_project_manager = models.BooleanField(default=False, help_text="Can manage projects and see PM dashboard")')
            field_added = True
            print("✅ Added is_project_manager field after utilization_target")
    
    if field_added:
        with open(models_path, 'w') as f:
            f.write('\n'.join(new_lines))
        print("✅ models.py updated!")
    else:
        print("⚠️  Could not automatically add field. Please add manually:")
        print("    is_project_manager = models.BooleanField(default=False, help_text=\"Can manage projects and see PM dashboard\")")
EOF

echo ""
echo "✅ All fix scripts created!"
echo ""
echo "🎯 Follow these steps to resolve the issue:"
echo ""
echo "1. First, ensure the field is in your models.py:"
echo "   python update_models.py"
echo ""
echo "2. Then run the migration:"
echo "   python manage.py migrate agency 0010"
echo ""
echo "3. If migration fails, add the field directly:"
echo "   python add_pm_field.py"
echo ""
echo "4. If you added the field directly, fake the migration:"
echo "   python manage.py migrate agency 0010 --fake"
echo ""
echo "5. Verify everything works:"
echo "   python manage.py shell"
echo "   >>> from agency.models import UserProfile"
echo "   >>> UserProfile.objects.filter(is_project_manager=True).count()"
echo "   >>> exit()"