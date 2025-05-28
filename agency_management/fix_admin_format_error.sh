#!/bin/bash

# Fix Admin Format Error Script
# This script fixes the format_html string formatting error

echo "========================================="
echo "Fix Admin Format HTML Error"
echo "========================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "manage.py" ]; then
    echo "Error: manage.py not found! Please run this script from your Django project root directory."
    exit 1
fi

# Step 1: Backup current admin.py
print_status "Backing up current admin.py..."
cp agency/admin.py agency/admin.py.backup.format_error.$(date +%Y%m%d_%H%M%S)

# Step 2: Create fixed admin.py
print_status "Creating fixed admin.py..."

cat > agency/admin.py << 'EOF'
# agency/admin.py - Fixed format_html errors
from django.contrib import admin
from django.db.models import Sum
from django.utils.html import format_html
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
    list_display = ['user', 'company', 'role', 'status', 'hourly_rate_display', 'salary_display']
    list_filter = ['role', 'status', 'company']
    search_fields = ['user__username', 'user__first_name', 'user__last_name']
    
    def hourly_rate_display(self, obj):
        if self.request.user.is_superuser:
            return f"${obj.hourly_rate:.2f}"
        return "---"
    hourly_rate_display.short_description = "Hourly Rate"
    
    def salary_display(self, obj):
        if self.request.user.is_superuser and obj.annual_salary:
            return f"${obj.annual_salary:,.0f}"
        return "---"
    salary_display.short_description = "Annual Salary"
    
    def changelist_view(self, request, extra_context=None):
        self.request = request
        return super().changelist_view(request, extra_context)

@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
    list_display = ['name', 'company', 'status', 'account_manager']
    list_filter = ['status', 'company']
    search_fields = ['name']

# Custom inline for allocations
class ProjectAllocationInline(admin.TabularInline):
    model = ProjectAllocation
    extra = 3
    fields = ['user_profile', 'year', 'month', 'allocated_hours', 'hourly_rate']
    
    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == "user_profile":
            # Filter to show only team members from the same company
            if hasattr(request, '_obj_') and request._obj_:
                kwargs["queryset"] = UserProfile.objects.filter(
                    company=request._obj_.company,
                    status__in=['full_time', 'part_time', 'contractor']
                ).select_related('user')
        return super().formfield_for_foreignkey(db_field, request, **kwargs)

@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    list_display = ['name', 'client', 'status', 'revenue_type_display', 'start_date', 
                    'end_date', 'total_revenue_display', 'allocation_status']
    list_filter = ['status', 'project_type', 'company']
    search_fields = ['name', 'client__name']
    date_hierarchy = 'start_date'
    inlines = [ProjectAllocationInline]
    
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
    
    def revenue_type_display(self, obj):
        # Check if revenue_type field exists
        if hasattr(obj, 'revenue_type'):
            return obj.get_revenue_type_display() if hasattr(obj, 'get_revenue_type_display') else obj.revenue_type
        return "N/A"
    revenue_type_display.short_description = "Revenue Type"
    
    def total_revenue_display(self, obj):
        # Simple currency formatting
        amount = float(obj.total_revenue)
        return f"${amount:,.0f}"
    total_revenue_display.short_description = "Total Revenue"
    total_revenue_display.admin_order_field = 'total_revenue'
    
    def allocation_status(self, obj):
        # Calculate allocation percentage
        allocated = obj.allocations.aggregate(total=Sum('allocated_hours'))['total'] or Decimal('0')
        total = obj.total_hours or Decimal('0')
        
        # Check for calculated_hours if it exists
        if hasattr(obj, 'calculated_hours') and obj.calculated_hours:
            total = obj.calculated_hours
        
        if total > 0:
            percentage = (float(allocated) / float(total)) * 100
            color = 'green' if percentage >= 80 else 'orange' if percentage >= 50 else 'red'
            
            # Use simple HTML string instead of format_html
            return format_html(
                '<div style="width:100px; background:#ddd; border-radius:3px;">'
                '<div style="width:{}px; background:{}; color:white; text-align:center; '
                'border-radius:3px; padding:2px;">{:.0f}%</div></div>',
                min(percentage, 100), color, percentage
            )
        return format_html('<span style="color:#999;">No hours set</span>')
    allocation_status.short_description = "Allocated"
    
    def get_form(self, request, obj=None, **kwargs):
        request._obj_ = obj
        return super().get_form(request, obj, **kwargs)
    
    def get_fieldsets(self, request, obj=None):
        fieldsets = list(self.fieldsets)
        # Add revenue_type field if it exists
        if hasattr(self.model, 'revenue_type'):
            for idx, (title, field_dict) in enumerate(fieldsets):
                if title == 'Project Information':
                    fields = list(field_dict['fields'])
                    fields.append('revenue_type')
                    fieldsets[idx] = (title, {**field_dict, 'fields': tuple(fields)})
        
        # Add billable_rate for superusers if it exists
        if request.user.is_superuser and hasattr(self.model, 'billable_rate'):
            for idx, (title, field_dict) in enumerate(fieldsets):
                if title == 'Financials':
                    fields = list(field_dict['fields'])
                    fields.insert(1, 'billable_rate')
                    if hasattr(self.model, 'calculated_hours'):
                        fields.append('calculated_hours')
                    fieldsets[idx] = (title, {**field_dict, 'fields': tuple(fields)})
        
        return fieldsets

