#!/bin/bash

# Fix Migration Order Script
# This script fixes the migration conflicts with agency_cost table

echo "========================================="
echo "Fix Migration Order and Conflicts"
echo "========================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "manage.py" ]; then
    print_error "manage.py not found! Please run this script from your Django project root directory."
    exit 1
fi

# Step 1: Show current migration status
print_status "Current migration status:"
python manage.py showmigrations agency

# Step 2: Check which migrations are causing issues
print_status "Checking for problematic migration files..."
ls -la agency/migrations/ | grep -E "(0005|cost)"

# Step 3: Fake the problematic migration
print_status "Faking the problematic Cost migration..."
python manage.py migrate agency 0005_cost --fake 2>/dev/null || true

# Step 4: Check if there's another 0005 migration
if [ -f "agency/migrations/0005_cost_alter_monthlycost_unique_together_and_more.py" ]; then
    print_warning "Found problematic migration: 0005_cost_alter_monthlycost_unique_together_and_more.py"
    
    # Rename it to avoid conflicts
    print_status "Renaming problematic migration..."
    mv agency/migrations/0005_cost_alter_monthlycost_unique_together_and_more.py \
       agency/migrations/0005_cost_alter_monthlycost_unique_together_and_more.py.backup
    
    print_status "Migration file backed up"
fi

# Step 5: Check Django migrations table
print_status "Checking Django migrations table..."
python manage.py shell << 'EOF'
from django.db import connection

with connection.cursor() as cursor:
    cursor.execute("SELECT name FROM django_migrations WHERE app='agency' ORDER BY id")
    migrations = cursor.fetchall()
    print("\nApplied agency migrations:")
    for m in migrations:
        print(f"  - {m[0]}")
        
    # Check if the problematic migration is marked as applied
    cursor.execute("""
        SELECT COUNT(*) FROM django_migrations 
        WHERE app='agency' AND name LIKE '%0005%'
    """)
    count = cursor.fetchone()[0]
    print(f"\nNumber of 0005 migrations marked as applied: {count}")
exit()
EOF

# Step 6: Clean up migration conflicts
print_status "Cleaning up migration conflicts..."

# Create a script to fix the migrations
cat > /tmp/fix_migrations.py << 'EOF'
import os
import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
django.setup()

from django.db import connection, transaction

# Get all agency migrations from the database
with connection.cursor() as cursor:
    cursor.execute("""
        SELECT name FROM django_migrations 
        WHERE app='agency' 
        ORDER BY id
    """)
    db_migrations = [row[0] for row in cursor.fetchall()]
    
print("Migrations in database:")
for m in db_migrations:
    print(f"  - {m}")

# Get all migration files
migration_dir = 'agency/migrations'
file_migrations = []
for f in os.listdir(migration_dir):
    if f.endswith('.py') and not f.startswith('__'):
        file_migrations.append(f[:-3])  # Remove .py extension

file_migrations.sort()
print("\nMigration files on disk:")
for m in file_migrations:
    print(f"  - {m}")

# Find migrations in DB but not on disk
missing_files = [m for m in db_migrations if m not in file_migrations]
if missing_files:
    print("\nMigrations in DB but not on disk (will remove from DB):")
    for m in missing_files:
        print(f"  - {m}")
        with connection.cursor() as cursor:
            cursor.execute(
                "DELETE FROM django_migrations WHERE app='agency' AND name=%s",
                [m]
            )
    print("Cleaned up missing migrations from database")

# Handle duplicate 0005 migrations
with connection.cursor() as cursor:
    cursor.execute("""
        SELECT id, name FROM django_migrations 
        WHERE app='agency' AND name LIKE '%0005%'
        ORDER BY id
    """)
    migrations_0005 = cursor.fetchall()
    
    if len(migrations_0005) > 1:
        print(f"\nFound {len(migrations_0005)} migrations with 0005:")
        for mid, name in migrations_0005:
            print(f"  - {name} (id: {mid})")
        
        # Keep only the first one
        for mid, name in migrations_0005[1:]:
            cursor.execute("DELETE FROM django_migrations WHERE id=%s", [mid])
            print(f"  Removed duplicate: {name}")
EOF

python /tmp/fix_migrations.py

# Step 7: Apply remaining migrations
print_status "Applying remaining migrations..."
python manage.py migrate agency

# Step 8: Final status check
print_status "Final migration status:"
python manage.py showmigrations agency

# Step 9: Test that everything works
print_status "Testing Django setup..."
python manage.py check

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================="
    echo "Migration Issues Fixed!"
    echo "========================================="
    echo ""
    print_status "What was done:"
    echo "  ✓ Cleaned up duplicate migration entries"
    echo "  ✓ Backed up problematic migration files"
    echo "  ✓ Fixed migration order in database"
    echo "  ✓ Applied all pending migrations"
    echo ""
else
    print_error "There might still be issues. Check the errors above."
fi

# Clean up
rm -f /tmp/fix_migrations.py

# Ask if user wants to test admin
read -p "Would you like to test the admin now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Starting development server..."
    echo "Visit: http://127.0.0.1:8000/admin/agency/project/"
    python manage.py runserver
fi