#!/bin/bash

# Fix Team Members Field Script
# This script adds the team_members field to the Project model

echo "========================================="
echo "Fix Team Members Field"
echo "========================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "manage.py" ]; then
    print_error "manage.py not found! Please run this script from your Django project root directory."
    exit 1
fi

# Step 1: Backup models.py
print_status "Backing up models.py..."
cp agency/models.py agency/models.py.backup.team_members.$(date +%Y%m%d_%H%M%S)

# Step 2: Update models.py to add team_members field
print_status "Adding team_members field to Project model..."

# Use Python to safely add the field to the Project model
python3 << 'EOF'
import re

# Read the current models.py
with open('agency/models.py', 'r') as f:
    content = f.read()

# Check if team_members already exists
if 'team_members' in content and 'ManyToManyField' in content:
    print("✓ team_members field already exists in Project model")
else:
    # Find the Project class and add the field
    # Look for the class definition and add after the last field before methods
    
    # Pattern to find the Project class
    project_class_pattern = r'(class Project\(.*?\):.*?)((?:\n    def|\n\nclass|\Z))'
    
    def add_team_members_field(match):
        class_content = match.group(1)
        next_section = match.group(2)
        
        # Add the team_members field before the first method or end of class
        team_members_field = '''
    team_members = models.ManyToManyField(
        'UserProfile',
        related_name='assigned_projects',
        blank=True,
        help_text='Team members assigned to this project'
    )
'''
        
        return class_content + team_members_field + next_section
    
    # Apply the replacement
    content = re.sub(project_class_pattern, add_team_members_field, content, flags=re.DOTALL)
    
    # Write back
    with open('agency/models.py', 'w') as f:
        f.write(content)
    
    print("✓ Added team_members field to Project model")

EOF

# Step 3: Create a simpler admin.py that doesn't reference team_members until after migration
print_status "Creating temporary admin.py without team_members reference..."

cat > agency/admin_temp.py << 'EOF'
# Temporary admin.py - basic version without team_members
from django.contrib import admin
from django.db.models import Sum
from django.utils.safestring import mark_safe
from decimal import Decimal

# Import models
from .models import (
    Company, UserProfile, Client, Project, 
    ProjectAllocation, Expense, ContractorExpense
)

# Try to import optional models
try:
    from .models import Cost, CapacitySnapshot
    COST_MODEL_EXISTS = True
except ImportError:
    COST_MODEL_EXISTS = False

try:
    from .models import MonthlyRevenue
    MONTHLY_REVENUE_EXISTS = True
except ImportError:
    MONTHLY_REVENUE_EXISTS = False


@admin.register(Company)
class CompanyAdmin(admin.ModelAdmin):
    list_display = ['name', 'code', 'created_at']
    search_fields = ['name', 'code']


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ['user', 'company', 'role', 'status', 'hourly_rate']
    list_filter = ['role', 'status', 'company']
    search_fields = ['user__username', 'user__first_name', 'user__last_name']


@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
    list_display = ['name', 'company', 'status', 'account_manager']
    list_filter = ['status', 'company']
    search_fields = ['name']


@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    list_display = ['name', 'client', 'status', 'start_date', 'end_date', 'total_revenue']
    list_filter = ['status', 'project_type', 'company']
    search_fields = ['name', 'client__name']
    date_hierarchy = 'start_date'
    
    fieldsets = (
        ('Project Information', {
            'fields': ('name', 'client', 'company', 'project_type', 'status')
        }),
        ('Timeline', {
            'fields': ('start_date', 'end_date')
        }),
        ('Financials', {
            'fields': ('total_revenue', 'total_hours'),
        }),
        ('Management', {
            'fields': ('project_manager',)
        })
    )


@admin.register(ProjectAllocation)
class ProjectAllocationAdmin(admin.ModelAdmin):
    list_display = ['project', 'user_profile', 'year', 'month', 'allocated_hours']
    list_filter = ['year', 'month', 'project__company']
    search_fields = ['project__name']


@admin.register(Expense)
class ExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'category', 'monthly_amount', 'is_active']
    list_filter = ['category', 'is_active', 'company']


@admin.register(ContractorExpense)
class ContractorExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'year', 'month', 'amount']
    list_filter = ['year', 'month', 'company']


if COST_MODEL_EXISTS:
    @admin.register(Cost)
    class CostAdmin(admin.ModelAdmin):
        list_display = ['name', 'cost_type', 'amount', 'frequency', 'is_active']
        list_filter = ['cost_type', 'frequency', 'is_active', 'company']


if MONTHLY_REVENUE_EXISTS:
    @admin.register(MonthlyRevenue)
    class MonthlyRevenueAdmin(admin.ModelAdmin):
        list_display = ['client', 'project', 'year', 'month', 'revenue']
        list_filter = ['year', 'month', 'company']


admin.site.site_header = "Agency Management Admin"
admin.site.site_title = "Agency Management"
admin.site.index_title = "Welcome to Agency Management"
EOF

# Step 4: Replace admin.py with temporary version
print_status "Switching to temporary admin.py..."
mv agency/admin.py agency/admin_with_team.py
mv agency/admin_temp.py agency/admin.py

# Step 5: Create and run migration
print_status "Creating migration for team_members field..."
python manage.py makemigrations agency -n add_team_members_to_project

print_status "Running migration..."
python manage.py migrate agency

# Step 6: Restore full admin.py
print_status "Restoring full admin.py with team features..."
mv agency/admin_with_team.py agency/admin.py

# Step 7: Test that everything works
print_status "Testing setup..."
python manage.py check

if [ $? -eq 0 ]; then
    print_status "✓ Everything is working!"
else
    print_error "There might still be issues. Check the error messages above."
fi

# Step 8: Summary
echo ""
echo "========================================="
echo "Team Members Field Fixed!"
echo "========================================="
echo ""
print_status "What happened:"
echo "  ✓ Added team_members field to Project model"
echo "  ✓ Created and ran migration"
echo "  ✓ Restored full admin with team features"
echo ""
print_status "You can now:"
echo "  1. Edit any project in admin"
echo "  2. Use the 'Team Members' field to assign people"
echo "  3. Save to see the allocation grid"
echo ""

# Ask if user wants to start server
read -p "Would you like to start the server and test? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Starting development server..."
    echo "Visit: http://127.0.0.1:8000/admin/agency/project/"
    python manage.py runserver
fi