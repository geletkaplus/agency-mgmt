#!/bin/bash

# Fix Migration Conflict Script
# This script fixes the "table already exists" migration error

echo "========================================="
echo "Fix Migration Conflict - agency_cost"
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

# Step 1: Check current migration status
print_status "Checking current migration status..."
python manage.py showmigrations agency

# Step 2: Check if the table exists
print_status "Checking if agency_cost table exists..."
python manage.py shell << 'EOF'
from django.db import connection

with connection.cursor() as cursor:
    cursor.execute("""
        SELECT name FROM sqlite_master 
        WHERE type='table' AND name='agency_cost';
    """)
    result = cursor.fetchone()
    if result:
        print("✓ Table 'agency_cost' exists in database")
    else:
        print("✗ Table 'agency_cost' does NOT exist")
exit()
EOF

# Step 3: Ask user how to proceed
echo ""
print_warning "The table 'agency_cost' already exists but migration 0005 wants to create it."
echo ""
echo "Choose how to fix this:"
echo "1) Mark migration 0005 as already applied (fake it)"
echo "2) Delete the existing table and run migration normally"
echo "3) Skip migration 0005 and continue with others"
echo ""
read -p "Enter your choice (1-3): " choice

case $choice in
    1)
        print_status "Marking migration 0005 as already applied..."
        python manage.py migrate agency 0005 --fake
        
        if [ $? -eq 0 ]; then
            print_status "Migration 0005 marked as applied successfully!"
            
            # Apply remaining migrations
            print_status "Applying remaining migrations..."
            python manage.py migrate agency
        else
            print_error "Failed to fake migration"
        fi
        ;;
        
    2)
        print_warning "This will DELETE all data in the agency_cost table!"
        read -p "Are you sure? (y/n): " confirm
        
        if [[ $confirm =~ ^[Yy]$ ]]; then
            print_status "Dropping agency_cost table..."
            python manage.py shell << 'EOF'
from django.db import connection

with connection.cursor() as cursor:
    # Drop indexes first
    cursor.execute("DROP INDEX IF EXISTS agency_cost_company_start_idx;")
    cursor.execute("DROP INDEX IF EXISTS agency_cost_type_contractor_idx;")
    # Drop the table
    cursor.execute("DROP TABLE IF EXISTS agency_cost;")
    print("✓ Table 'agency_cost' dropped")
exit()
EOF
            
            print_status "Running migrations normally..."
            python manage.py migrate agency
        else
            print_status "Operation cancelled"
        fi
        ;;
        
    3)
        print_status "Creating a custom migration to skip 0005..."
        
        # First, fake the problematic migration
        python manage.py migrate agency 0004
        python manage.py migrate agency 0005 --fake
        
        # Then continue with the rest
        python manage.py migrate agency
        ;;
        
    *)
        print_error "Invalid choice"
        exit 1
        ;;
esac

# Step 4: Verify the fix
print_status "Verifying migration status..."
python manage.py showmigrations agency

# Step 5: Test that the Cost model works
print_status "Testing Cost model..."
python manage.py shell << 'EOF'
try:
    from agency.models import Cost
    print("✓ Cost model imports successfully")
    
    # Try to query it
    count = Cost.objects.count()
    print(f"✓ Cost table has {count} records")
except Exception as e:
    print(f"✗ Error with Cost model: {e}")
exit()
EOF

# Step 6: Apply any remaining migrations for other apps
print_status "Applying all remaining migrations..."
python manage.py migrate

# Step 7: Final status check
echo ""
echo "========================================="
echo "Migration Conflict Resolution Complete!"
echo "========================================="
echo ""

print_status "Current status:"
python manage.py showmigrations agency | tail -10

echo ""
print_status "Next steps:"
echo "  1. Test the admin interface: http://127.0.0.1:8000/admin/agency/cost/"
echo "  2. If you chose option 1 (fake), the existing data is preserved"
echo "  3. If you chose option 2 (drop), you'll need to re-enter cost data"
echo ""

# Ask if user wants to check admin
read -p "Would you like to start the server and check admin? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Starting development server..."
    echo "Visit: http://127.0.0.1:8000/admin/agency/cost/"
    python manage.py runserver
fi