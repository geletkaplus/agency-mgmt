#!/bin/bash

# Fix Migration Issues Script
echo "🔧 Fixing Django Migration Issues..."

# 1. First, let's check the current migration state
echo "📋 Current migration files:"
ls -la agency_management/agency/migrations/

# 2. Check if there's a problematic migration
echo "📋 Checking migration 0010:"
if [ -f "agency_management/agency/migrations/0010_alter_monthlycost_unique_together_and_more.py" ]; then
    echo "Found problematic migration 0010. This appears to be auto-generated and conflicts with our manual migration."
    echo "Moving it to backup..."
    mv agency_management/agency/migrations/0010_alter_monthlycost_unique_together_and_more.py \
       agency_management/agency/migrations/0010_alter_monthlycost_unique_together_and_more.py.problematic
fi

# 3. Create our clean migration for is_project_manager field
echo "📝 Creating clean migration for is_project_manager field..."
cat > agency_management/agency/migrations/0010_add_is_project_manager.py << 'EOF'
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

# 4. Show current migration status
echo ""
echo "📊 Checking migration status..."
echo "Run these commands to check and apply migrations:"
echo ""
echo "# Show migrations status"
echo "python manage.py showmigrations agency"
echo ""
echo "# If there are unapplied migrations, you might need to fake the problematic one:"
echo "python manage.py migrate agency 0009 --fake"
echo ""
echo "# Then apply our new migration:"
echo "python manage.py migrate agency 0010"
echo ""
echo "# Or if needed, reset to a known good state:"
echo "python manage.py migrate agency zero --fake"
echo "python manage.py migrate agency --fake-initial"

# 5. Create a diagnostic script
echo ""
echo "📝 Creating diagnostic script..."
cat > check_models.py << 'EOF'
#!/usr/bin/env python
import os
import sys
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
sys.path.insert(0, os.path.abspath('.'))
django.setup()

from agency.models import *

print("🔍 Checking Models...")
print("\nModels found:")
for model in [Company, UserProfile, Client, Project, ProjectAllocation, MonthlyRevenue, Cost, CapacitySnapshot, Expense, ContractorExpense]:
    try:
        print(f"✓ {model.__name__}: {model.objects.count()} records")
        if hasattr(model, '_meta'):
            fields = [f.name for f in model._meta.get_fields()]
            print(f"  Fields: {', '.join(fields[:5])}{'...' if len(fields) > 5 else ''}")
    except Exception as e:
        print(f"✗ {model.__name__}: Error - {str(e)}")

print("\n🔍 Checking for MonthlyCost and RecurringCost models...")
try:
    from agency.models import MonthlyCost
    print("⚠️  MonthlyCost model still exists in models.py - this should be removed!")
except ImportError:
    print("✓ MonthlyCost model not found (good)")

try:
    from agency.models import RecurringCost
    print("⚠️  RecurringCost model still exists in models.py - this should be removed!")
except ImportError:
    print("✓ RecurringCost model not found (good)")

print("\n🔍 Checking Project model fields...")
try:
    project_fields = [f.name for f in Project._meta.get_fields()]
    if 'billable_rate' in project_fields:
        print("✓ Project has billable_rate field")
    else:
        print("⚠️  Project missing billable_rate field")
    
    if 'calculated_hours' in project_fields:
        print("✓ Project has calculated_hours field")
    else:
        print("⚠️  Project missing calculated_hours field")
        
    if 'team_members' in project_fields:
        print("✓ Project has team_members field")
    else:
        print("⚠️  Project missing team_members field")
except Exception as e:
    print(f"Error checking Project fields: {e}")

print("\n✅ Diagnostic complete!")
EOF

chmod +x check_models.py

# 6. Create a migration reset script
echo ""
echo "📝 Creating migration reset script (use with caution)..."
cat > reset_migrations.sh << 'EOF'
#!/bin/bash
echo "⚠️  WARNING: This will reset migrations. Make sure you have a backup!"
read -p "Are you sure you want to continue? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "Backing up current migrations..."
    mkdir -p migrations_backup
    cp agency_management/agency/migrations/*.py migrations_backup/
    
    echo "Removing migration files (keeping __init__.py)..."
    find agency_management/agency/migrations -name "*.py" -not -name "__init__.py" -delete
    find agency_management/agency/migrations -name "*.pyc" -delete
    
    echo "Creating fresh migrations..."
    python manage.py makemigrations agency
    
    echo "Done! Now you can run: python manage.py migrate --fake-initial"
fi
EOF

chmod +x reset_migrations.sh

echo ""
echo "✅ Migration fix scripts created!"
echo ""
echo "🎯 Recommended steps to fix the issue:"
echo ""
echo "1. First, run the diagnostic to see current state:"
echo "   python check_models.py"
echo ""
echo "2. Check migration status:"
echo "   python manage.py showmigrations agency"
echo ""
echo "3. If you see unapplied migrations after 0009, try:"
echo "   python manage.py migrate agency 0009 --fake"
echo "   python manage.py migrate agency 0010"
echo ""
echo "4. If that doesn't work, you may need to:"
echo "   - Remove the problematic migration file"
echo "   - Run: python manage.py makemigrations"
echo "   - Run: python manage.py migrate"
echo ""
echo "5. As a last resort, use the reset script (BACKUP FIRST!):"
echo "   ./reset_migrations.sh"