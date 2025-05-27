#!/bin/bash

# Django Migration Fix Script
# This script will fix migration issues and ensure all models are properly migrated

echo "========================================="
echo "Django Migration Fix Script"
echo "========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "manage.py" ]; then
    print_error "manage.py not found! Please run this script from your Django project root directory."
    exit 1
fi

# Step 1: Backup the database
print_status "Creating database backup..."
if [ -f "db.sqlite3" ]; then
    cp db.sqlite3 db.sqlite3.backup.$(date +%Y%m%d_%H%M%S)
    print_status "Database backed up successfully"
else
    print_warning "No database file found to backup"
fi

# Step 2: Check current migration status
print_status "Checking current migration status..."
python manage.py showmigrations agency

# Step 3: Create the Cost model migration if it doesn't exist
print_status "Creating migration for Cost model..."
cat > agency/migrations/0005_cost.py << 'EOF'
# Generated manually for Cost model

from django.db import migrations, models
import django.db.models.deletion
import uuid

class Migration(migrations.Migration):

    dependencies = [
        ('agency', '0004_add_revenue_type_to_project'),
    ]

    operations = [
        migrations.CreateModel(
            name='Cost',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('name', models.CharField(max_length=200)),
                ('cost_type', models.CharField(choices=[('contractor', 'Contractor'), ('payroll', 'Payroll'), ('rent', 'Rent'), ('utilities', 'Utilities'), ('software', 'Software/Technology'), ('office', 'Office Supplies'), ('marketing', 'Marketing'), ('travel', 'Travel'), ('professional', 'Professional Services'), ('insurance', 'Insurance'), ('other', 'Other')], max_length=20)),
                ('description', models.TextField(blank=True)),
                ('amount', models.DecimalField(decimal_places=2, max_digits=10)),
                ('frequency', models.CharField(choices=[('monthly', 'Monthly Recurring'), ('one_time', 'One Time'), ('project_duration', 'Spread Over Project Duration')], default='monthly', max_length=20)),
                ('start_date', models.DateField()),
                ('end_date', models.DateField(blank=True, null=True)),
                ('is_contractor', models.BooleanField(default=False)),
                ('vendor', models.CharField(blank=True, max_length=200)),
                ('is_billable', models.BooleanField(default=False)),
                ('is_active', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('company', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='costs', to='agency.company')),
                ('project', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='costs', to='agency.project')),
            ],
            options={
                'indexes': [
                    models.Index(fields=['company', 'start_date'], name='agency_cost_company_start_idx'),
                    models.Index(fields=['cost_type', 'is_contractor'], name='agency_cost_type_contractor_idx'),
                ],
            },
        ),
    ]
EOF

print_status "Migration file created"

# Step 4: Apply all migrations
print_status "Applying migrations..."
python manage.py migrate

# Step 5: Check if migrations were successful
if [ $? -eq 0 ]; then
    print_status "Migrations applied successfully!"
else
    print_error "Migration failed. Checking for issues..."
    
    # Try to create migrations automatically
    print_status "Attempting to create migrations automatically..."
    python manage.py makemigrations agency
    
    # Apply again
    print_status "Applying migrations again..."
    python manage.py migrate
fi

# Step 6: Verify the database structure
print_status "Verifying database structure..."
python manage.py dbshell << EOF
.tables
.exit
EOF

# Step 7: Create superuser if it doesn't exist
print_status "Checking for superuser..."
python manage.py shell << EOF
from django.contrib.auth.models import User
if not User.objects.filter(is_superuser=True).exists():
    print("No superuser found. Please create one.")
else:
    print("Superuser exists.")
exit()
EOF

# Step 8: Collect static files (if needed)
print_status "Collecting static files..."
python manage.py collectstatic --noinput 2>/dev/null || print_warning "Static files collection skipped (STATIC_ROOT not configured)"

# Step 9: Run a test server check
print_status "Running system check..."
python manage.py check

# Step 10: Final migration status
print_status "Final migration status:"
python manage.py showmigrations agency

echo ""
echo "========================================="
echo "Migration fix complete!"
echo "========================================="
echo ""
print_status "Next steps:"
echo "  1. Start the development server: python manage.py runserver"
echo "  2. Visit http://127.0.0.1:8000/admin/agency/cost/"
echo "  3. If you need a superuser, run: python manage.py createsuperuser"
echo ""
print_status "Database backup saved as: db.sqlite3.backup.*"

# Optional: Ask if user wants to start the server
read -p "Would you like to start the development server now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Starting development server..."
    python manage.py runserver
fi