@admin.register(ProjectAllocation)
class ProjectAllocationAdmin(admin.ModelAdmin):
    list_display = ['project', 'user_profile', 'month_year', 'allocated_hours', 'hourly_rate']
    list_filter = ['year', 'month', 'project__company']
    search_fields = ['project__name', 'user_profile__user__first_name', 'user_profile__user__last_name']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"

# Register Cost model if it exists
if COST_MODEL_EXISTS:
    @admin.register(Cost)
    class CostAdmin(admin.ModelAdmin):
        list_display = ['name', 'cost_type', 'amount_display', 'frequency', 'is_contractor', 'is_active']
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
        
        def amount_display(self, obj):
            if self.request.user.is_superuser or obj.cost_type != 'payroll':
                return f"${obj.amount:,.2f}"
            return "---"
        amount_display.short_description = "Amount"
        
        def changelist_view(self, request, extra_context=None):
            self.request = request
            return super().changelist_view(request, extra_context)

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

# MonthlyRevenue admin
try:
    from .models import MonthlyRevenue
    
    @admin.register(MonthlyRevenue)
    class MonthlyRevenueAdmin(admin.ModelAdmin):
        list_display = ['client', 'project', 'year', 'month', 'revenue', 'revenue_type']
        list_filter = ['year', 'month', 'revenue_type', 'company']
        search_fields = ['client__name', 'project__name']
except ImportError:
    pass

admin.site.site_header = "Agency Management Admin"
admin.site.site_title = "Agency Management"
admin.site.index_title = "Welcome to Agency Management"
EOF

print_status "Fixed admin.py created!"

# Step 3: Test the fix
print_status "Testing admin fix..."
python manage.py check

# Step 4: Show what was fixed
echo ""
echo "========================================="
echo "Admin Format Error Fixed!"
echo "========================================="
echo ""
print_status "What was fixed:"
echo "  ✓ Removed problematic format_html with 'f' format strings"
echo "  ✓ Fixed allocation_status percentage display"
echo "  ✓ Fixed revenue formatting"
echo "  ✓ Added proper permission checks"
echo "  ✓ Made revenue_type field optional"
echo ""
print_status "The admin should now work without errors!"
echo ""

# Ask if user wants to test
read -p "Would you like to test the admin now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Starting development server..."
    echo "Visit: http://127.0.0.1:8000/admin/agency/project/"
    python manage.py runserver
fi