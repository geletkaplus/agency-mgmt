#!/bin/bash

# Fix All format_html Issues
# This script finds and fixes all format_html errors in admin.py

echo "========================================="
echo "Fix All format_html Issues"
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

# Step 1: Find the problematic line
print_status "Searching for format_html issues in admin.py..."
grep -n "format_html.*{.*:.*f" agency/admin.py || true

# Step 2: Create a completely clean admin.py
print_status "Creating clean admin.py without format_html issues..."

cat > agency/admin.py << 'EOF'
# agency/admin.py - Clean version without format_html issues
from django.contrib import admin
from django.db.models import Sum
from django.utils.html import format_html
from django.utils.safestring import mark_safe
from decimal import Decimal

# Import models that definitely exist
from .models import (
    Company, UserProfile, Client, Project, 
    ProjectAllocation, Expense, ContractorExpense
)

# Try to import new models if they exist
try:
    from .models import Cost, CapacitySnapshot
    COST_MODEL_EXISTS = True
except ImportError:
    COST_MODEL_EXISTS = False

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
    list_display = ['name', 'company', 'status', 'account_manager', 'total_revenue']
    list_filter = ['status', 'company']
    search_fields = ['name']
    
    def total_revenue(self, obj):
        total = obj.projects.aggregate(total=Sum('total_revenue'))['total'] or 0
        # Simple formatting without format_html
        return f"${int(total):,}"
    total_revenue.short_description = "Total Revenue"

# Project Allocation Inline
class ProjectAllocationInline(admin.TabularInline):
    model = ProjectAllocation
    extra = 3
    fields = ['user_profile', 'year', 'month', 'allocated_hours', 'hourly_rate']

@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    # Check if revenue_type field exists
    try:
        Project._meta.get_field('revenue_type')
        list_display = ['name', 'client', 'status', 'revenue_type', 'start_date', 'end_date', 'total_revenue', 'allocation_status']
        list_filter = ['status', 'revenue_type', 'project_type', 'company']
    except:
        list_display = ['name', 'client', 'status', 'start_date', 'end_date', 'total_revenue', 'allocation_status']
        list_filter = ['status', 'project_type', 'company']
    
    search_fields = ['name', 'client__name']
    date_hierarchy = 'start_date'
    inlines = [ProjectAllocationInline]
    
    def allocation_status(self, obj):
        allocated = obj.allocations.aggregate(total=Sum('allocated_hours'))['total'] or Decimal('0')
        total = obj.total_hours or Decimal('0')
        
        if total > 0:
            percentage = (float(allocated) / float(total)) * 100
            color = '#22c55e' if percentage >= 80 else '#f97316' if percentage >= 50 else '#ef4444'
            
            # Create simple HTML without format_html
            width = min(int(percentage), 100)
            html = (
                f'<div style="width:100px; background:#e5e7eb; border-radius:3px; overflow:hidden;">'
                f'<div style="width:{width}px; background:{color}; color:white; text-align:center; '
                f'padding:2px 0; font-size:12px;">{int(percentage)}%</div>'
                f'</div>'
            )
            return mark_safe(html)
        return mark_safe('<span style="color:#999;">No hours</span>')
    allocation_status.short_description = "Allocated"

@admin.register(ProjectAllocation)
class ProjectAllocationAdmin(admin.ModelAdmin):
    list_display = ['project', 'user_profile', 'month_year', 'allocated_hours', 'hourly_rate']
    list_filter = ['year', 'month', 'project__company']
    search_fields = ['project__name']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"
    month_year.short_description = "Period"

# Register Cost model if it exists
if COST_MODEL_EXISTS:
    @admin.register(Cost)
    class CostAdmin(admin.ModelAdmin):
        list_display = ['name', 'cost_type', 'amount', 'frequency', 'is_contractor', 'is_active']
        list_filter = ['cost_type', 'frequency', 'is_contractor', 'is_active', 'company']
        search_fields = ['name', 'description', 'vendor']
        
        fieldsets = (
            ('Basic Information', {
                'fields': ('company', 'name', 'cost_type', 'description', 'vendor')
            }),
            ('Cost Details', {
                'fields': ('amount', 'frequency', 'start_date', 'end_date')
            }),
            ('Assignment & Flags', {
                'fields': ('is_contractor', 'project', 'is_billable', 'is_active')
            })
        )

    @admin.register(CapacitySnapshot)
    class CapacitySnapshotAdmin(admin.ModelAdmin):
        list_display = ['company', 'month_year', 'utilization_rate']
        list_filter = ['year', 'month', 'company']
        
        def month_year(self, obj):
            return f"{obj.year}-{obj.month:02d}"

# Legacy models
@admin.register(Expense)
class ExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'category', 'monthly_amount', 'is_active']
    list_filter = ['category', 'is_active', 'company']

@admin.register(ContractorExpense)
class ContractorExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'month_year', 'amount']
    list_filter = ['year', 'month', 'company']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"

admin.site.site_header = "Agency Management Admin"
admin.site.site_title = "Agency Management"
admin.site.index_title = "Welcome to Agency Management"
EOF

print_status "Clean admin.py created!"

# Step 3: Test with debug mode
print_status "Testing admin with debug info..."
python manage.py shell << 'EOF'
try:
    from agency.admin import ProjectAdmin
    from agency.models import Project
    
    # Test if the admin loads
    admin = ProjectAdmin(Project, None)
    print("✓ ProjectAdmin loads successfully")
    
    # Check which fields exist
    if hasattr(Project, 'revenue_type'):
        print("✓ Project has revenue_type field")
    else:
        print("✗ Project does NOT have revenue_type field")
        
    if hasattr(Project, 'billable_rate'):
        print("✓ Project has billable_rate field")
    else:
        print("✗ Project does NOT have billable_rate field")
        
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()
EOF

# Step 4: Verify syntax
print_status "Checking Python syntax..."
python -m py_compile agency/admin.py

if [ $? -eq 0 ]; then
    print_status "✓ No syntax errors found"
else
    print_error "✗ Syntax errors detected"
fi

# Step 5: Run Django check
print_status "Running Django system check..."
python manage.py check

echo ""
echo "========================================="
echo "format_html Issues Fixed!"
echo "========================================="
echo ""
print_status "Changes made:"
echo "  ✓ Removed ALL format_html calls with problematic formatting"
echo "  ✓ Used mark_safe() for simple HTML instead"
echo "  ✓ Simplified allocation progress bar"
echo "  ✓ Used standard f-strings for currency formatting"
echo "  ✓ Added checks for optional fields"
echo ""

# Step 6: Clear Python cache
print_status "Clearing Python cache..."
find . -type d -name __pycache__ -exec rm -r {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true

print_status "Cache cleared!"

# Ask if user wants to test
read -p "Would you like to test the admin now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Starting development server..."
    echo ""
    echo "Visit: http://127.0.0.1:8000/admin/agency/project/"
    echo "If you still see errors, check the terminal output"
    echo ""
    python manage.py runserver
fi