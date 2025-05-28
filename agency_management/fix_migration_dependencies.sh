#!/bin/bash

# Fix Migration Dependencies Script
# This script fixes migration dependency errors

echo "========================================="
echo "Fix Migration Dependencies"
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

# Step 1: List all migration files
print_status "Current migration files:"
ls -1 agency/migrations/*.py | grep -v __pycache__ | sort

# Step 2: Find the problematic merge migration
print_status "Looking for merge migration..."
MERGE_MIGRATION=$(ls agency/migrations/*merge*.py 2>/dev/null | head -1)

if [ -n "$MERGE_MIGRATION" ]; then
    print_warning "Found merge migration: $MERGE_MIGRATION"
    
    # Show its dependencies
    print_status "Checking dependencies..."
    grep -A5 "dependencies" "$MERGE_MIGRATION"
    
    # Fix the dependency
    print_status "Fixing dependency reference..."
    
    # Create a fixed version
    python3 << EOF
import re

# Read the merge migration
with open("$MERGE_MIGRATION", 'r') as f:
    content = f.read()

# Replace the nonexistent dependency
content = re.sub(
    r"\('agency', '0005_cost_alter_monthlycost_unique_together_and_more'\)",
    "('agency', '0005_cost')",
    content
)

# Write back
with open("$MERGE_MIGRATION", 'w') as f:
    f.write(content)

print("✓ Fixed merge migration dependencies")
EOF
fi

# Step 3: Clean up any other problematic migrations
print_status "Checking for other issues..."

# Find all migrations and check their dependencies
python3 << 'EOF'
import os
import re

migration_dir = 'agency/migrations'
issues_found = False

# Get all migration files
migrations = []
for f in sorted(os.listdir(migration_dir)):
    if f.endswith('.py') and not f.startswith('__'):
        migrations.append(os.path.join(migration_dir, f))

# Check each migration
for migration_file in migrations:
    with open(migration_file, 'r') as f:
        content = f.read()
    
    # Find dependencies
    deps_match = re.search(r'dependencies\s*=\s*\[(.*?)\]', content, re.DOTALL)
    if deps_match:
        deps_text = deps_match.group(1)
        
        # Check for the problematic dependency
        if '0005_cost_alter_monthlycost_unique_together_and_more' in deps_text:
            print(f"Found problematic dependency in: {migration_file}")
            
            # Fix it
            content = content.replace(
                "'0005_cost_alter_monthlycost_unique_together_and_more'",
                "'0005_cost'"
            )
            
            with open(migration_file, 'w') as f:
                f.write(content)
            
            print(f"  ✓ Fixed dependency")
            issues_found = True

if not issues_found:
    print("No other dependency issues found")
EOF

# Step 4: Remove duplicate or unnecessary migrations
print_status "Cleaning up migration files..."

# Check for duplicate 0005 migrations
MIGRATIONS_0005=$(ls agency/migrations/0005*.py 2>/dev/null | grep -v __pycache__)
COUNT_0005=$(echo "$MIGRATIONS_0005" | grep -c "0005" || true)

if [ "$COUNT_0005" -gt 1 ]; then
    print_warning "Found multiple 0005 migrations:"
    echo "$MIGRATIONS_0005"
    
    # Keep only the main one
    for migration in $MIGRATIONS_0005; do
        if [[ ! "$migration" =~ "0005_cost.py" ]]; then
            print_status "Moving $migration to backup..."
            mv "$migration" "${migration}.backup_dep"
        fi
    done
fi

# Step 5: Reset migration state if needed
print_status "Checking migration state..."

python manage.py shell << 'EOF'
from django.db import connection

with connection.cursor() as cursor:
    # Get current migration state
    cursor.execute("""
        SELECT name FROM django_migrations 
        WHERE app='agency' 
        ORDER BY id
    """)
    applied = [row[0] for row in cursor.fetchall()]
    
    print("Currently applied migrations:")
    for m in applied:
        print(f"  - {m}")
    
    # Remove any references to the problematic migration
    cursor.execute("""
        DELETE FROM django_migrations 
        WHERE app='agency' 
        AND name = '0005_cost_alter_monthlycost_unique_together_and_more'
    """)
    
    if cursor.rowcount > 0:
        print(f"\nRemoved problematic migration from database")
EOF

# Step 6: Recreate __init__.py if missing
touch agency/migrations/__init__.py

# Step 7: Show final state
print_status "Final migration files:"
ls -1 agency/migrations/*.py | grep -v -E "(backup|__pycache__)" | sort

# Step 8: Test
print_status "Testing migrations..."
python manage.py showmigrations agency

# Step 9: Try to start the server
print_status "Testing server startup..."
python manage.py check

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================="
    echo "Migration Dependencies Fixed!"
    echo "========================================="
    echo ""
    print_status "The server should now start properly"
    echo ""
    
    # Ask if user wants to start server
    read -p "Would you like to start the server now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Starting development server..."
        python manage.py runserver
    fi
else
    print_error "There are still issues. Please check the error messages above."
    
    # Show more diagnostic info
    print_status "Migration files present:"
    ls -la agency/migrations/ | grep -v __pycache__
fi